module llsdk.client;

import core.thread;

import std.base64;
import std.conv;
import std.functional;
import std.string;
import std.stdio;
import std.digest;
import std.random;
import std.datetime.stopwatch;

import tinyredis;
import tinyredis.subscriber;


import llsdk.errors;
import llsdk.durations;

public:

class LLClient {
  private Redis pub;
  private Subscriber sub;
  private string redis_host, prefix,
          cli_channel, bus_channel;
  private ushort redis_port;
  private string name;

  private Random rnd;

  this(string redis_host = "127.0.0.1", 
      ushort redis_port = 6379,
      string prefix = "dobaosll", 
      string name = "llclient") {

    this.name = name;
    this.redis_host = redis_host;
    this.redis_port = redis_port;
    this.prefix = prefix;
    this.cli_channel = cli_channel;
    this.bus_channel = bus_channel;

    // init publisher/subscriber
    pub = new Redis(redis_host, redis_port);
    cli_channel = getPrefixKey(":config:cli_channel");
    if (cli_channel.length == 0) {
      throw new Exception(ERR_WRONG_PREFIX);
    }
    bus_channel = getPrefixKey(":config:bus_channel");
    if (bus_channel.length == 0) {
      throw new Exception(ERR_WRONG_PREFIX);
    }
    sub = new Subscriber(redis_host, redis_port);
    rnd = Random(unpredictableSeed);
  }

  private string received_id;
  private int received_success;
  private string received_payload;
  private void delegate(ubyte[]) handler;
  public void onCemi(void delegate(ubyte[]) handler) {
    this.handler = handler;
    void handleMessage(string channel, string message) {
      if (channel != bus_channel) return;
      auto arr = message.split("-");
      if (arr.length != 3) {
        return;
      }

      received_id = arr[0];
      received_success = parse!int(arr[1]);
      received_payload = arr[2];
      if (received_id == "0") {
        received_id = "";
        ubyte[] received_cemi = Base64.decode(received_payload);
        handler(received_cemi);
      }
    }
    sub.subscribe(bus_channel, toDelegate(&handleMessage));
  }
  public void sendCemi(ubyte[] cemi,
      int delay = 0,
      Duration con_timeout = 30.seconds) {
    // con_timeout is big by default to prevent 
    // error throwing when llpub is busy with 
    // another processes requests
    if (handler is null) {
      throw new Exception("ERR_NO_CEMI_HANDLER");
    }
    string req;
    string req_id = name;
    // Generate an integer in [0, 1023]
    auto r = uniform(0, 65535, rnd);
    req_id ~= "_" ~ to!string(r);

    // request - <req_id-delay-cemi>
    string cemiB64 = Base64.encode(cemi);
    req ~= req_id;
    req ~= "-";
    req ~= to!string(delay);
    req ~= "-";
    req ~= cemiB64;
    pub.send("PUBLISH", cli_channel, req);
    bool confirmed = false;
    bool timeout = false;
    StopWatch sw = StopWatch(AutoStart.yes);
    while (!confirmed && !timeout) {
      if (timeout) {
        throw new Exception("ERR_REQUEST_TIMEOUT");
      }
      if (received_id == req_id) {
        if (received_success == 1) {
          received_id = "";
          ubyte[] received_cemi = Base64.decode(received_payload);
          handler(received_cemi);
          confirmed = true;
        } else {
          received_id = "";
          throw new Exception(received_payload);
        }
      } else {
        Thread.sleep(DUR_SLEEP_REQUEST);
        processMessages();
        continue;
      }
    }
  }
  public void processMessages() {
    return sub.processMessages();
  }
  public string getPrefixKey(string key) {
    return pub.send("GET " ~ prefix ~ key).toString;
  }
}

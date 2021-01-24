module llsdk.client;

import std.base64;
import std.conv;
import std.functional;
import std.string;
import std.datetime.stopwatch;

import tinyredis;
import tinyredis.subscriber;


import llsdk.errors;

public:

class LLClient {
  private Redis pub;
  private Subscriber sub;
  private string redis_host, prefix,
          cli_channel, bus_channel;
  private ushort redis_port;

  this(string redis_host = "127.0.0.1", 
      ushort redis_port = 6379,
      string prefix = "dobaosll") {

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
  }

  public void onCemi(void delegate(ubyte[]) handler) {
    void handleMessage(string channel, string message) {
      if (channel != bus_channel) return;
      auto arr = message.split("-");
      if (arr.length != 3) {
        return;
      }

      // reserved for future use
      string ts = arr[0];
      string ms = arr[1];

      string cemiB64 = arr[2];

      ubyte[] cemi;

      try {
        cemi = Base64.decode(cemiB64);
      } catch(Exception e) {
        return;
      }
      handler(cemi);
    }
    sub.subscribe(bus_channel, toDelegate(&handleMessage));
  }
  public void sendCemi(ubyte[] cemi) {
    string req;
    // request - <timestamp-milliseconds-cemi>
    auto tr = pub.send("TIME");
    foreach(v; tr) {
      req ~= v.toString ~ "-";
    }
    string cemiB64 = Base64.encode(cemi);
    req ~= cemiB64;
    pub.send("PUBLISH", cli_channel, req);
  }
  public void processMessages() {
    return sub.processMessages();
  }
  public string getPrefixKey(string key) {
    return pub.send("GET " ~ prefix ~ key).toString;
  }
}

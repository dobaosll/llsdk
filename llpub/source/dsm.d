// redis abstractions. publish/subscribe, get/set keys, add to stream

module redis_dsm;
import std.base64;
import std.conv;
import std.datetime.systime;
import std.functional;
import std.stdio;

import tinyredis;
import tinyredis.subscriber;

class RedisDsm {
  private Redis pub, redis;
  private Subscriber sub;
  // 
  private string redis_host, 
          // cli_channel - to where clients send requests
          // bus_channel - all messages from bus puslished there
          cli_channel, bus_channel, redis_stream;
  private ushort redis_port;

  this(string redis_host, ushort redis_port, string cli_channel,
      string bus_channel) {
    // init publisher
    this.redis_host = redis_host;
    this.redis_port = redis_port;
    this.cli_channel = cli_channel;
    this.bus_channel = bus_channel;
    redis = new Redis(redis_host, redis_port);
    pub = new Redis(redis_host, redis_port);
  }
  this(string redis_host, ushort redis_port) {
    this.redis_host = redis_host;
    this.redis_port = redis_port;
    redis = new Redis(redis_host, redis_port);
    pub = new Redis(redis_host, redis_port);
    sub = new Subscriber(redis_host, redis_port);
  }
  public void setChannels(string cli_channel, string bus_channel) {
    this.cli_channel = cli_channel;
    this.bus_channel = bus_channel;
  }
  public void subscribe(void delegate(string) req_handler) {
    // delegate for incoming messages
    void handleMessage(string channel, string message) {
      if (channel != cli_channel) return;
      req_handler(message);
    }
    writeln("Subscribing to ", cli_channel);
    sub.subscribe(cli_channel, toDelegate(&handleMessage));
  }
  public void bus2pub(string req_id, int success, ubyte[] cemi) {
    string req = req_id;
    req ~= "-";
    req ~= to!string(success);
    req ~= "-";
    req ~= Base64.encode(cemi);
    pub.send("PUBLISH", bus_channel, req);
  }
  public void bus2pub(string req_id, int success, string msg) {
    string req = req_id;
    req ~= "-";
    req ~= to!string(success);
    req ~= "-";
    req ~= msg;
    pub.send("PUBLISH", bus_channel, req);
  }
  public void processMessages() {
    sub.processMessages();
  }
  public string getKey(string key) {
    return redis.send("GET " ~ key).toString();
  }
  public string getKey(string key, string default_value, bool set_if_null = false) {
    auto keyValue = redis.send("GET " ~ key).toString();

    if (keyValue.length > 0) {
      return keyValue;
    } else if (set_if_null) {
      setKey(key, default_value);
      return default_value;
    } else {
      return default_value;
    }
  }
  public string setKey(string key, string value) {
    return redis.send("SET " ~ key ~ " " ~ value).toString();
  }
  public void addToStream(string key_name, string maxlen, string data) {
    auto command = "XADD ";
    command ~= key_name ~ " ";
    command ~= "MAXLEN ~ " ~ to!string(maxlen) ~ " ";
    command ~= "* "; // id
    command ~= "payload " ~ data ~ " ";
    redis.send(command);
  }
}

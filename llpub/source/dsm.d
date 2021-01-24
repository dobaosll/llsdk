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
  public void bus2pub(ubyte[] cemi) {
    string req;
    auto tr = pub.send("TIME");
    foreach(v; tr) {
      req ~= v.toString ~ "-";
    }
    string cemiB64 = Base64.encode(cemi);
    req ~= cemiB64;
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
  public long getRelativeTime(SysTime now, long ms) {
    SysTime zero = now;
    zero.hour(0);
    zero.minute(0);
    zero.second(0);
    long diffSecs = now.toUnixTime - zero.toUnixTime;
    long diffMsecs = diffSecs*1000 + ms;
    return diffMsecs;
  }
  public long getRelativeTime() {
    // return difference between current time
    // and time of same day at midnight(00:00:00)
    // in milliseconds
    auto tr = redis.send("TIME");
    long ts;
    long ms;
    foreach(k,v;tr) {
      if (k == 0) {
        ts = v.toInt!long();
      } else if (k == 1) {
        // microsecs to millisecs
        ms = v.toInt!long()/1000; 
      }
    }
    SysTime now = SysTime(unixTimeToStdTime(ts));
    return getRelativeTime(now, ms);
  }
  public long getRelativeTime(string tsStr, string microsecsStr) {
    // return difference between current time
    // and time of same day at midnight(00:00:00)
    // in milliseconds
    long ts = parse!long(tsStr);
    long ms = parse!long(microsecsStr)/1000;
    SysTime now = SysTime(unixTimeToStdTime(ts));
    return getRelativeTime(now, ms);
  }
}

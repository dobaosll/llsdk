// redis abstractions. get/set keys, add to stream
module redis_helper;
import std.conv;
import std.functional;

import tinyredis;

public:
class RedisHelper {
  private Redis redis;
  private string redis_host;
  private ushort redis_port;

  this(string redis_host = "127.0.0.1", ushort redis_port=6379) {
    this.redis_host = redis_host;
    this.redis_port = redis_port;
    redis = new Redis(redis_host, redis_port);
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
    return redis.send("SET " ~ key ~ " " ~ value).toString;
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

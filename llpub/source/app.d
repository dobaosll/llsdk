import core.thread;
import std.algorithm.comparison : equal;
import std.array;
import std.base64;
import std.bitmanip;
import std.conv;
import std.digest: toHexString;
import std.functional;
import std.getopt;
import std.stdio;
import std.string;

import baos_ll;
import redis_dsm;
import errors;

import llsdk.util;
import llsdk.cemi;

void main(string[] args) {
  writeln("hello, friend");

  // baos global
  BaosLL baos;

  string prefix = "dobaosll";
  string device = "/dev/ttyAMA0";
  bool stream_enabled = false;

  RedisDsm dsm; 
  try {
    dsm = new RedisDsm("127.0.0.1", cast(ushort)6379);
  } catch(Exception e) {
    writeln("Exception while initializing redis client:");
    writeln(e.message);
    return;
  }

	void setUartDevice(string opt, string value) {
		device = value;
		dsm.setKey(prefix ~ ":config:uart_device", device);
	}

	auto getoptResult = getopt(args,
			"prefix|c", 
			"Prefix for redis config and stream keys. Default: dobaosll",
			&prefix,

			"device|d",
			"UART device. Will be persisted in redis key. Default: /dev/ttyAMA0", 
			&setUartDevice,

			"stream|s", 
			"Store each frame in redis stream(redis >= 5.0.0). Default: no", 
			&stream_enabled);

	if (getoptResult.helpWanted) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - main daemon.\n";
    info ~= "Connect UART device and Redis Pub/Sub service. \n";
    info ~= "Required for the rest of SDK.";
		defaultGetoptPrinter(info,
				getoptResult.options);
		return;
	}

  device = dsm.getKey(prefix ~ ":config:uart_device", "/dev/ttyAMA0", true);
  string params = dsm.getKey(prefix ~ ":config:uart_params", "19200:8E1", true);

  string cli_channel = dsm.getKey(prefix ~ ":config:cli_channel", prefix ~ "_cli", true);
  string bus_channel = dsm.getKey(prefix ~ ":config:bus_channel", prefix ~ "_bus", true);
  dsm.setChannels(cli_channel, bus_channel);

  // if request was sent before [current time - timeout] then ignore it. 
  // in milliseconds
  string timeout_cfg = dsm.getKey(prefix ~ ":config:msg_timeout", "15000", true);
  long timeout = parse!long(timeout_cfg);

  string stream_name; string stream_maxlen;
  if (stream_enabled) {
    stream_name = dsm.getKey(prefix ~ ":stream_name", prefix ~ ":stream", true);
    stream_maxlen = dsm.getKey(prefix ~ ":stream_maxlen", "10000", true);
    writeln("Redis stream feature enabled");
  }

  void pub2bus(string payload) {
    ubyte[] cemi;
    auto arr = payload.split("-");
    if (arr.length != 3) {
      writeln("Wrong request");
      return;
    }
    string ts = arr[0];
    string ms = arr[1];
    string cemiB64 = arr[2];
    long requestTime = dsm.getRelativeTime(ts, ms);
    long serverTime = dsm.getRelativeTime();
    long diff = serverTime - requestTime;
    diff = diff < 0? -diff: diff;
    if (diff > timeout) {
      writeln("Request timeout");
      //throw new Exception("bye");
      return;
    }
    try {
      cemi = Base64.decode(cemiB64);
    } catch(Exception e) {
      writeln("Payload is not base64-encoded");
      return;
    }
    baos.sendFT12Frame(cemi);
    // add to redis stream
    if (stream_enabled) {
      dsm.addToStream(stream_name, stream_maxlen, cemi.toHexString);
    }
    // process cemi
    writeln("====================================================");
    writeln("cemi frame >> BAOS: ", cemi.toHexString);
    ubyte mc = cemi.peek!ubyte(0);
    if (mc == MC.LDATA_REQ || mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
      LData_cEMI decoded = new LData_cEMI(cemi);
      writeln("orig frame: 0x", cemi.toHexString);
      writeln("mc: ", decoded.message_code);
      writeln("standard: ", decoded.standard);
      writeln("donorepeat: ", decoded.donorepeat);
      writeln("sys_broadcast: ", decoded.sys_broadcast);
      writeln("priority: ", decoded.priority);
      writeln("ack_requested: ", decoded.ack_requested);
      writeln("error: ", decoded.error);
      writeln("address_type_group: ", decoded.address_type_group);
      writeln("hop_count: ", decoded.hop_count);
      writeln("source: ", decoded.source);
      writeln("dest: ", decoded.dest);
      writeln("tpci: ", decoded.tpci);
      writeln("apci: ", decoded.apci, " == ", cast(ushort)decoded.apci);
      writeln("data: 0x", decoded.data.toHexString);
      writeln("tservice: ", decoded.tservice);
      writeln("tsequence: ", decoded.tseq);
      writeln("toUbytes: 0x", decoded.toUbytes.toHexString);
      writeln("original and calculated equal? ", equal(cemi, decoded.toUbytes));
      writeln("====================================================");
    }
  }
  dsm.subscribe(toDelegate(&pub2bus));

  baos = new BaosLL(device, params);
  void onCemiFrame(ubyte[] cemi) {
    dsm.bus2pub(cemi);

    writeln("====================================================");
    writeln("BAOS >> cemi frame: 0x", cemi.toHexString);

    // add to redis stream
    if (stream_enabled) {
      dsm.addToStream(stream_name, stream_maxlen, cemi.toHexString);
    }

    auto mc = cemi.peek!ubyte(0);
    if (mc == MC.LDATA_REQ || mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
      LData_cEMI decoded = new LData_cEMI(cemi);
      writeln("orig frame: 0x", cemi.toHexString);
      writeln("mc: ", decoded.message_code);
      writeln("standard: ", decoded.standard);
      writeln("donorepeat: ", decoded.donorepeat);
      writeln("sys_broadcast: ", decoded.sys_broadcast);
      writeln("priority: ", decoded.priority);
      writeln("ack_requested: ", decoded.ack_requested);
      writeln("error: ", decoded.error);
      writeln("address_type_group: ", decoded.address_type_group);
      writeln("hop_count: ", decoded.hop_count);
      writeln("source: ", decoded.source, " ", ia2str(decoded.source));
      if (decoded.address_type_group) {
        writeln("dest: ", decoded.dest, " ", grp2str(decoded.dest));
      } else {
        writeln("dest: ", decoded.dest, " ", ia2str(decoded.dest));
      }
      writeln("tpci: ", decoded.tpci);
      writeln("apci: ", decoded.apci, " == ", cast(ushort)decoded.apci);
      writeln("data: 0x", decoded.data.toHexString);
      writeln("tservice: ", decoded.tservice);
      writeln("tsequence: ", decoded.tseq);
      writeln("toUbytes: 0x", decoded.toUbytes.toHexString);
      writeln("original and calculated equal? ", equal(cemi, decoded.toUbytes));
      writeln("====================================================");
    }
  }
  baos.onCemiFrame = toDelegate(&onCemiFrame);

  writeln("BAOS instance created");
  Thread.sleep(10.msecs);
  baos.reset();
  baos.switch2LL();
  writeln("Switching to LinkLayer");
  writeln("Working....");

  while(true) {
    dsm.processMessages();
    baos.processIncomingData();
    Thread.sleep(1.msecs);
  }
}

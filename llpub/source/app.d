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
import std.datetime.stopwatch;

import baos_ll;
import redis_dsm;
import errors;

import llsdk.util;
import llsdk.cemi;
import llsdk.durations;

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

  string last_req_id;
  ubyte[] last_cemi;
  ubyte[] last_received;
  bool confirmed = false;
  void pub2bus(string payload) {
    ubyte[] cemi;
    auto arr = payload.split("-");
    if (arr.length != 3) {
      writeln("Wrong request");
      return;
    }
    string req_id = arr[0];
    int delay = parse!int(arr[1]);
    string cemiB64 = arr[2];
    try {
      cemi = Base64.decode(cemiB64);
    } catch(Exception e) {
      writeln("Payload is not base64-encoded");
      return;
    }

    Thread.sleep(delay.msecs);
    baos.sendFT12Frame(cemi);
    last_req_id = req_id;
    last_cemi = cemi.dup;

    // add to redis stream
    if (stream_enabled) {
      dsm.addToStream(stream_name, stream_maxlen, cemi.toHexString);
    }
    // process cemi
    writeln(req_id ~ ": ", cemi.toHexString);
    MC mc = cast(MC) cemi.peek!ubyte(0);
    
    /*if (mc == MC.LDATA_REQ || mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
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
    } */
    confirmed = false;
    bool timeout = false;
    StopWatch sw = StopWatch(AutoStart.yes);
    while(!timeout && !confirmed) {
      Thread.sleep(DUR_SLEEP_REQUEST);
      baos.processIncomingData();
      timeout = sw.peek > 500.msecs;
      if (timeout) {
        sw.stop();
        dsm.bus2pub(req_id, 0, "ERR_TIMEOUT");
        last_received = [];
      }
      if (last_received.length > 0) {
        mc = cast(MC) last_received.peek!ubyte(0);
        if (mc == MC.LDATA_CON ||
            mc == MC.MPROPREAD_CON ||
            mc == MC.MPROPWRITE_CON) {
          confirmed = true;
          dsm.bus2pub(req_id, 1, last_received);
          last_received = [];
        } else {
          dsm.bus2pub("0", 1, last_received);
          last_received = [];
        }
      }
    }
  }
  dsm.subscribe(toDelegate(&pub2bus));

  baos = new BaosLL(device, params);
  void onCemiFrame(ubyte[] cemi) {
    last_received = cemi.dup;
    writeln("                                                ", cemi.toHexString);

    // add to redis stream
    if (stream_enabled) {
      dsm.addToStream(stream_name, stream_maxlen, cemi.toHexString);
    }

    auto mc = cemi.peek!ubyte(0);
    /*if (mc == MC.LDATA_REQ || mc == MC.LDATA_CON || mc == MC.LDATA_IND) {
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
    }*/
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
    if (last_received.length > 0) {
      dsm.bus2pub("0", 1, last_received);
      last_received = [];
    }
    Thread.sleep(DUR_SLEEP_MAIN_LOOP);
  }
}

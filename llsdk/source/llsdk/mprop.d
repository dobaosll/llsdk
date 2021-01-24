module llsdk.mprop;

import core.thread;
import std.algorithm: equal;
import std.bitmanip;
import std.conv;
import std.datetime.stopwatch;
import std.functional;

import std.digest: toHexString;

import llsdk.cemi;
import llsdk.client;
import llsdk.errors;

/***

  +----+-----------+------+----------------+-----+---------+--------+------+
  | MC | IObjTypeH | IOTL | ObjectInstance | PID | NoE > 0 | SIx    | data |
  |    |           |      |                |     | 4bits   | 12bits | data |
  +----+-----------+------+----------------+-----+---------+--------+------+
  con with error:
  +----+-----------+------+----------------+-----+---------+-----+------+
  | MC | IObjTypeH | IOTL | ObjectInstance | PID | NoE = 0 | SIx | code |
  +----+-----------+------+----------------+-----+---------+-----+------+

 ***/

public:

struct MPropFrame {
  MC mc;
  ushort obj_type;
  ubyte obj_inst;
  ubyte prop_id;
  ubyte number;
  ushort start_index;
  ubyte[] data;
  this(MC mc) {
    this.mc = mc;
    // default values
    this.obj_type = 0;
    this.obj_inst = 1;
    this.number = 1;
    this.start_index = 1;
  }
  this(ubyte[] msg) {
    int offset = 0;
    mc = cast(MC) msg.peek!ubyte(offset); offset += 1;
    if (mc != MC.MPROPREAD_REQ &&
        mc != MC.MPROPREAD_CON &&
        mc != MC.MPROPWRITE_REQ &&
        mc != MC.MPROPWRITE_CON &&
        mc != MC.MPROPINFO)IND) return;
    obj_type = msg.peek!ushort(offset); offset += 2;
    obj_inst = msg.peek!ubyte(offset); offset += 1;
    prop_id = msg.peek!ubyte(offset); offset += 1;
    ushort noe_six = msg.peek!ushort(offset); 
    number = noe_six >> 12;
    start_index = noe_six & 0b0000_1111_1111_1111;
    offset += 2;
    data = msg[offset..$].dup;
  }
  ubyte[] toUbytes() {
    ubyte[] res; res.length = 7;
    int offset = 0;
    res.write!ubyte(mc, offset); offset += 1;
    res.write!ushort(obj_type, offset); offset += 2;
    res.write!ubyte(obj_inst, offset); offset += 1;
    res.write!ubyte(prop_id, offset); offset += 1;
    ushort noe_six =to!ushort(
        (number << 12) | (start_index & 0b0000_1111_1111_1111));
    res.write!ushort(noe_six, offset); offset += 2;
    res ~= data;
    return res;
  }
}

class MProp {
  private LLClient ll;
  // global variables
  private MPropFrame last;
  private MPropFrame response;
  private bool resolved = false;
  private Duration req_timeout;

  this(string redis_host = "127.0.0.1", 
       ushort redis_port = 6379,
       string prefix = "dobaosll", 
       Duration req_timeout = 3000.msecs) {

    this.req_timeout = req_timeout;
    ll = new LLClient(redis_host, redis_port, prefix);
    ll.onCemi(toDelegate(&onCemiFrame));
  }
  private void onCemiFrame(ubyte[] cemi) {
    int offset = 0;
    MPropFrame _response = MPropFrame(cemi);
    if (_response.mc != MC.MPROPREAD_CON && 
        _response.mc != MC.MPROPWRITE_CON) {
      return;
    }

    if (last.obj_type == _response.obj_type &&
        last.obj_inst == _response.obj_inst &&
        last.prop_id == _response.prop_id) {
      resolved = true;
      response = _response;
    }
  }
  public ubyte[] read(ubyte id, ubyte num = 1,
      ushort si = 0x0001, ushort iot = 0, ubyte instance = 0x01) {

    resolved = false;

    MPropFrame mf = MPropFrame(MC.MPROPREAD_REQ);
    mf.obj_type = iot;
    mf.obj_inst = instance;
    mf.prop_id = id;
    mf.start_index = si;
    mf.number = num;
    last = mf;
    ll.sendCemi(mf.toUbytes);
    bool timeout = false;
    StopWatch sw = StopWatch(AutoStart.yes);
    while (!resolved && !timeout) {
      timeout = sw.peek() > req_timeout;
      ll.processMessages();
      Thread.sleep(1.msecs);
    }
    if (timeout) {
      throw new Exception(ERR_MPROPREAD_TIMEOUT);
    }
    sw.stop();
    ubyte[] result;
    if (response.number > 0) {
      result = response.data.dup;
    } else {
      throw new Exception(ERR_LL ~ response.data.toHexString);
    }

    return result;
  }
  public ubyte[] write(ubyte id, ubyte[] value, ubyte num = 1,
      ushort si = 0x0001, ushort iot = 0, ubyte instance = 0x01) {

    resolved = false;

    MPropFrame mf = MPropFrame(MC.MPROPWRITE_REQ);
    mf.obj_type = iot;
    mf.obj_inst = instance;
    mf.prop_id = id;
    mf.start_index = si;
    mf.number = num;
    mf.data = value.dup;
    last = mf;
    ll.sendCemi(mf.toUbytes);
    bool timeout = false;
    StopWatch sw = StopWatch(AutoStart.yes);
    while (!resolved && !timeout) {
      timeout = sw.peek() > req_timeout;
      ll.processMessages();
      Thread.sleep(1.msecs);
    }
    if (timeout) {
      throw new Exception(ERR_MPROPWRITE_TIMEOUT);
    }
    sw.stop();
    ubyte[] result;
    if (response.number > 0) {
      result = response.data.dup;
    } else {
      throw new Exception(ERR_LL ~ response.data.toHexString);
    }

    return result;
  }
}

module knx_cl;

import core.thread;
import std.bitmanip;
import std.datetime.stopwatch;
import std.functional;

import std.stdio;

import llsdk;

public:
enum FrameType: ubyte {
  unknown = 0x00,
  connect = 0x01,
  data = 0x02,
  ack = 0x03,
  nack = 0x04,
  disconnect = 0x05
}

struct NetworkFrame {
  FrameType type = FrameType.unknown;
  ubyte seq = 0x00;
  ubyte[] data = [];
  ushort source, dest;
  this(ubyte[] msg) {
    if (msg.length == 0) return;
    type = cast(FrameType) msg.read!ubyte();
    switch(type) {
      case FrameType.ack:
      case FrameType.nack:
        if (msg.length != 1) {
          type = FrameType.unknown;
          return;
        }
        seq = msg.read!ubyte();
        break;
      case FrameType.data:
        if (msg.length == 0) {
          type = FrameType.unknown;
          return;
        }
        seq = msg.read!ubyte();
        data = msg.dup;
        break;
      case FrameType.connect:
      case FrameType.disconnect:
      default:
        break;
    }
  }
  ubyte[] toUbytes() {
    ubyte[] res = [];
    res.length = 1;
    res.write!ubyte(type, 0);
    switch(type) {
      case FrameType.ack:
      case FrameType.nack:
        res.length = 2;
        res.write!ubyte(seq, 1);
        return res;
      case FrameType.data:
        res.length = 2;
        res.write!ubyte(seq, 1);
        res ~= data;
        return res;
      case FrameType.connect:
      case FrameType.disconnect:
      default:
        break;
    }

    return res;
  }
}

class NetworkSocket {
  private LLClient ll;
  private LData_cEMI in_frame;
  private ushort self;
  private ushort client;

  public bool available = true;
  private LData_cEMI last_req;
  private  StopWatch sw = StopWatch(AutoStart.no);

  private void onCemiFrame(ubyte[] frame) {
    ubyte mc = frame.peek!ubyte(0);
    if (mc == MC.LDATA_REQ || 
        mc == MC.LDATA_IND) {
      in_frame = new LData_cEMI(frame);
    }
    if ( mc == MC.LDATA_CON ) {
      auto conFrame = new LData_cEMI(frame);
      if (conFrame.message_code == MC.LDATA_CON &&
          conFrame.tservice == last_req.tservice &&
          conFrame.dest == last_req.dest) {
        available = true;
        sw.stop();
        sw.reset();
      }
    }
  }
  this(string host = "127.0.0.1", 
      ushort port = 6379,
      string prefix = "dobaosll") {
    ll = new LLClient(host, port, prefix);
    ll.onCemi(toDelegate(&onCemiFrame));
  }
  NetworkFrame receive() {
    NetworkFrame res = NetworkFrame([0]);

    ll.processMessages();
    if (in_frame is null) return res;
    if (in_frame.tservice == TService.TDataIndividual &&
        in_frame.apci == APCI.AUserMessageReq) {
      res = NetworkFrame(in_frame.data);
      res.source = in_frame.source;
      res.dest = in_frame.dest;
      in_frame = null;
      return res;
    }
    in_frame = null;

    processConTimer();

    return res;
  }
  void processConTimer() {
    auto dur = sw.peek();
    if (dur > 100.msecs) {
      sw.stop();
      sw.reset();
      available = true;
    }
  }
  void send(NetworkFrame frame, Duration delay = 0.msecs) {
    Thread.sleep(delay);
    ubyte[] data = frame.toUbytes;
    LData_cEMI cl = new LData_cEMI();
    cl.message_code = MC.LDATA_REQ;
    cl.address_type_group = false;
    cl.source = 0x0000;
    cl.dest = frame.dest;
    cl.tservice = TService.TDataIndividual;
    cl.apci_data_len = (1 + data.length) & 0xff;
    cl.apci = APCI.AUserMessageReq;
    cl.data = data;
    last_req = cl;
    available = false;
    sw.reset();
    sw.start();
    ll.sendCemi(cl.toUbytes);
  }
}

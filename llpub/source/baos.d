module baos_ll;

import std.stdio;
import core.thread;

import std.datetime.stopwatch;

import serialport;

import ft12;

class BaosLL {
  private SerialPortNonBlk com;

  // helper serves to parse/compose ft12 frames
  private FT12Helper ft12;
  private FT12FrameParity currentParity = FT12FrameParity.unknown;

  private bool resetInd = false;
  private bool resetAckReceived = false;
  private bool ackReceived = false;

  // store cemi frames received.
  // send to KNXNetIP client and clear
  private ubyte[][] cemiReceived;

  private int req_timeout;
  private bool timeout = false;
  private StopWatch sw;

  public ulong processIncomingData() {
    void[1024*4] data = void;
    void[] tmp;
    tmp = com.read(data);
    if(tmp.length > 0) {
      ubyte[] chunk = cast(ubyte[]) tmp;

      ft12.parse(chunk);
    }

    return tmp.length;
  }
  public void processResponseTimeout() {
    auto dur = sw.peek();
    timeout = dur > msecs(req_timeout);
  }
  void sendFT12Frame(ubyte[] message) {
    ackReceived = false;
    if (currentParity == FT12FrameParity.unknown ||
        currentParity == FT12FrameParity.even) {
      currentParity = FT12FrameParity.odd;
    } else {
      currentParity = FT12FrameParity.even;
    }

    FT12Frame request;
    request.type = FT12FrameType.dataFrame;
    request.parity = currentParity;
    request.payload = message[0..$];
    ubyte[] buffer = ft12.compose(request);
    //writeln("baos.d: writing to comport: ", buffer);
    com.write(buffer);
    sw.reset();
    sw.start();
    // пока не получен ответ, либо индикатор сброса, либо таймаут
    while(!(ackReceived || resetInd || timeout)) {
      try {
        processIncomingData();
        processResponseTimeout();
        if (resetInd) {
          resetInd = false;
          break;
        }
        if (timeout) {
          writeln("err timeout");
          timeout = false;
          // send again
          return sendFT12Frame(message);
        }
      } catch(Exception e) {
        writeln(e);
      }
      Thread.sleep(500.usecs);
    }
  }

  private void onFT12Frame(FT12Frame frame) {
    //writeln("Received FT12 frame:", frame);
    bool isAck = frame.isAckFrame();
    bool isResetInd = frame.isResetInd();
    bool isDataFrame = frame.isDataFrame();

    if (isAck) {
      ackReceived = true;
    } else if (isResetInd) {
      // send acknowledge
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);
      writeln("Reset indication received");
      currentParity = FT12FrameParity.unknown;
      switch2LL();
    } else  if (isDataFrame) {
      // send acknowledge
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);
      onCemiFrame(frame.payload);
    }
  }
  public void reset() {
    // send reset request
    FT12Frame resetFrame;
    resetFrame.type = FT12FrameType.resetReq;
    ubyte[] resetReqBuffer = ft12.compose(resetFrame);

    writeln("Sending reset request");
    com.write(resetReqBuffer);

    // init var
    resetInd = false;
    ackReceived = false;
    timeout = false;
    sw.reset();
    sw.start();
    // and wait until it is received
    while(!(ackReceived || resetInd || timeout)) {
      processIncomingData();
      processResponseTimeout();
      if (timeout) {
        writeln("Reset request timeout. Sending again.");
        timeout = false;
        sw.reset();
        sw.start();
        // repeat
        reset();
      }
      if (ackReceived) {
        writeln("Ack for reset request received");
      }
      if (resetInd) {
        resetInd = false;
        break;
      }
      Thread.sleep(500.usecs);
    }
    writeln("Reset has been sent?");
  }
  public void switch2LL() {
    if (currentParity == FT12FrameParity.unknown || currentParity == FT12FrameParity.even) {
      currentParity = FT12FrameParity.odd;
    } else {
      currentParity = FT12FrameParity.even;
    }
    writeln("Sending 0xF600080134100100 to switch to LL mode");
    ubyte[] switch2ll = [0xf6, 0x00, 0x08, 0x01, 0x34, 0x10, 0x01, 0x00];
    FT12Frame request;
    request.type = FT12FrameType.dataFrame;
    request.parity = currentParity;
    request.payload = switch2ll[0..$];
    ubyte[] buffer = ft12.compose(request);
    com.write(buffer);
  }

  public void delegate(ubyte[] ) onCemiFrame;

  this(string device = "/dev/ttyS1", string params = "19200:8E1", int req_timeout = 1000) {
    com = new SerialPortNonBlk(device, params);
    // register listener for ft12 incoming frames
    ft12 = new FT12Helper(&onFT12Frame);
    this.req_timeout = req_timeout;
    this.sw = StopWatch(AutoStart.no);
  }
}

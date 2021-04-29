module llsdk.tbroadcast;

import core.thread;
import core.time;
import std.bitmanip;
import std.conv;
import std.datetime.stopwatch;
import std.functional;

import llsdk.cemi;
import llsdk.client;
import llsdk.errors;
import llsdk.durations;
import llsdk.util;

class TBroadcast {
  private LLClient ll;
  private LData_cEMI in_frame, out_frame;

  private LData_cEMI waitForCon(LData_cEMI req, Duration timeout = 300.msecs) {
    LData_cEMI res;
    // wait for confirmation
    StopWatch sw;
    Duration dur;
    sw.reset();
    sw.start();
    bool con_received = false;
    bool con_timeout = false;
    while(!con_received && !con_timeout) {
      dur = sw.peek();
      con_timeout = dur > timeout;
      ll.processMessages();
      if (in_frame is null) continue;
      if (in_frame.message_code == MC.LDATA_CON &&
          in_frame.tservice == req.tservice &&
          in_frame.dest == req.dest) {
        con_received = true;
        res = in_frame;
      }
      in_frame = null;
    }
    if (con_timeout) {
      throw new Exception(ERR_LDATACON_TIMEOUT);
    }

    return res;
  }
  private LData_cEMI[] collectResponse(LData_cEMI req, APCI apci, Duration timeout = 1000.msecs) {
    LData_cEMI[] res;
    // wait for confirmation
    bool res_received = false;
    StopWatch sw;
    Duration dur;
    sw.reset();
    sw.start();
    bool res_timeout = false;
    while(!res_timeout) {
      Thread.sleep(DUR_SLEEP_REQUEST);
      dur = sw.peek();
      res_timeout = dur > timeout;
      ll.processMessages();
      if (in_frame is null) continue;
      if (in_frame.message_code == MC.LDATA_IND &&
          in_frame.tservice == req.tservice &&
          in_frame.apci == apci) {
        res ~= in_frame;
      }
      in_frame = null;
    }

    return res;
  }
  private void onCemiFrame(ubyte[] frame) {
    ubyte mc = frame.peek!ubyte(0);
    if (mc == MC.LDATA_REQ || 
        mc == MC.LDATA_CON ||
        mc == MC.LDATA_IND) {
      in_frame = new LData_cEMI(frame);
    }
  }
  this(string redis_host = "127.0.0.1", 
      ushort redis_port = 6379,
      string prefix = "dobaosll",
      string name = "tbroadcast") {
    ll = new LLClient(redis_host, redis_port, prefix, name);
    ll.onCemi(toDelegate(&onCemiFrame));
  }
  private void request(LData_cEMI req) {
    ll.sendCemi(req.toUbytes, 10);
    bool confirmed = false;
    while(!confirmed) {
      try {
        waitForCon(req);
        confirmed = true;
      } catch(Exception e) {
        ll.sendCemi(req.toUbytes, 10);
      }
    }
  }
  public LData_cEMI[] iaRead() {
    LData_cEMI dmsg = new LData_cEMI();
    dmsg.message_code = MC.LDATA_REQ;
    dmsg.address_type_group = true;
    dmsg.source = 0x0000;
    dmsg.dest = 0x0000;
    dmsg.tservice = TService.TDataBroadcast;
    dmsg.apci = APCI.AIndividualAddressRead;
    dmsg.apci_data_len = 1;

    request(dmsg);
    return collectResponse(dmsg, APCI.AIndividualAddressResponse);
  }
}

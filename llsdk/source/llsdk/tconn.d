module llsdk.tconn;

import core.thread;
import core.time;
import std.bitmanip;
import std.conv;
import std.datetime.stopwatch;
import std.functional;

import llsdk.cemi;
import llsdk.client;
import llsdk.errors;

public:

class TConn {
  private LLClient ll;
  private LData_cEMI in_frame, out_frame;
  private ubyte in_seq, out_seq;
  private bool check_in_seq = false;

  public ushort address;
  public bool connected;

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
      Thread.sleep(500.usecs);
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
  private LData_cEMI waitForAck(LData_cEMI req, Duration timeout = 3000.msecs) {
    LData_cEMI res;
    // wait for confirmation
    bool ack_received = false;
    StopWatch sw;
    Duration dur;
    sw.reset();
    sw.start();
    bool ack_timeout = false;
    while(!ack_received && !ack_timeout) {
      Thread.sleep(500.usecs);
      dur = sw.peek();
      ack_timeout = dur > timeout;
      ll.processMessages();
      if (in_frame is null) continue;
      if (in_frame.message_code == MC.LDATA_IND &&
          in_frame.tservice == TService.TAck &&
          in_frame.source == req.dest &&
          in_frame.tseq == req.tseq) {
        ack_received = true;
        res = in_frame;
      }
      in_frame = null;
    }
    if (ack_timeout) {
      throw new Exception(ERR_ACK_TIMEOUT);
    }

    return res;
  }
  private LData_cEMI waitForResponse(LData_cEMI req, APCI apci, Duration timeout = 6000.msecs) {
    LData_cEMI res;
    // wait for confirmation
    bool res_received = false;
    StopWatch sw;
    Duration dur;
    sw.reset();
    sw.start();
    bool res_timeout = false;
    while(!res_received && !res_timeout) {
      Thread.sleep(500.usecs);
      dur = sw.peek();
      res_timeout = dur > timeout;
      ll.processMessages();
      if (in_frame is null) continue;
      if (in_frame.message_code == MC.LDATA_IND &&
          in_frame.tservice == TService.TDataConnected &&
          in_frame.apci == apci &&
          in_frame.source == req.dest) {
        res_received = true;
        res = in_frame;
      }
      in_frame = null;
    }
    if (res_timeout) {
      throw new Exception(ERR_CONNECTION_TIMEOUT);
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
  private void increaseInSeq() {
    if (in_seq < 15) {
      in_seq += 1;
    } else {
      in_seq = 0;
    }
  }
  private void increaseOutSeq() {
    if (out_seq < 15) {
      out_seq += 1;
    } else {
      out_seq = 0;
    }
  }
  private void sendAck() {
    // send ack
    LData_cEMI tack = new LData_cEMI();
    tack.message_code = MC.LDATA_REQ;
    tack.address_type_group = false;
    tack.source = 0x0000;
    tack.dest = address;
    tack.tservice = TService.TAck;
    tack.tseq = in_seq;
    increaseInSeq();
    ll.sendCemi(tack.toUbytes);
  }
  this(ushort ia, 
      string redis_host = "127.0.0.1", 
      ushort redis_port = 6379,
      string prefix = "dobaosll") {
    address = ia;
    ll = new LLClient(redis_host, redis_port, prefix);
    ll.onCemi(toDelegate(&onCemiFrame));
  }

  public void connect() {
    LData_cEMI tconn = new LData_cEMI();
    tconn.message_code = MC.LDATA_REQ;
    tconn.address_type_group = false;
    tconn.source = 0x0000;
    tconn.dest = address;
    tconn.tservice = TService.TConnect;
    ll.sendCemi(tconn.toUbytes);
    bool confirmed = false;
    LData_cEMI con;
    while (!confirmed) {
      try {
        con = waitForCon(tconn);
        confirmed = true;
      } catch(Exception e) {
        ll.sendCemi(tconn.toUbytes);
      }
    }
    if (con.error) {
      connected = false;
      return;
    }
    connected = true;
    in_seq = 0x00;
    out_seq = 0x00;
  }
  public void disconnect() {
    LData_cEMI tdcon = new LData_cEMI();
    tdcon.message_code = MC.LDATA_REQ;
    tdcon.address_type_group = false;
    tdcon.source = 0x0000;
    tdcon.dest = address;
    tdcon.tservice = TService.TDisconnect;
    ll.sendCemi(tdcon.toUbytes);
    connected = false;
  }
  private void request(LData_cEMI req) {
    if (!connected) {
      throw new Exception(ERR_DISCONNECTED);
    }
    ll.sendCemi(req.toUbytes);
    bool confirmed = false;
    while(!confirmed) {
      try {
        waitForCon(req);
        confirmed = true;
      } catch(Exception e) {
        ll.sendCemi(req.toUbytes);
      }
    }
    // while ack not received or sent count < 4
    auto ack_timeout_dur = 3000.msecs;
    auto sent_cnt = 1;
    bool acknowledged = false;
    while (!acknowledged && sent_cnt < 4) {
      try {
        waitForAck(req, ack_timeout_dur);
        acknowledged = true;
        increaseOutSeq();
      } catch(Exception e) {
        ll.sendCemi(req.toUbytes);
        //ack_timeout_dur = 1000.msecs;
        sent_cnt += 1;
      }
    }
    if (!acknowledged) {
      disconnect();
      throw new Exception(ERR_ACK_TIMEOUT);
    }
  }
  private LData_cEMI requestResponse(LData_cEMI req, APCI apci_res) {
    LData_cEMI result;
    request(req);
    try {
      result = waitForResponse(req, apci_res);
      if (check_in_seq && result.tseq == in_seq) {
        sendAck();
      } else if (!check_in_seq) {
        sendAck();
      } else if (check_in_seq && result.tseq != in_seq){
        disconnect();
        throw new Exception(ERR_WRONG_SEQ_NUM);
      }
    } catch(Exception e) {
      disconnect();
      throw e;
    }

    return result;
  }
  public ubyte[] deviceDescriptorRead(ubyte descr_type = 0x00) {
    ubyte[] result;
    LData_cEMI dread = new LData_cEMI();
    dread.message_code = MC.LDATA_REQ;
    dread.address_type_group = false;
    dread.source = 0x0000;
    dread.dest = address;
    dread.tservice = TService.TDataConnected;
    dread.tseq = out_seq;
    dread.apci = APCI.ADeviceDescriptorRead;
    dread.apci_data_len = 1;
    dread.tiny_data = descr_type;

    result = requestResponse(dread, APCI.ADeviceDescriptorResponse).data;

    return result;
  }
  public ubyte[] propertyRead(ubyte prop_id,
      ubyte obj_id = 0x00, ubyte num=0x01, ushort start=0x01) {
    ubyte[] result;
    LData_cEMI dprop = new LData_cEMI();
    dprop.message_code = MC.LDATA_REQ;
    dprop.address_type_group = false;
    dprop.source = 0x0000;
    dprop.dest = address;
    dprop.tservice = TService.TDataConnected;
    dprop.tseq = out_seq;
    dprop.apci = APCI.APropertyValueRead;
    dprop.apci_data_len = 5;
    dprop.data.length = 4;
    dprop.data.write!ubyte(obj_id, 0);
    dprop.data.write!ubyte(prop_id, 1);
    ushort numstart = start & 0b000011111111;
    numstart = to!ushort((num << 12) | numstart);
    dprop.data.write!ushort(numstart, 2);
    ll.sendCemi(dprop.toUbytes);
    result = requestResponse(dprop, APCI.APropertyValueResponse).data;

    if(result.length >= 4) {
      ubyte res_obj_id = result.read!ubyte();
      ubyte res_prop_id = result.read!ubyte();
      ushort res_numstart = result.read!ushort();
      if (res_obj_id != obj_id &&
          res_prop_id != prop_id) {
        throw new Exception(ERR_WRONG_RESPONSE);
      }
      ubyte res_num = res_numstart >> 12;
      ushort res_start = res_numstart & 0b0000_1111_1111_1111;
      if (res_num == 0) {
        // TODO approptiate error code
        throw new Exception(ERR_WRONG_RESPONSE);
      }
    } else {
      throw new Exception(ERR_WRONG_RESPONSE);
    }

    return result;
  }
  public ubyte[] propertyWrite(ubyte prop_id, ubyte[] data, 
      ubyte obj_id = 0x00, ubyte num = 0x01, ushort start = 0x1) {
    ubyte[] result;
    LData_cEMI dprop = new LData_cEMI();
    dprop.message_code = MC.LDATA_REQ;
    dprop.address_type_group = false;
    dprop.source = 0x0000;
    dprop.dest = address;
    dprop.tservice = TService.TDataConnected;
    dprop.tseq = out_seq;
    dprop.apci = APCI.APropertyValueWrite;
    dprop.apci_data_len = to!ubyte(5 + data.length);
    dprop.data.length = 4;
    dprop.data.write!ubyte(obj_id, 0);
    dprop.data.write!ubyte(prop_id, 1);
    dprop.data ~= data;
    ushort numstart = start & 0b000011111111;
    numstart = to!ushort((num << 12) | numstart);
    dprop.data.write!ushort(numstart, 2);
    ll.sendCemi(dprop.toUbytes);
    result = requestResponse(dprop, APCI.APropertyValueResponse).data;

    if(result.length >= 4) {
      ubyte res_obj_id = result.read!ubyte();
      ubyte res_prop_id = result.read!ubyte();
      ushort res_numstart = result.read!ushort();
      if (res_obj_id != obj_id &&
          res_prop_id != prop_id) {
        throw new Exception(ERR_WRONG_RESPONSE);
      }
      ubyte res_num = res_numstart >> 12;
      ushort res_start = res_numstart & 0b0000_1111_1111_1111;
      if (res_num == 0) {
        // TODO approptiate error code
        throw new Exception(ERR_WRONG_RESPONSE);
      }
    } else {
      throw new Exception(ERR_WRONG_RESPONSE);
    }

    return result;
  }
  public ubyte[] memoryRead(ushort addr, ubyte number) {
    ubyte[] result;
    LData_cEMI dmem = new LData_cEMI();
    dmem.message_code = MC.LDATA_REQ;
    dmem.address_type_group = false;
    dmem.source = 0x0000;
    dmem.dest = address;
    dmem.tservice = TService.TDataConnected;
    dmem.tseq = out_seq;
    dmem.apci = APCI.AMemoryRead;
    dmem.apci_data_len = 3;
    dmem.tiny_data = number & 0b00111111;
    dmem.data.length = 2;
    dmem.data.write!ushort(addr, 0);
    ll.sendCemi(dmem.toUbytes);

    LData_cEMI rmem = requestResponse(dmem, APCI.AMemoryResponse);
    
    if (rmem.tiny_data == number) {
      result = rmem.data;
    } else {
      throw new Exception(ERR_WRONG_RESPONSE);
    }

    return result;
  }
  public void memoryWrite(ushort addr, ubyte[] data) {
    LData_cEMI dmem = new LData_cEMI();
    dmem.message_code = MC.LDATA_REQ;
    dmem.address_type_group = false;
    dmem.source = 0x0000;
    dmem.dest = address;
    dmem.tservice = TService.TDataConnected;
    dmem.tseq = out_seq;
    dmem.apci = APCI.AMemoryWrite;
    ubyte number = data.length & 0b00111111;
    dmem.apci_data_len = to!ubyte(3 + number);
    dmem.tiny_data = number;
    dmem.data.length = 2;
    dmem.data.write!ushort(addr, 0);
    dmem.data ~= data;
    ll.sendCemi(dmem.toUbytes);

    return request(dmem);
  }
  public void userMessage(ubyte[] data) {
    LData_cEMI dmsg = new LData_cEMI();
    dmsg.message_code = MC.LDATA_REQ;
    dmsg.address_type_group = false;
    dmsg.source = 0x0000;
    dmsg.dest = address;
    dmsg.tservice = TService.TDataConnected;
    dmsg.tseq = out_seq;
    dmsg.apci = APCI.AUserMessageReq;
    dmsg.apci_data_len = to!ubyte(1 + data.length);
    dmsg.data = data.dup;
    ll.sendCemi(dmsg.toUbytes);

    return request(dmsg);
  }
}

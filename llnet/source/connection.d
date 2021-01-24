module connection;

import std.conv;
import std.datetime.stopwatch;
import std.socket;
import std.stdio;
import std.string;

import knxnet;

struct KnxNetRequest {
  // TUNNELING_REQ or DEV_MGMT_REQ
  ushort service;
  // cemi frame
  ubyte[] cemi;
}

struct KnxNetConnection {
  bool active = false;
  Address addr;
  ushort ia = 0x0000;
  ubyte channel = 0x01;
  ubyte sequence = 0x00;
  ubyte outSequence = 0x00;
  ubyte type = KNXConnTypes.TUNNEL_CONNECTION;

  // acknowledge for TUN_REQ received? from net client
  bool ackReceived = true;
  int sentReqCount = 0;
  // store last request to net client
  ubyte[] lastReq;
  // timeout watcher
  StopWatch swCon; // 120s inactivity
  StopWatch swAck; // 1s for request ack

  StopWatch[ushort] tconns;

  // last data sent to baos.
  // purpose is to compare when Con frame received
  ubyte[] lastCemiToBaos;

  void increaseSeqId() {
    if (sequence < 255) {
      sequence += 1;
    } else {
      sequence = 0;
    }
  }
  void increaseOutSeqId() {
    if (sequence < 255) {
      outSequence += 1;
    } else {
      outSequence = 0;
    }
  }

  KnxNetRequest[] queue;
  ubyte[] processQueue() {
    ubyte[] res;
    if (ackReceived) {
      if (queue.length > 0) {
        KnxNetRequest item = queue[0];
        if (queue.length > 1) {
          queue = queue[1..$];
        } else {
          queue = [];
          queue.length = 0;
        }
        ubyte[] frame = request(item.cemi, channel, outSequence);
        ubyte[] req = KNXIPMessage(item.service, frame);

        return req;
      }
    }

    return res;
  }
  void add2queue(ushort service, ubyte[] cemi) {
    queue ~= KnxNetRequest(service, cemi);
  }
}

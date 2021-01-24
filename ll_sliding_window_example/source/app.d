import core.thread;

import std.bitmanip;
import std.conv;
import std.digest;
import std.datetime.stopwatch;
import std.file;
import std.getopt;
import std.stdio;
import std.string;
import std.random;

import knx_cl;

import llsdk;

enum SEND_DELAY = 10.msecs;

ubyte inc(ubyte k, ubyte max_seq) {
  if (k < max_seq)
    return (k + 1) & 0xff;
  else 
    return 0;
}

bool between(ubyte a, ubyte b, ubyte c) {
  // a <= b < c
  // b < c < a 
  // c < a <=b
  bool res =  ((a <= b) && (b < c)) ||
    ((b < c) && (c < a)) ||
    ((c < a) && (a <= b));

  return res;
}

void main(string[] args) {
  string prefix = "dobaosll";
  string host = "127.0.0.1";
  ushort port = 6379;
  ubyte max_seq = 7;
  ubyte nr_bufs = ((max_seq + 1)/2);
  int msg_len = 45;
  int ack_timeout_int = 1500;
  int ack_rate = 90;
  Duration ack_timeout;
  string device = "";
  string file_to_send = "";

  // to emulate ack sending delay I use random 
  auto rnd = Random(unpredictableSeed);

  GetoptResult getoptResult;
  try {
    getoptResult = getopt(args,
        "prefix|c", 
        "Prefix for redis config and stream keys. Default: dobaosll",
        &prefix,

        "host|h",
        "Host with llpub service running. Default: 127.0.0.1", 
        &host,

        "port|p", 
        "Redis port. Default: 6379", 
        &port,

        "device|d", 
        "Remote device.",
        &device,

        "file|f",
        "File to send.",
        &file_to_send,

        "max_seq|m",
        "Max sequence value. 1, 7, 15, 31. Default: 7",
        &max_seq,

        "ack_time|t",
        "Timeout for ack arrival in ms. Default: 1500",
        &ack_timeout_int,

        "ack_rate|r",
        "Rate in percent for acknowledging data frames. Default: 90",
        &ack_rate,

        "packet_len|l",
        "Length for packet. 1-MAX_APDU. Default: 45",
        &msg_len
        );
  } catch(Exception e) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - send user file_to_send.\n";
    info ~= "if you want to receive file - run without -d and -f args.\n";
    defaultGetoptPrinter(info,
        getoptResult.options);
    writeln(e.message);
    return;
  }

  nr_bufs = ((max_seq + 1)/2);
  ack_timeout = ack_timeout_int.msecs;

  writeln("max_seq number: ", max_seq);
  writeln("sliding win size: ", nr_bufs);
  writeln("ack_timeout, ms: ", ack_timeout_int);
  writeln("ack_rate, %: ", ack_rate);
  writeln("packet_size, bytes: ", msg_len);

  if (getoptResult.helpWanted) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - send user file_to_send.\n";
    info ~= "if you want to receive file - run without -d and -m args.\n";
    defaultGetoptPrinter(info,
        getoptResult.options);
    return;
  }

  MProp mprop = new MProp(host, port, prefix);
  ubyte[] local_descr = mprop.read(83);
  ubyte[] local_sn = mprop.read(11);
  ubyte[] local_manu = mprop.read(12);
  ubyte local_sub = mprop.read(57)[0];
  ubyte local_addr = mprop.read(58)[0];
  ushort local_ia = to!ushort(local_sub << 8 | local_addr);
  writeln("BAOS address: ", ia2str(local_ia));

  bool client_mode = false;
  if (device.length > 0 && file_to_send.length > 0)
    client_mode = true;

  NetworkFrame[] queue;
  ushort server_addr;
  if (client_mode) {
    server_addr = str2ia(device);
    writeln("tryin to send [", file_to_send, "] to device ", device);
    if (!exists(file_to_send)) {
      writeln("File doesn't exist");
      return;
    }
    // read file
    ubyte[] data = cast(ubyte[]) read(file_to_send);
    // divide data by chunks
    queue.reserve(data.length/msg_len + 1);
    while(data.length > 0)  {
      NetworkFrame q;
      q.type = FrameType.data;
      if (data.length > msg_len) {
        q.data ~= data[0..msg_len].dup;
        data = data[msg_len..$];
      } else {
        q.data ~= data.dup;
        data = [];
      }
      q.dest = server_addr;
      queue ~= q;
    }
  }

  NetworkSocket nl = new NetworkSocket(host, port, prefix);
  writeln("network socket created");

  if (client_mode) {
    // connect
    NetworkFrame c;
    c.type = FrameType.connect;
    c.dest = server_addr;
    nl.send(c, SEND_DELAY);
  }

  // protocol implementation begin
  ubyte ack_expected = 0,
        next_frame_to_send = 0,
        frame_expected = 0,
        too_far = nr_bufs;
  NetworkFrame[] out_buf; out_buf.length = nr_bufs;
  NetworkFrame[] in_buf; in_buf.length = nr_bufs;
  bool[] acknowledged; acknowledged.length = nr_bufs;
  StopWatch[] ack_timers; ack_timers.length = nr_bufs;
  int nbuffered = 0;

  bool[] arrived; arrived.length = nr_bufs;

  bool can_send = true;

  ubyte[] result;
  int lost_count, arrived_count; // to get stats

  bool done = false;
  auto idx = 0; auto total = queue.length;
  while(!done) {
    if (can_send && queue.length > 0) {
      NetworkFrame q = queue[0];

      q.seq = next_frame_to_send;
      // save frame to resend it in case of timeout
      out_buf[q.seq % nr_bufs] = q;
      nl.send(q, SEND_DELAY);
      writeln("sending packet ", idx, "/", total);
      idx += 1;
      nbuffered += 1;
      // freshly sent packet is not acknowledged yet.
      // start acknowledge timer
      acknowledged[q.seq % nr_bufs] = false;
      ack_timers[q.seq % nr_bufs] = StopWatch(AutoStart.no);
      ack_timers[q.seq % nr_bufs].reset();
      ack_timers[q.seq % nr_bufs].start();

      // slide window
      next_frame_to_send = inc(next_frame_to_send, max_seq);
      // decrease queue size
      if (queue.length == 1) {
        queue = [];
      } else {
        queue = queue[1..$];
      }
    }

    can_send = (nbuffered < nr_bufs) && nl.available;

    NetworkFrame recvd = nl.receive();

    switch(recvd.type) {
      case FrameType.connect:
        ack_expected = 0,
                     next_frame_to_send = 0,
                     frame_expected = 0,
                     too_far = nr_bufs;
        lost_count = 0, arrived_count = 0;
        for (auto i = 0; i < nr_bufs; i += 1) {
          acknowledged[i] = false;
          arrived[i] = false;
          out_buf[i] = NetworkFrame([0]);
        }
        nbuffered = 0;
        result = [];
        writeln("client connected");
        break;
      case FrameType.disconnect:
        writeln("client disconnected", );
        auto f = File("file.out", "w");
        f.write(cast(string)result);
        writeln("saved output to file.out"); 
        writeln("lost frames: ", lost_count);
        writeln("arrived: ", arrived_count);
        break;
      case FrameType.data:
        if (between(frame_expected, recvd.seq, too_far) && 
            !arrived[recvd.seq % nr_bufs]) {

          // emulate lost data frame
          auto rd = uniform(0, 100, rnd);
          if (rd > ack_rate) {
            lost_count += 1;
            break;
          } else {
            arrived_count += 1;
          }

          arrived[recvd.seq % nr_bufs] = true;
          in_buf[recvd.seq % nr_bufs] = recvd;
          NetworkFrame a;
          a.type = FrameType.ack;
          a.seq = recvd.seq;
          a.dest = recvd.source;
          nl.send(a, SEND_DELAY);

          // slide window
          while(arrived[frame_expected % nr_bufs]) {
            result ~= in_buf[frame_expected % nr_bufs].data;
            arrived[frame_expected % nr_bufs] = false;
            frame_expected = inc(frame_expected, max_seq);
            too_far = inc(too_far, max_seq);
          }
        } else if (arrived[recvd.seq % nr_bufs]){
          //send duplicate ACK
          NetworkFrame a;
          a.type = FrameType.ack;
          a.seq = recvd.seq;
          a.dest = recvd.source;
          //nl.send(a, SEND_DELAY);
        }
        break;
      case FrameType.ack:
        if (between(ack_expected, recvd.seq, next_frame_to_send) && 
            !acknowledged[recvd.seq % nr_bufs]) {
          acknowledged[recvd.seq % nr_bufs] = true;
          ack_timers[recvd.seq % nr_bufs].stop();
          ack_timers[recvd.seq % nr_bufs].reset();
          while(acknowledged[ack_expected % nr_bufs]) {
            result ~= recvd.data;
            acknowledged[ack_expected % nr_bufs] = false;
            ack_expected = inc(ack_expected, max_seq);
            nbuffered -= 1;
          }

          // nothing is awaiting ack and queue is empty
          // client should end his work
          if (nbuffered == 0 && queue.length == 0 && client_mode)
            done = true;
        }
        break;
      case FrameType.nack:
        break;
      default:
        break;
    }
    // process timers
    for (auto i = 0; i < nr_bufs; i += 1) {
      if (acknowledged[i]) continue;
      Duration d = ack_timers[i].peek();
      if (d > ack_timeout) {
        writeln("ack timeout, resending");
        // resend and reset timer
        nl.send(out_buf[i], SEND_DELAY);
        ack_timers[i].reset();
        ack_timers[i].start();
      }
    }
  }

  // finally, send disconnect
  if (client_mode) {
    // connect
    NetworkFrame d;
    d.type = FrameType.disconnect;
    d.dest = server_addr;
    nl.send(d, SEND_DELAY);
  }
}

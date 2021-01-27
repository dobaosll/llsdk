import core.thread;
import std.bitmanip;
import std.conv;
import std.digest;
import std.file;
import std.json;
import std.datetime.stopwatch;
import std.getopt;
import std.parallelism;
import std.stdio;
import std.string;

import llsdk;

void main(string[] args) {
  string prefix = "dobaosll";
  string host = "127.0.0.1";
  ushort port = 6379;
  string line = "";
  ubyte start = 1;
  ubyte end = 255;
  string fname = "";
  int thread_num = 1;

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

        "line|l", 
        "Line to scan. If empty, scan BAOS subnetwork.",
        &line,

        "start|s", 
        "Start scanning from device. Default: 1",
        &start,

        "end|e", 
        "Stop at given device. Default: 255",
        &end,

        "threads|t", 
        "Number of threads for parallel operation. Default: 1",
        &thread_num,

        "output|o",
        "Filename to save output in JSON format.",
        &fname);
  } catch(Exception e) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - scan line.\n";
    info ~= "Scan given line.";
    info ~= "If no --line argument was provided, scan BAOS subnetwork.";
    defaultGetoptPrinter(info,
        getoptResult.options);
    writeln(e.message);
    return;
  }

  if (getoptResult.helpWanted) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - scan line.\n";
    info ~= "Scan given line.";
    info ~= "If no --line argument was provided, scan BAOS subnetwork.";
    defaultGetoptPrinter(info,
        getoptResult.options);
    return;
  }

  ubyte[] lines;
  string[] lines_str = line.split(" ");
  foreach(string line_addr; lines_str) {
    try {
      if (line_addr == "") continue;
      lines ~= str2subnetwork(line_addr);
    } catch(Exception e) {
      writeln(e.message);
      return;
    }
  }

  MProp mprop = new MProp(host, port, prefix);
  ubyte[] local_descr = mprop.read(83);
  ubyte[] local_sn = mprop.read(11);
  ubyte[] local_manu = mprop.read(12);
  ubyte local_sub = mprop.read(57)[0];
  ubyte local_addr = mprop.read(58)[0];
  ushort local_ia = to!ushort(local_sub << 8 | local_addr);

  if (lines.length == 0) {
    // if no line was provided in args, use BAOS module line
    lines ~= local_sub;
  }

  JSONValue jout = parseJSON("[]");

  foreach(ubyte sub; lines) {
    string lineStr = subnetwork2str(sub);
    writeln("Scanning line ", lineStr);
    ushort[] ia2scan;
    for (int i = start; i <= end; i += 1) {
      ubyte a = i & 0xff;
      ushort addr = sub*256 + a;
      ia2scan ~= addr;
    }
    //for (int i = start; i <= end; i += 1) {
    auto workUnitSize = ia2scan.length/thread_num;

    auto taskPool = new TaskPool(thread_num);
    foreach(i, addr; taskPool.parallel(ia2scan, workUnitSize)) {
      JSONValue jo = parseJSON("{}");
      writeln("Scanning address ", ia2str(addr));
      if (addr == local_ia) {
        jo["addr_ushort"] = local_ia;
        jo["addr_string"] = ia2str(local_ia);
        jo["sn"] = local_sn.toHexString;
        jo["descr"] = local_descr.toHexString;
        jo["manufacturer"] = local_manu.toHexString;
        jout.array ~= jo;

        writefln("..Local [%s Descr: %s. SN: %s. Manuf-r: %s.]", 
            ia2str(local_ia), toHexString(local_descr), toHexString(local_sn),
            local_manu.toHexString); 
        continue;
      }
      auto tc = new TConn(addr, host, port, prefix);
      tc.connect();
      if (!tc.connected) {
        writeln("..TConnect.req confirmation error ", ia2str(addr));
        continue;
      }
      writeln("..TConnect.req confirmed ", ia2str(addr));
      ubyte[] descr;
      ubyte[] serial;
      ubyte[] manufacturer;
      try {
        descr = tc.deviceDescriptorRead();
      } catch(Exception e) {
        writefln("..Error reading device %s descriptor: %s",
            ia2str(addr), e.message);
        continue;
      }
      try {
        // manufacturer code: Obj 0, PID 12, num 1, start 01
        manufacturer = tc.propertyRead(0x0c, 0x00, 0x01, 0x01);
      }  catch(Exception e) {
        writefln("..Error reading device %s manufacturer code: %s",
            ia2str(addr), e.message);
      }
      try {
        // serialnum: Obj 0, PID 11, num 1, start 1
        serial = tc.propertyRead(0x0b, 0x00, 0x01, 0x01);
        Thread.sleep(50.msecs);
      } catch(Exception e) {
        writefln("..Error reading device %s serial number: %s",
            ia2str(addr), e.message);
      } finally {
        tc.disconnect();
        jo["addr_ushort"] = addr;
        jo["addr_string"] = ia2str(addr);
        jo["descr"] = descr.toHexString;
        jo["sn"] = serial.toHexString;
        jo["manufacturer"] = manufacturer.toHexString;
        jout.array ~= jo;
        writefln("..[%s Descr: %s. SN: %s. Manuf-r: %s. ]",
            ia2str(addr), toHexString(descr),
            toHexString(serial), toHexString(manufacturer));
      }
    }
  }

  writeln("=================");
  if (fname.length > 0) {
    writeln("saving to file <", fname, ">");
    auto file = File(fname, "w");
    file.writeln(jout.toPrettyString);
  }
  writeln(jout.toPrettyString);
}

import core.thread;
import std.digest;
import std.conv;
import std.datetime.stopwatch;
import std.stdio;
import std.getopt;
import std.string;

import llsdk;

void main(string[] args) {

  string prefix = "dobaosll";
  string host = "127.0.0.1";
  ushort port = 6379;
  string device = "";
  ushort mode = 0;
  ubyte[] progmode;

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
        "Remote device. If empty, MProp for BAOS will be used.",
        &device,

        std.getopt.config.required,
        "mode|m",
        "Mode value: 0/1. Required",
        &mode);
  } catch(Exception e) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - progmode.\n";
    info ~= "Set programming mode of local(BAOS) or remote device.";
    defaultGetoptPrinter(info,
        getoptResult.options);
    writeln(e.message);
    return;
  }

  if (getoptResult.helpWanted) {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - progmode.\n";
    info ~= "Set programming mode of local(BAOS) or remote device.";
    defaultGetoptPrinter(info,
        getoptResult.options);
    return;
  }

  if (mode != 0 && mode != 1) {
    writeln("Value should be 1 or 0");
    return;
  }
  progmode ~= to!ubyte(mode);
  if (device.length == 0) {
    writeln("Writing progmode for BAOS module: ", mode);

    MProp mprop;
    try {
      mprop = new MProp(host, port, prefix);
    } catch(Exception e) {
      writeln("Exception while initializing MProp client.");
      writeln(e.message);
      return;
    }
    try {
      mprop.write(54, progmode);
    } catch (Exception e) {
      writeln("Error writing progmode property: ", e.message);
    }
  } else {
    writeln("Writing progmode for remote device ", device, ": ", mode);
    ushort ia = str2ia(device);
    TConn tc;
    try {
      tc = new TConn(ia, host, port, prefix);
    } catch(Exception e) {
      writeln("Exception while initializing TConn instance.");
      writeln(e.message);
      return;
    }
    ubyte[] descr = [];
    try {
      tc.connect();
      descr = tc.deviceDescriptorRead();
      writeln("Device descriptor: ", descr.toHexString);
      if (descr.toHexString == "07B0") {
        ubyte[] currentMode = tc.propertyRead(54, 0, 1, 1);
        writeln("APropertyRead response: ", currentMode.toHexString);
        ubyte[] newMode = tc.propertyWrite(54, progmode, 0, 1, 1);
        writeln("APropertyWrite response: ", newMode.toHexString);
      } else if (descr.toHexString == "0705") {
        ubyte[] mem = tc.memoryRead(96, 1);
        writeln("Old value: ", mem[$-1]);
        tc.memoryWrite(96, progmode);
        mem = tc.memoryRead(96, 1);
        writeln("New value: ", mem[$-1]);
      } else {
        writeln("I don't know how to work with this device descriptor yet.");
      }
    } catch (Exception e) {
      writeln("Error writing progmode property: ", e.message);
    } finally {
      writeln("bye");
      tc.disconnect();
    }
  }
}

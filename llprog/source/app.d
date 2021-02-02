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
  ubyte progmode;

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
  progmode = to!ubyte(mode);
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
      mprop.write(54, [progmode]);
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
      switch(descr.toHexString) {
        case "07B0":
        case "091A":
        case "17B1":
        case "2705":
        case "27B1":
        case "2920":
        case "57B0":
          writeln("flavour_prop");
          ubyte[] currentMode = tc.propertyRead(54, 0, 1, 1);
          writeln("Old value: ", currentMode[0]);
          ubyte[] newMode = tc.propertyWrite(54, [progmode], 0, 1, 1);
          writeln("New value: ", newMode[0]);
          break;
        case "0010":
        case "0011":
        case "0012":
        case "0013":
        case "0020":
        case "0021":
        case "0025":
        case "0700":
        case "0701":
        case "0705":
        case "0900":
        case "0910":
        case "0911":
        case "0912":
        case "1011":
        case "1012":
        case "1013":
        case "1900":
        case "5705":
          writeln("flavour_bcu1");
          // flavour bcu1
          ubyte[] mem = tc.memoryRead(0x60, 1);
          ubyte oldmem = mem[$-1];
          ubyte newmem;
          ubyte oldmode = oldmem & 0b1;
          ubyte parity = (oldmem & 0b10000000) >> 7;
          writeln("Old value: ", oldmode);
          if (progmode != oldmode) {
            parity = parity == 0 ? 1: 0;
          }
          newmem = oldmem & 0b01111110; // clear parity and progmode bit
          newmem = newmem | progmode; // write new mode
          newmem = (newmem | (parity << 7)) & 0xff; // write parity bit
          tc.memoryWrite(0x60, [newmem]);
          mem = tc.memoryRead(96, 1);
          writeln("New value: ", mem[$-1] & 0b1);
          break;
        default:
          writeln("I don't know how to work with this device descriptor yet.");
          break;
      }
    } catch (Exception e) {
      writeln("Error writing progmode property: ", e.message);
    } finally {
      writeln("Disconnecting..");
      tc.disconnect();
    }
  }
}

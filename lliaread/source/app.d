import core.thread;
import std.digest;
import std.conv;
import std.datetime.stopwatch;
import std.stdio;
import std.getopt;
import std.string;

import llsdk.tbroadcast;

void main(string[] args) {
  string prefix = "dobaosll";
  string host = "127.0.0.1";
  ushort port = 6379;

  GetoptResult getoptResult;
  void printHelp() {
    string info = "SDK for Weinzierl BAOS 83x Data Link Layer - ind address read.\n";
    info ~= "Read devices in programming mode.";
    defaultGetoptPrinter(info,
        getoptResult.options);
  }
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
        &port
        );
  } catch(Exception e) {
    printHelp();
    writeln(e.message);
    return;
  }

  if (getoptResult.helpWanted) {
    printHelp();
    return;
  }

  auto tb = new TBroadcast(host, port, prefix);
  
  while(true) {
    try {
      auto res = tb.iaRead();
      writeln(res);
    } catch (Exception e) {
      writeln(e.message);
    }
  }
}

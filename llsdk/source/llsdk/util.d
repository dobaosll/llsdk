module llsdk.util;

import std.conv;
import std.string;

import llsdk.errors;

public:

// individual address
string ia2str(ushort ia) {
  string area = to!string(ia >> 12);
  string line = to!string((ia >> 8) & 0b1111);
  string device = to!string(ia & 0xff);

  return area ~ "." ~ line ~ "." ~ device;
}
ushort str2ia(string addr) {
  string[] arr = addr.split(".");
  if (arr.length != 3) throw new Exception(ERR_WRONG_IA);

  ubyte main = parse!ubyte(arr[0]);
  ubyte middle = parse!ubyte(arr[1]);
  ubyte main_middle = ((main << 4) | middle) & 0xff;
  ubyte address = parse!ubyte(arr[2]);

  return to!ushort(main_middle << 8 | address);
}

// group address
string grp2str(ushort grp) {
  string main = to!string(grp >> 11);
  string middle = to!string((grp >> 8) & 0b111);
  string group = to!string(grp & 0xff);

  return main ~ "/" ~ middle ~ "/" ~ group;
}
ushort str2grp(string grp) {
  string[] arr = grp.split("/");
  if (arr.length != 3) throw new Exception(ERR_WRONG_GRP);

  ubyte main = parse!ubyte(arr[0]);
  ubyte middle = parse!ubyte(arr[1]);
  ubyte main_middle = ((main << 3) | middle) & 0xff;
  ubyte address = parse!ubyte(arr[2]);

  return to!ushort(main_middle << 8 | address);
}

// subnetwork - line.area
ubyte str2subnetwork(string subStr) {
  string[] arr = subStr.split(".");
  if (arr.length != 2) {
    throw new Exception(ERR_WRONG_SUBNETWORK_ADDR);
  }
  ubyte main = parse!ubyte(arr[0]);
  ubyte middle = parse!ubyte(arr[1]);

  return to!ubyte(((main << 4)|middle));
}
string subnetwork2str(ubyte sub) {
  string res;
  res ~= to!string(sub >> 4);
  res ~= ".";
  res ~= to!string(sub & 0xf);
  return res;
}

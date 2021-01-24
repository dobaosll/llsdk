module knxnet;

import std.conv;
import std.digest;
import std.bitmanip;
import std.range.primitives: empty;
import std.socket;
import std.stdio;


enum KNXServices: ushort {
  unknown,
  // SEARCH_REQ Sent by KNXnet/IP Client to search available KNXnet/IP Servers.
  SEARCH_REQUEST = 0x0201,  
  // Sent by KNXnet/IP Server when receiving a KNXnet/IP SEARCH_REQUEST.
  SEARCH_RESPONSE = 0x0202, 

  // Sent by KNXnet/IP Client to a KNXnet/IP Server to retrieve
  // information about capabilities and supported services
  DESCRIPTION_REQUEST = 0x203, 
  // Sent by KNXnet/IP Server in response to a DESCRIPTION_REQUEST
  // to provide information about the server implementation.
  DESCRIPTION_RESPONSE = 0x0204, 

  // Sent by KNXnet/IP Client for establishing a communication channel to a KNXnet/IP Server.
  CONNECT_REQUEST = 0x0205, 
  // Sent by KNXnet/IP Server as answer toCONNECT_REQUEST telegram.
  CONNECT_RESPONSE = 0x0206, 

  // Sent by KNXnet/IP Client for requesting the connection
  // state of an established connection to a KNXnet/IP Server.   
  CONNECTIONSTATE_REQUEST = 0x0207,
  // Sent by KNXnet/IP Server when receiving a 
  // CONNECTIONSTATE_REQUEST for an established connection.
  CONNECTIONSTATE_RESPONSE = 0x0208,

  // Sent by KNXnet/IP device, typically the KNXnet/IP Client,
  // to terminate an established connection.
  DISCONNECT_REQUEST = 0x0209,
  // Sent by KNXnet/IP device, typically the KNXnet/IP Server,
  // in response to a DISCONNECT_REQUEST.
  DISCONNECT_RESPONSE = 0x020A, 

  // Reads/Writes KNXnet/IP device configuration data (Interface Object Properties)
  DEVICE_CONFIGURATION_REQUEST = 0x0310,
  // Sent by a KNXnet/IP device to confirm the reception of the DEVICE_CONFIGURATION_REQUEST
  DEVICE_CONFIGURATION_ACK = 0x0311, 

  // Used for sending and receiving single KNX
  // telegrams between KNXnet/IP Client and - Server
  TUNNELING_REQUEST = 0x0420, 
  // Sent by a KNXnet/IP device to confirm the reception of the TUNNELING_REQUEST
  TUNNELING_ACK = 0x0421
};

enum KNXConnTypes: ubyte {
  // Data connection used to configure a KNXnet/IP device
  DEVICE_MGMT_CONNECTION = 0x03, 
  // Data connection used to forward KNX telegrams between two KNXnet/IP devices
  TUNNEL_CONNECTION = 0x04, 
  // Data connection used for configuration and data transfer with a remote logging server
  REMLOG_CONNECTION = 0x06, 
  //Data connection used for data transfer with a remote configuration server.
  REMCONF_CONNECTION = 0x07, 
  // Data connection used for configuration and data transfer 
  // with an Object Server in a KNXnet/IP device.
  OBJSVR_CONNECTION = 0x08, 
};

enum KNXErrorCodes: ubyte {
  // Error Codes
  E_NO_ERROR = 0x00,
  E_HOST_PROTOCOL_TYPE = 0x01,
  E_VERSION_NOT_SUPPORTED = 0x02,
  E_SEQUENCE_NUMBER = 0x04,
  E_CONNECTION_ID = 0x21,
  E_CONNECTION_TYPE = 0x22,
  E_CONNECTION_OPTION = 0x23,
  E_NO_MORE_CONNECTIONS = 0x24,
  E_DATA_CONNECTION = 0x26,
  E_KNX_CONNECTION = 0x27,
  E_TUNNELING_LAYER = 0x29,
};

enum CRI: ubyte {
  //CRI
  TUNNEL_LINKLAYER = 0x02,
  TUNNEL_RAW = 0x04,
  TUNNEL_BUSMONITOR = 0x80,
};

enum DIB_SUPP_SVC {
  CORE = 0x02,
  DEV_MGMT = 0x03,
  TUNNEL = 0x04
}

enum cEMI_MC {
  LDATA_REQ = 0x11,
  LDATA_CON = 0x2E,
  LDATA_IND = 0x29,
  MPROPREAD_REQ = 0xFC,
  MPROPREAD_CON = 0xFB,
  MPROPWRITE_REQ = 0xF6,
  MPROPWRITE_CON = 0xF5,
  MPROPINFO_IND = 0xF7,
  MRESET_REQ = 0xF1,
  MRESET_IND = 0xF0
}

// constants
enum KNXConstants: ubyte {
  VERSION_10 = 0x10,
  SIZE_10 = 0x6,
};

enum KNXDescriptionTypes: ubyte {
  DEVICE_INFO = 0x01,
  SUPP_SVC_FAMILIES = 0x02,
  // there is more, not gonna implement right now
  // from 03_08_02 core, page 23
};


ubyte[] request(ubyte[] cemiFrame, ubyte channel = 0x00, ubyte seq = 0x00) {
  ubyte[] result = []; result.length = 4;

  auto offset = 0;
  result.write!ubyte(4, offset);
  offset += 1;
  result.write!ubyte(channel, offset);
  offset += 1;
  result.write!ubyte(seq, offset); // seq counter. azaaza
  offset += 1;
  result.write!ubyte(0x00, offset); // reserved
  offset += 1;

  result ~= cemiFrame;

  return result;
}

ubyte[] ack(ubyte channel = 0x00, ubyte seq = 0x00) {
  ubyte[] result = []; result.length = 4;

  auto offset = 0;
  result.write!ubyte(4, offset);
  offset += 1;
  result.write!ubyte(channel, offset);
  offset += 1;
  result.write!ubyte(seq, offset); // seq counter. azaaza
  offset += 1;
  result.write!ubyte(KNXErrorCodes.E_NO_ERROR, offset); // no error yet
  offset += 1;

  return result;
}
ubyte[] connectionStateResponse(ubyte error, ubyte channel) {
  ubyte[] result = []; result.length = 2;

  auto offset = 0;
  result.write!ubyte(channel, offset);
  offset += 1;
  result.write!ubyte(error, offset); // no error yet
  offset += 1;

  return result;
}
ubyte[] disconnectRequest(ubyte channel, ubyte[] hpai) {
  ubyte[] result = [];
  result.length = 3; // ch, reserv, hpai len
  result.write!ubyte(channel, 0);
  result.write!ubyte(0x00, 1); //reserved
  result.write!ubyte(to!ubyte(hpai.length + 1), 2);
  result ~= hpai;

  return result;
}
ubyte[] disconnectResponse(ubyte error, ubyte channel) {
  ubyte[] result = []; result.length = 2;

  auto offset = 0;
  result.write!ubyte(channel, offset);
  offset += 1;
  result.write!ubyte(error, offset); // no error yet
  offset += 1;

  return result;
}

ubyte[] connectResponseSuccess(ubyte channel, ubyte connType, ushort ia = 0x0000) {
  ubyte[] result = [];

  auto offset = 0; result.length = 2 + 8 + 2;
  // channel, error. 2 bytes
  result.write!ubyte(channel, offset); offset += 1;
  result.write!ubyte(KNXErrorCodes.E_NO_ERROR, offset); offset += 1;

  // hpai
  result.write!ubyte(0x08, offset); offset += 1; // len
  result.write!ubyte(0x01, offset); offset += 1; // protocol code udp
  result.write!ubyte(0x00, offset); offset += 1; // azaza
  result.write!ubyte(0x00, offset); offset += 1;// ...
  result.write!ubyte(0x00, offset); offset += 1;
  result.write!ubyte(0x00, offset); offset += 1;
  result.write!ubyte(0x00, offset); offset += 1;
  result.write!ubyte(0x00, offset); offset += 1;

  // crd

  if (connType == KNXConnTypes.TUNNEL_CONNECTION) {
    result.write!ubyte(0x04, offset); offset += 1; // len
    result.write!ubyte(connType, offset); offset += 1; // connection type
    result.length += 2;
    result.write!ushort(ia, offset); // knx addr
  } else if (connType == KNXConnTypes.DEVICE_MGMT_CONNECTION) {
    result.write!ubyte(0x02, offset); offset += 1; // len
    result.write!ubyte(connType, offset); offset += 1; // connection type
  }

  return result;
}
ubyte[] connectResponseError(ubyte channel, ubyte error) {
  ubyte[] result = [];

  auto offset = 0; result.length = 2;
  // channel, error. 2 bytes
  result.write!ubyte(channel, offset); offset += 1;
  result.write!ubyte(error, offset); offset += 1;

  return result;
}
ubyte[] descriptionResponse(ushort ia, ubyte[] serialNumber, ubyte[] macAddress, string friendlyName) {
  ubyte[] result = [];

  auto offset = 0; result.length = 255;
  // channel, error. 2 bytes

  // : DIB
  // : DIB 1 - devinfo
  // : DIB 2 - supported services
  // Let't go
  offset = 0;
  result.write!ubyte(0x00, offset); // total length of struct
  offset += 1;
  result.write!ubyte(KNXDescriptionTypes.DEVICE_INFO, offset);
  offset += 1;
  result.write!ubyte(0x02, offset); // knx medium
  offset += 1;
  result.write!ubyte(0x00, offset); // device status
  offset += 1;
  result.write!ushort(ia, offset); // knx address
  offset += 2;
  result.write!ushort(0x00, offset); // installation id
  offset += 2;
  result[offset..offset + 6] = serialNumber[0..6];
  offset += 6;
  result.write!ubyte(0x00, offset); offset += 1; // multicast addr
  result.write!ubyte(0x00, offset); offset += 1; // multicast addr
  result.write!ubyte(0x00, offset); offset += 1; // multicast addr
  result.write!ubyte(0x00, offset); offset += 1; // multicast addr
  result[offset..offset + 6] = macAddress[0..6];
  offset += 6;

  char[] name = friendlyName.dup;
  for (int i = 0; (i < name.length && i < 30); i += 1) {
    result.write!char(name[i], offset + i);
  }
  offset += 30; // lenght of name should be 30 octets

  // writeln("Length of DEV_INFO section: ", offset);
  result.write!ubyte(cast(ubyte)offset, 0); // write len at 0 position

  // supported services
  result.write!ubyte(0x08, offset); // total lenght of struct
  offset += 1;
  result.write!ubyte(KNXDescriptionTypes.SUPP_SVC_FAMILIES, offset);
  offset += 1;
  result.write!ubyte(DIB_SUPP_SVC.CORE, offset); // core services
  offset += 1;
  result.write!ubyte(0x01, offset); // of version 1
  offset += 1;
  result.write!ubyte(DIB_SUPP_SVC.DEV_MGMT, offset);
  offset += 1;
  result.write!ubyte(0x01, offset); // of version 1
  offset += 1;
  result.write!ubyte(DIB_SUPP_SVC.TUNNEL, offset); // tunnel connection supported also
  offset += 1;
  result.write!ubyte(0x01, offset); // of version 1
  offset += 1;
  result.length = offset;

  return result;
}

ubyte[] KNXIPMessage(ushort service, ubyte[] message) {
  ubyte[] dgram = [];
  ushort totalLen = to!ushort(KNXConstants.SIZE_10 + message.length);
  auto offset = 0; dgram.length = KNXConstants.SIZE_10;

  dgram.write!ubyte(KNXConstants.SIZE_10, offset); offset += 1;
  dgram.write!ubyte(KNXConstants.VERSION_10, offset); offset += 1;
  dgram.write!ushort(service, offset); offset += 2;
  // total len
  dgram.write!ushort(totalLen, offset); offset += 2;

  dgram ~= message;

  return dgram;
}

ubyte[] sendKNXIPMessage(ushort service, ubyte[] message, UdpSocket s, Address sendTo) {
  auto dgram = KNXIPMessage(service, message);
  if (sendTo is null) {
    writeln("SendTo is null");
    return [];
  }
  writeln("Sending: ", dgram.toHexString()," to:: ", sendTo);
  s.sendTo(dgram, sendTo);

  return dgram;
}

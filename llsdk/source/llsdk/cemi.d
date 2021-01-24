// cemi abstractions
// https://www.dehof.de/eib/pdfs/EMI-FT12-Message-Format.pdf
module llsdk.cemi;

import std.bitmanip;
import std.conv;

public:

enum MC: ubyte {
  unknown,
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

enum TService {
  unknown,
  TDataBroadcast,
  TDataGroup,
  TDataTagGroup,
  TDataIndividual,
  TDataConnected,
  TConnect,
  TDisconnect,
  TAck,
  TNack
}

enum APCI: ushort {
  AGroupValueRead = 0b0000,
  AGroupValueResponse = 0b0001,
  AGroupValueWrite = 0b0010,
  AIndividualAddressWrite = 0b0011,
  AIndividualAddressRead = 0b0100,
  AIndividualAddressResponse = 0b0101,
  AADCRead = 0b0110,
  AADCResponse = 0b0111,
  AMemoryRead = 0b1000,
  AMemoryResponse = 0b1001,
  AMemoryWrite = 0b1010,
  AUser = 0b1011,
  AUserMemoryRead = 0b1011000001,
  AUserMemoryResponse = 0b1011000001,
  AUserMemoryWrite = 0b1011000010,
  AUserMessageReq = 0b1011111000, // in specs it is manufacturer specific
  AUserMessageRes = 0b1011111110, // so, assume request-response model
  AUserManufacturerInfoRead = 0b1011000101,
  AUserManufacturerInfoResponse = 0b1011000110,
  ADeviceDescriptorRead = 0b1100,
  ADeviceDescriptorResponse = 0b1101,
  ARestart = 0b1110,
  AEscape = 0b1111,
  APropertyValueRead = 0b1111010101,
  APropertyValueResponse = 0b1111010110,
  APropertyValueWrite = 0b1111010111,
  APropertyDescriptionRead = 0b1111011000,
  APropertyDescriptionResponse = 0b1111011001
}

class LData_cEMI {
  public MC message_code;
  public ubyte[] additional_info;

  // control field 1
  private ubyte cf1;
  public bool standard; // extended 0, standard 1
  public bool donorepeat; // 0 - repeat, 1 - do not
  public bool sys_broadcast;
  public ubyte priority;
  public bool ack_requested;
  public bool error; // 0 - no error(confirm)
  // control field 2
  private ubyte cf2;
  public bool address_type_group; // 0 - individual, 1 - group;
  public ubyte hop_count; 
  public ubyte ext_frame_format; // 0 - std frame

  public ushort source;
  public ushort dest;

  public ubyte apci_data_len;
  private ubyte tpci_apci;
  private ubyte[] apci_data;

  public ubyte tpci;
  public TService tservice;
  public ubyte tseq;
  public APCI apci;
  public ubyte[] data;
  
  // 6bits that goes together with apci, if apci_data_len > 1
  public ubyte tiny_data; 

  private void getCFInfo() {
    // extract info from cf1
    standard = to!bool(cf1 >> 7);
    donorepeat = to!bool((cf1 >> 5) & 0b1);
    sys_broadcast = to!bool((cf1 >> 4) & 0b1);
    priority = to!ubyte((cf1 >> 2) & 0b11);
    ack_requested = to!bool((cf1 >> 1) & 0b1);
    error = to!bool(cf1 & 0b1);
    // from cf2
    address_type_group = to!bool(cf2 >> 7);
    hop_count = to!ubyte((cf2 >> 4) & 0b111);
    ext_frame_format = to!ubyte(cf2 & 0b1111);
  }
  private void calculateCF() {
    // calculate cf1 and cf2
    cf1 = 0x00;
    if (standard) {
      cf1 = cf1 | 0b10000000;
    }
    if (donorepeat) {
      cf1 = cf1 | 0b00100000;
    }
    if (sys_broadcast) {
      cf1 = cf1 | 0b00010000;
    }
    cf1 = to!ubyte(cf1 | (priority << 2));
    if (ack_requested) {
      cf1 = cf1 | 0b00000010;
    }
    if (error) {
      cf1 = cf1 | 0b00000001;
    }

    cf2 = 0x00;
    if (address_type_group) {
      cf2 = cf2 | 0b10000000;
    }
    cf2 = to!ubyte(cf2 | (hop_count << 4));
    cf2 = cf2 | (ext_frame_format & 0b1111);
  }
  // set control fields and calculate properties
  public void setControlFields(ubyte newCf1, ubyte newCf2) {
    cf1 = newCf1;
    cf2 = newCf2;
    getCFInfo();
  }
  public void getTransportServiceInfo() {
    // extract information from tpci data bits
    bool data_control_flag = to!bool((tpci >> 7) & 0b1);
    bool numbered = to!bool((tpci >> 6) & 0b1);
    tseq = to!ubyte((tpci >> 2 ) & 0b1111);
    if (address_type_group) {
      // group address
      if (!data_control_flag && !numbered) {
        if (dest == 0 && tseq == 0) tservice = TService.TDataBroadcast;
        if (dest != 0 && tseq == 0) tservice = TService.TDataGroup;
        if (tseq != 0) tservice = TService.TDataTagGroup;
      }
    } else {
      // individual addr 
      if (!data_control_flag && !numbered && tseq == 0) tservice = TService.TDataIndividual;
      else if (!data_control_flag && numbered) tservice = TService.TDataConnected;
      else if (data_control_flag && !numbered && tpci == 0x80) tservice = TService.TConnect;
      else if (data_control_flag && !numbered && tpci == 0x81) tservice = TService.TDisconnect;
      else if (data_control_flag && numbered && (tpci & 0b11) == 0b10) tservice = TService.TAck;
      else if (data_control_flag && numbered && (tpci & 0b11) == 0b11) tservice = TService.TNack;
    }
  }

  this() {
    // default values
    message_code = MC.LDATA_REQ;
    setControlFields(0xbc, 0xe0);
  }
  this(ubyte[] msg) {
    // parse frame
    auto offset = 0;
    message_code = cast(MC) msg.peek!ubyte(offset); offset += 1;
    additional_info.length = msg.peek!ubyte(offset); offset += 1;
    additional_info = msg[offset..offset + additional_info.length].dup;
    offset += additional_info.length;
    cf1 = msg.peek!ubyte(offset); offset += 1;
    cf2 = msg.peek!ubyte(offset); offset += 1;
    
    // extract info from control fields
    getCFInfo();

    // addresses
    source = msg.peek!ushort(offset); offset += 2;
    dest = msg.peek!ushort(offset); offset += 2;
    apci_data_len = msg.peek!ubyte(offset); offset += 1;
    tpci_apci = msg.peek!ubyte(offset); offset += 1;
    apci_data = msg[offset..offset + apci_data_len].dup;
    
    if (apci_data_len == 0) {
      tpci = tpci_apci;
      //apci = ((tpci_apci & 0b11) << 2);
      data.length = 0;
    } else if (apci_data_len == 1) {
      tpci = tpci_apci & 0b11111100;
      apci = cast(APCI) (((tpci_apci & 0b11) << 2) | ((apci_data[0] & 0b11000000) >> 6));
      tiny_data = apci_data[0] & 0b00111111;
    } else if (apci_data_len > 1) {
      tpci = tpci_apci & 0b11111100;
      apci = cast(APCI) (((tpci_apci & 0b11) << 2) | ((apci_data[0] & 0b11000000) >> 6));
      data.length = apci_data_len - 1;
      data[0..$] = apci_data[1..$];
      // cases like ADCRead/ADCResponse
      // where data is encoded in next six bits
      tiny_data = apci_data[0] & 0b111111;
    }
    if (apci == APCI.AUser || apci == APCI.AEscape) {
      apci = cast(APCI) ((apci << 6) | tiny_data);
      tiny_data = 0;
    }
    getTransportServiceInfo();
  }
  public void calculateTpci() {
    // calculate tpci ubyte from tservice and tseq
    bool data_control_flag;
    bool numbered;
    ubyte last_bits = 0b00;
    switch (tservice) {
      case TService.TDataBroadcast:
      case TService.TDataGroup:
      case TService.TDataTagGroup:
      case TService.TDataIndividual:
        data_control_flag = false;
        numbered = false;
        break;
      case TService.TDataConnected:
        data_control_flag = false;
        numbered = true;
        break;
      case TService.TConnect:
        data_control_flag = true;
        numbered = false;
        last_bits = 0b00;
        break;
      case TService.TDisconnect:
        data_control_flag = true;
        numbered = false;
        last_bits = 0b01;
        break;
      case TService.TAck:
        data_control_flag = true;
        numbered = true;
        last_bits = 0b10;
        break;
      case TService.TNack:
        data_control_flag = true;
        numbered = true;
        last_bits = 0b11;
        break;
      default:
        break;
    }
    tpci = 0x00;
    if (data_control_flag) tpci = tpci | 0b10000000;
    if (numbered) {
      tpci = tpci | 0b01000000;
      tpci = tpci | ((tseq & 0b1111) << 2);
    }
    tpci = tpci | last_bits;
  }

  public ubyte[] toUbytes() {
    ubyte[] result;
    result.length = 10 + additional_info.length + apci_data_len;
    auto offset = 0;
    result.write!ubyte(message_code, offset); offset += 1;
    result.write!ubyte(to!ubyte(additional_info.length & 0xff), offset); offset += 1;
    result[offset..offset + additional_info.length] = additional_info[0..$];
    offset += additional_info.length;

    // calculate control fields
    calculateCF();

    result.write!ubyte(cf1, offset); offset += 1;
    result.write!ubyte(cf2, offset); offset += 1;
    result.write!ushort(source, offset); offset += 2;
    result.write!ushort(dest, offset); offset += 2;

    result.write!ubyte(to!ubyte(apci_data_len), offset); offset += 1;

    calculateTpci();
    
    apci_data.length = apci_data_len;
    if (apci_data_len == 0) {
      // only tpci presented
      result.write!ubyte(tpci, offset); offset += 1;
    } else if (apci_data_len == 1 ) {
      // apci with tiny data (6bits)
      tpci_apci = tpci & 0b11111100;
      if (apci < 0b1111) {
        tpci_apci = to!ubyte(tpci_apci | ((apci & 0b1111) >> 2));
      } else {
        tpci_apci = to!ubyte(tpci_apci | (apci  >> 8));
      }
      result.write!ubyte(tpci_apci, offset); offset += 1;
      apci_data[0] = (apci & 0b11) << 6;
      if (apci < 0b1111) {
        apci_data[0] = apci_data[0] | (tiny_data & 0b111111);
      } else {
        apci_data[0] = apci & 0b11111111;
      }
      result[offset..$] = apci_data[0..$];
    } else if (apci_data_len > 1) {
      tpci_apci = tpci;
      if (apci < 0b1111) {
        tpci_apci = to!ubyte(tpci_apci | ((apci & 0b1111) >> 2));
      } else {
        tpci_apci = to!ubyte(tpci_apci | (apci  >> 8));
      }
      result.write!ubyte(tpci_apci, offset); offset += 1;
      if (apci < 0b1111) {
        apci_data[0] = (apci & 0b11) << 6;

        // cases like ADCRead/ADCResponse
        // where data is encoded in next six bits
        apci_data[0] = apci_data[0] | tiny_data;
      } else {
        apci_data[0] = apci & 0b11111111;
      }
      apci_data[1..$] = data[0..$];
      result[offset..$] = apci_data[0..$];
    }

    return result;
  }
}

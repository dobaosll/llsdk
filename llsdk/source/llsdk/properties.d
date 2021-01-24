module llsdk.properties;

enum PDT: ubyte {
  PDT_CONTROL = 0,
  PDT_CHAR = 1,
  PDT_UNSIGNED_CHAR = 2,
  PDT_INT = 3,
  PDT_UNSIGNED_INT = 4,
  PDT_KNX_FLOAT = 5,
  PDT_DATE = 6,
  PDT_TIME = 7,
  PDT_LONG = 8,
  PDT_UNSIGNED_LONG = 9,
  PDT_FLOAT = 10,
  PDT_DOUBLE = 11,
  PDT_CHAR_BLOCK = 12,
  PDT_POLL_GROUP_SETTINGS = 13,
  PDT_SHORT_CHAR_BLOCK = 14,
  PDT_DATE_TIME = 15,
  PDT_VARIABLE_LENGTH = 16,
  PDT_GENERIC_01 = 17,
  PDT_GENERIC_02 = 18,
  PDT_GENERIC_03 = 19,
  PDT_GENERIC_04 = 20,
  PDT_GENERIC_05 = 21,
  PDT_GENERIC_06 = 22,
  PDT_GENERIC_07 = 23,
  PDT_GENERIC_08 = 24,
  PDT_GENERIC_09 = 25,
  PDT_GENERIC_10 = 26,
  PDT_GENERIC_11 = 27,
  PDT_GENERIC_12 = 28,
  PDT_GENERIC_13 = 29,
  PDT_GENERIC_14 = 30,
  PDT_GENERIC_15 = 31,
  PDT_GENERIC_16 = 32,
  PDT_GENERIC_17 = 33,
  PDT_GENERIC_18 = 34,
  PDT_GENERIC_19 = 35,
  PDT_GENERIC_20 = 36,
  PDT_UTF8 = 47,
  PDT_VERSION = 48,
  PDT_ALARM_INFO = 49,
  PDT_BINARY_INFORMATION = 50,
  PDT_BITSET8 = 51,
  PDT_BITSET16 = 52,
  PDT_ENUM8 = 53,
  PDT_SCALING = 54,
  PDT_NE_VL = 60,
  PDT_NE_FL = 61,
  PDT_FUNCTION = 62,
  PDT_ESCAPE = 63,
}

int getPdtSize(PDT pdt) {
  switch(pdt) {
    case PDT.PDT_CONTROL: 
      return 10;
    case PDT.PDT_CHAR: 
      return 1;
    case PDT.PDT_UNSIGNED_CHAR: 
      return 1;
    case PDT.PDT_INT: 
      return 2;
    case PDT.PDT_UNSIGNED_INT: 
      return 2;
    case PDT.PDT_KNX_FLOAT: 
      return 2;
    case PDT.PDT_DATE: 
      return 3;
    case PDT.PDT_TIME: 
      return 3;
    case PDT.PDT_LONG: 
      return 4;
    case PDT.PDT_UNSIGNED_LONG: 
      return 4;
    case PDT.PDT_FLOAT: 
      return 4;
    case PDT.PDT_DOUBLE: 
      return 8;
    case PDT.PDT_CHAR_BLOCK: 
      return 10;
    case PDT.PDT_POLL_GROUP_SETTINGS: 
      return 3;
    case PDT.PDT_SHORT_CHAR_BLOCK: 
      return 5;
    case PDT.PDT_DATE_TIME: 
      return 8;
    case PDT.PDT_GENERIC_01: 
      return 1;
    case PDT.PDT_GENERIC_02: 
      return 2;
    case PDT.PDT_GENERIC_03: 
      return 3;
    case PDT.PDT_GENERIC_04: 
      return 4;
    case PDT.PDT_GENERIC_05: 
      return 5;
    case PDT.PDT_GENERIC_06: 
      return 6;
    case PDT.PDT_GENERIC_07: 
      return 7;
    case PDT.PDT_GENERIC_08: 
      return 8;
    case PDT.PDT_GENERIC_09: 
      return 9;
    case PDT.PDT_GENERIC_10: 
      return 10;
    case PDT.PDT_GENERIC_11: 
      return 11;
    case PDT.PDT_GENERIC_12: 
      return 12;
    case PDT.PDT_GENERIC_13: 
      return 13;
    case PDT.PDT_GENERIC_14: 
      return 14;
    case PDT.PDT_GENERIC_15: 
      return 15;
    case PDT.PDT_GENERIC_16: 
      return 16;
    case PDT.PDT_GENERIC_17: 
      return 17;
    case PDT.PDT_GENERIC_18: 
      return 18;
    case PDT.PDT_GENERIC_19: 
      return 19;
    case PDT.PDT_GENERIC_20: 
      return 20;
    case PDT.PDT_VERSION: 
      return 2;
    case PDT.PDT_ALARM_INFO: 
      return 6;
    case PDT.PDT_BINARY_INFORMATION: 
      return 1;
    case PDT.PDT_BITSET8: 
      return 1;
    case PDT.PDT_BITSET16: 
      return 2;
    case PDT.PDT_ENUM8: 
      return 1;
    case PDT.PDT_SCALING: 
      return 1;
    default:
      return 0;
  }
}

enum OT: ushort {
  OT_DEVICE = 0,
  OT_ADDRESS_TABLE = 1,
  OT_ASSOCIATION_TABLE = 2,
  OT_APPLICATION_PROGRAM = 3,
  OT_INTERACE_PROGRAM = 4,
  OT_EIBOBJECT_ASSOCIATATION_TABLE = 5,
  OT_ROUTER = 6,
  OT_LTE_ADDRESS_ROUTING_TABLE = 7,
  OT_CEMI_SERVER = 8,
  OT_GROUP_OBJECT_TABLE = 9,
  OT_POLLING_MASTER = 10,
  OT_KNXIP_PARAMETER = 11,
  OT_FILE_SERVER = 13,
  OT_SECURITY = 17,
  OT_RF_MEDIUM = 19,
  OT_INDOOR_BRIGHTNESS_SENSOR = 409,
  OT_INDOOR_LUMINANCE_SENSOR = 410,
  OT_LIGHT_SWITCHING_ACTUATOR_BASIC = 417,
  OT_DIMMING_ACTUATOR_BASIC = 418,
  OT_DIMMING_SENSOR_BASIC = 420,
  OT_SWITCHING_SENSOR_BASIC = 421,
  OT_SUNBLIND_ACTUATOR_BASIC = 800,
  OT_SUNBLIND_SENSOR_BASIC = 801,
}


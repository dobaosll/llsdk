/***
  This class serves to compose/parse FT1.2 frames
  in which ObjectServer message is incapsulated
  there is a two general types of FT12 frame
  1. Frames with fixed length
    - ack 0x05
      reset request
      reset ind
  2. Frames with variable length
      data frame
  ***/

module ft12;
import std.stdio;

enum FT12FrameType {
  ackFrame,
  resetInd,
  resetReq,
  dataFrame
}

enum FT12FrameParity {
  unknown,
  odd,
  even
}

struct FT12Frame {
  FT12FrameType type;
  bool isAckFrame() const { return this.type == FT12FrameType.ackFrame;}
  bool isResetInd() const { return this.type == FT12FrameType.resetInd;}
  bool isResetReq() const { return this.type == FT12FrameType.resetReq;}
  bool isDataFrame() const { return this.type == FT12FrameType.dataFrame;}

  FT12FrameParity parity;

  ubyte[] payload;
}

class FT12Helper {
  // consts
  private static ubyte[] ackFrame = [0xe5];
  private static ubyte[] resetInd = [0x10, 0xc0, 0xc0, 0x16];
  private static ubyte[] resetReq = [0x10, 0x40, 0x40, 0x16];
  private static ubyte dataFrameStartByte = 0x68;
  private static ubyte dataFrameEndByte = 0x16;

  private void delegate(FT12Frame) onReceived;

  this(void delegate(FT12Frame) onReceived) {
    this.onReceived = onReceived;
  }

  private bool _isBuffersEqual(ubyte[] a, ubyte[] b) {
    bool result = true;
    if (a.length != b.length) {
      return false;
    }
    auto len = a.length;
    for(auto i = 0; i < len; i++) {
      result = result && a[i] == b[i];
      if (!result) {
        break;
      }
    }

    return result;
  }
  // parse part
  private ubyte[] _buffer;
  void parse(ubyte[] chunk) {
    _buffer ~= chunk;
    auto processed = false;
    while(!processed) {
      while(_isBuffersEqual(_buffer[0..1], ackFrame)) {
        // ack frame received
        FT12Frame result;
        result.type = FT12FrameType.ackFrame;
        result.payload = ackFrame;
        onReceived(result);

        if (_buffer.length > 1) {
          _buffer = _buffer[1..$];
        } else {
          _buffer = [];
          processed = true;
          break;
        }
      }
      if (_buffer.length >= 4) {
        // reset ind or data frame
        if (_buffer[0] != dataFrameStartByte && _buffer[0]!= resetInd[0]) {
          // if unrecognazible first byte, pass it, process next
          _buffer = _buffer[1..$];
          continue;
        }
        ubyte[] fixed = _buffer[0..4];
        if (_isBuffersEqual(fixed, resetInd)) {
          // reset indication
          FT12Frame result;
          result.type = FT12FrameType.resetInd;
          result.payload = cast(ubyte[]) fixed;
          onReceived(result);

          if (_buffer.length > 4) {
            _buffer = _buffer[4..$];
          } else {
            _buffer = [];
            processed = true;
          }
          continue;
        } else if (fixed[0] == dataFrameStartByte && fixed[3] == dataFrameStartByte) {
          // data frame
          // 0x68 LL LL 0x60 CR <DATA> C 0x16
          // CR is 0x73 - odd frames, 0x53 - even(after reset req)
          // check if it equals to fixed[2]?(second LL)
          int dataLen = fixed[1];
          // whole frame length
          // 4 - header, 1 + dataLen(CR + data length) + checksum + 0x16;
          int expectedLen = 4 + dataLen + 1 + 1;

          // if whole data frame is here, then process it
          // if not, then wait for next chunk
          if (_buffer.length >= expectedLen) {
            // whole data frame should be here
            auto dataFrame = _buffer[0..expectedLen];

            // if end byte is right
            if (dataFrame[expectedLen-1] == dataFrameEndByte) {
              int controlByte = _buffer[4];
              ubyte[] message = _buffer[5..expectedLen - 2];
              int checkSum = _buffer[expectedLen - 2];
              // compare checksum received and expected
              auto expectedCheckSum = calculateCheckSum(cast(ubyte[])[controlByte] ~ message);
              
              //////////////////////////////////////
              // delete data from buffer
              // no matter, was it correct or not
              if (_buffer.length > expectedLen) {
                _buffer = _buffer[expectedLen..$];
              } else {
                _buffer = [];
                processed = true;
              }
              //////////////////////////////////////
              // if checksum is right, then emit frame to delegate
              if (checkSum == expectedCheckSum) {
                FT12Frame result;
                result.type = FT12FrameType.dataFrame;
                result.payload = message;
                // call delegate
                onReceived(result);
              }
            } else {
              // last expected byte is not 0x68
              if (_buffer.length > expectedLen) {
                _buffer = _buffer[expectedLen..$];
              } else {
                _buffer = [];
                processed = true;
              }
            }
          } else {
            // wait for the next chunk
            processed = true;
          }
          continue;
        }
        //
        if (_buffer.length > 1) {
          // unknown first byte, proceed next
          _buffer = _buffer[1..$];
          continue;
        } else {
          _buffer = [];
        }
      } else if (_buffer.length > 0) {
        // if data or reset, but not completed
        if (_buffer[0] == dataFrameStartByte || _buffer[0] == resetInd[0]) {
          // wait for another chunk
          processed = true;
        } else {
          // unknown first byte, proceed next
          if (_buffer.length > 1) {
            _buffer = _buffer[1..$];
          } else {
            _buffer = [];
          }
        }
      }
      if (_buffer.length == 0) {
        //buffer now is empty, parsed completely
        processed = true;
      }
    }
  }
  static ubyte calculateCheckSum(ubyte[] data) {
    ubyte sum = 0;
    auto l = data.length;
    for (auto i = 0; i < l; i+= 1) {
      sum += data[i];
    }

    ubyte result = sum % 256;
    return result;
  }
  static ubyte[] compose(FT12Frame frame) {
    ubyte[] result = [];
    if (frame.isAckFrame()) {
      return cast(ubyte[]) ackFrame;
    }
    if (frame.isResetReq()) {
      return cast(ubyte[]) resetReq;
    }

    // data frame: 4bytes [fixed], 1[control byte], LL(data), + checksum + 0x16;
    auto payloadLen = frame.payload.length;
    auto expectedLen = 4 + 1 + payloadLen + 1 + 1;
    result.length = expectedLen;
    // header
    result[0] = cast(ubyte) dataFrameStartByte;
    result[1] = cast(ubyte) (frame.payload.length + 1);
    result[2] = cast(ubyte) (frame.payload.length + 1);
    result[3] = cast(ubyte) dataFrameStartByte;
    // control byte
    if (frame.parity == FT12FrameParity.unknown) {
      throw new Exception("Frame parity is unknown");
    }
    if (frame.parity == FT12FrameParity.odd) {
      result[4] = 0x73;
    }
    if (frame.parity == FT12FrameParity.even) {
      result[4] = 0x53;
    }
    // insert message
    result[5..5 + payloadLen] = frame.payload[0..$];
    // checksum
    result[5 + payloadLen ] = calculateCheckSum(result[4]~frame.payload);
    // end byte
    result[expectedLen - 1] = dataFrameEndByte;
    return result;
  }
}

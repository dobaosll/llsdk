module errors;

enum Errors {
  unknown = new Exception("ERR_UNKNOWN"),
  interrupted = new Exception("ERR_INTERRUPTED"),
  timeout = new Exception("ERR_TIMEOUT"),
  no_method_field = new Exception("ERR_NO_METHOD_FIELD"),
  no_payload_field = new Exception("ERR_NO_PAYLOAD_FIELD"),
  unknown_method = new Exception("ERR_UNKNOWN_METHOD"),
  wrong_payload_type = new Exception("ERR_WRONG_PAYLOAD_TYPE"),
  wrong_base64_string = new Exception("ERR_WRONG_BASE64_STRING")
}

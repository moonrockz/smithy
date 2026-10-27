///|
/// An exact integer JSON-RPC error code, without a machine-integer bound.
pub struct ErrorCode {
  priv number : @smithy.NodeNumber
} derive(Eq, Debug)

///|
pub fn ErrorCode::from_number(number : @smithy.NodeNumber) -> ErrorCode? {
  if number.is_integer() {
    Some({ number, })
  } else {
    None
  }
}

///|
pub fn ErrorCode::to_string(self : ErrorCode) -> String {
  self.number.to_string()
}

///|
pub fn ErrorCode::number(self : ErrorCode) -> @smithy.NodeNumber {
  self.number
}

///|
fn error_code(text : String) -> ErrorCode {
  ErrorCode::from_number(@smithy.NodeNumber::parse(text).unwrap()).unwrap()
}

///|
fn ErrorCode::is_reserved(self : ErrorCode) -> Bool {
  self.number.numeric_compare(@smithy.NodeNumber::parse("-32768").unwrap()) >= 0 &&
  self.number.numeric_compare(@smithy.NodeNumber::parse("-32000").unwrap()) <= 0
}

///|
fn ErrorCode::is_protocol(self : ErrorCode) -> Bool {
  ["-32700", "-32600", "-32601", "-32602", "-32603"]
  .iter()
  .any(s => self == error_code(s))
}

///|
fn ErrorCode::is_server(self : ErrorCode) -> Bool {
  self.number.numeric_compare(@smithy.NodeNumber::parse("-32099").unwrap()) >= 0 &&
  self.number.numeric_compare(@smithy.NodeNumber::parse("-32000").unwrap()) <= 0
}

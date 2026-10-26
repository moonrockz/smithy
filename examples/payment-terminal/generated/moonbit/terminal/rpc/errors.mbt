///|
/// A JSON-RPC error. A handler raises it to answer with this code, message
/// and data. `Peer::request` raises it for an error response and for a call
/// that the session refuses before it is sent.
pub(all) suberror RpcError {
  RpcError(code~ : Int32, message~ : String, data~ : Json?)
} derive(Debug)

///|
pub impl Show for RpcError with fn output(self, logger) {
  let RpcError(code~, message~, ..) = self
  logger.write_string("error \{code}: \{message}")
}

///|
/// A failure of the connection: the remote peer closed it, or a frame on the
/// wire is not valid.
pub(all) suberror TransportError {
  TransportError(String)
} derive(Debug)

///|
pub impl Show for TransportError with fn output(self, logger) {
  let TransportError(message) = self
  logger.write_string(message)
}

///|
/// Invalid JSON was received.
pub let parse_error_code : Int32 = -32700

///|
/// The JSON is not a valid request object.
pub let invalid_request_code : Int32 = -32600

///|
/// The method does not exist.
pub let method_not_found_code : Int32 = -32601

///|
/// The params are not valid.
pub let invalid_params_code : Int32 = -32602

///|
/// An internal error of the handler.
pub let internal_error_code : Int32 = -32603

///|
/// The default code of a cancelled call.
pub let request_cancelled_code : Int32 = -32800

///|
/// The ID of a JSON-RPC request: an integer or a string. An integer keeps its
/// exact text, so that an ID beyond the Int64 range is echoed unchanged.
pub(all) enum RequestId {
  Number(String)
  Text(String)
} derive(Eq, Hash, Debug)

///|
pub impl Show for RequestId with fn output(self, logger) {
  match self {
    Number(text) => logger.write_string(text)
    Text(text) => logger.write_string(write_json(Json::string(text)))
  }
}

///|
pub fn RequestId::to_json(self : RequestId) -> Json {
  match self {
    Number(text) => Json::number(number_double(text), repr=text)
    Text(text) => Json::string(text)
  }
}

///|
/// Gives the ID for a JSON string or a JSON integer, and None for any other
/// value.
pub fn RequestId::from_json(json : Json) -> RequestId? {
  match json {
    String(text) => Some(Text(text))
    Number(_, ..) =>
      match number_text(json) {
        Some(text) if is_integer_text(text) => Some(Number(text))
        _ => None
      }
    _ => None
  }
}

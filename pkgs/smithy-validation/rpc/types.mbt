///|
pub(all) enum ProtocolVersion {
  V1_0
  V2_0
} derive(Eq, Hash, Debug)

///|
pub fn ProtocolVersion::parse(text : String) -> ProtocolVersion? {
  match text {
    "1.0" => Some(V1_0)
    "2.0" => Some(V2_0)
    _ => None
  }
}

///|
pub fn ProtocolVersion::to_string(self : ProtocolVersion) -> String {
  match self {
    V1_0 => "1.0"
    V2_0 => "2.0"
  }
}

///|
pub struct MethodName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub fn MethodName::parse(text : String) -> MethodName? {
  if text.is_empty() || text.has_prefix("rpc.") {
    None
  } else {
    Some({ text, })
  }
}

///|
pub fn MethodName::to_string(self : MethodName) -> String {
  self.text
}

///|
pub(all) enum RequestId {
  Absent
  Present(@smithy.NodeValue)
} derive(Eq, Debug)

///|
pub(all) enum MessageKind {
  Call
  Notification
} derive(Eq, Debug)

///|
pub(all) enum MethodKind {
  RequestOnly
  NotificationOnly
  RequestOrNotification
} derive(Eq, Debug)

///|
pub(all) enum ParameterMode {
  Named
  Positional
  Either
} derive(Eq, Debug)

///|
pub(all) enum ResultSelection {
  OutputStructure(@smithy.ShapeId)
  OutputMember(@smithy.ShapeId)
  NullResult
} derive(Eq, Debug)

///|
pub(all) suberror PreparationError {
  InvalidContract(@smithy.ShapeId, String)
} derive(Debug)

///|
pub(all) enum FindingCode {
  InvalidJson
  DuplicateJsonKey
  JsonInputLimit
  InvalidEnvelope
  InvalidVersion
  InvalidId
  DiscouragedId
  UnknownMethod
  InvalidParams
  NotificationExpected
  RequestExpected
  UnsupportedMessage
  MissingContext
  LimitedScope
  InvalidContext
  IdMismatch
  UnexpectedResponse
  InvalidError
  UnknownError
  AmbiguousId
  DuplicateResponse
  MissingResponse
  Value(@validation.FindingCode)
} derive(Eq, Debug)

///|
pub fn FindingCode::to_string(self : FindingCode) -> String {
  match self {
    InvalidJson => "InvalidJson"
    DuplicateJsonKey => "DuplicateJsonKey"
    JsonInputLimit => "JsonInputLimit"
    InvalidEnvelope => "InvalidEnvelope"
    InvalidVersion => "InvalidVersion"
    InvalidId => "InvalidId"
    DiscouragedId => "DiscouragedId"
    UnknownMethod => "UnknownMethod"
    InvalidParams => "InvalidParams"
    NotificationExpected => "NotificationExpected"
    RequestExpected => "RequestExpected"
    UnsupportedMessage => "UnsupportedMessage"
    MissingContext => "MissingContext"
    LimitedScope => "LimitedScope"
    InvalidContext => "InvalidContext"
    IdMismatch => "IdMismatch"
    UnexpectedResponse => "UnexpectedResponse"
    InvalidError => "InvalidError"
    UnknownError => "UnknownError"
    AmbiguousId => "AmbiguousId"
    DuplicateResponse => "DuplicateResponse"
    MissingResponse => "MissingResponse"
    Value(code) => code.to_string()
  }
}

///|
pub(all) struct Finding {
  code : FindingCode
  severity : @validation.FindingSeverity
  path : @validation.InstancePath
  shape : @smithy.ShapeId
  operation : @smithy.ShapeId?
  offset : Int32?
  message : String
} derive(Eq, Debug)

///|
pub(all) struct RequestResult {
  findings : Array[Finding]
  complete : Bool
  kind : MessageKind?
  id : RequestId
  operation : @smithy.ShapeId?
} derive(Eq, Debug)

///|
pub fn RequestResult::is_valid(self : RequestResult) -> Bool {
  self.complete &&
  !self.findings.iter().any(f => f.severity == @validation.Error)
}

///|
pub impl @json.ToJson for Finding with fn to_json(self) {
  Json::object({
    "code": Json::string(self.code.to_string()),
    "severity": Json::string(
      if self.severity == @validation.Error {
        "error"
      } else {
        "advisory"
      },
    ),
    "path": @json.to_json(self.path),
    "pointer": Json::string(self.path.pointer()),
    "shape": Json::string(self.shape.to_string()),
    "operation": self.operation
    .map(id => Json::string(id.to_string()))
    .unwrap_or(Json::null()),
    "offset": self.offset
    .map(n => Json::number(n.to_double()))
    .unwrap_or(Json::null()),
    "message": Json::string(self.message),
  })
}

///|
pub impl @json.ToJson for RequestResult with fn to_json(self) {
  Json::object({
    "valid": Json::boolean(self.is_valid()),
    "complete": Json::boolean(self.complete),
    "findings": Json::array(self.findings.map(f => @json.to_json(f))),
    "kind": self.kind
    .map(k => Json::string(if k == Call { "call" } else { "notification" }))
    .unwrap_or(Json::null()),
    "operation": self.operation
    .map(id => Json::string(id.to_string()))
    .unwrap_or(Json::null()),
    "idPresent": Json::boolean(self.id is Present(_)),
    "id": match self.id {
      Absent => Json::null()
      Present(value) => @json.to_json(value)
    },
  })
}

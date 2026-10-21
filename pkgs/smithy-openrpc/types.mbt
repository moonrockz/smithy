///|
pub struct ServiceId(@smithy.ShapeId) derive(Eq, Debug, Hash)

///|
pub fn ServiceId::parse(text : String) -> ServiceId? {
  @smithy.ShapeId::parse(text).bind(id => {
    if id.root() == id {
      Some(ServiceId(id))
    } else {
      None
    }
  })
}

///|
pub fn ServiceId::shape_id(self : ServiceId) -> @smithy.ShapeId {
  self.0
}

///|
pub(all) enum OpenRpcVersion {
  V1_3_2
} derive(Eq, Debug)

///|
pub fn OpenRpcVersion::parse(text : String) -> OpenRpcVersion? {
  if text == "1.3.2" {
    Some(V1_3_2)
  } else {
    None
  }
}

///|
pub fn OpenRpcVersion::to_string(self : OpenRpcVersion) -> String {
  match self {
    V1_3_2 => "1.3.2"
  }
}

///|
pub(all) enum ExtensionPolicy {
  Preserve
  Omit
  Fail
} derive(Eq, Debug)

///|
pub(all) enum WarningCode {
  OmittedProtocolSemantics
  OmittedErrorData
  OmittedExample
  SchemaLimitation
} derive(Eq, Debug)

///|
pub(all) struct ConversionWarning {
  code : WarningCode
  shape : @smithy.ShapeId
  message : String
} derive(Eq, Debug)

///|
pub(all) struct Conversion {
  document : Json
  warnings : Array[ConversionWarning]
} derive(Debug)

///|
pub(all) suberror OpenRpcError {
  InvalidConfiguration(@smithy.ShapeId, String)
  InvalidContract(@smithy.ShapeId, String)
  SchemaConversion(@smithy.ShapeId, String)
  UnsupportedMapping(@smithy.ShapeId, String)
} derive(Debug)

///|
pub fn OpenRpcError::shape(self : OpenRpcError) -> @smithy.ShapeId {
  match self {
    InvalidConfiguration(id, _)
    | InvalidContract(id, _)
    | SchemaConversion(id, _)
    | UnsupportedMapping(id, _) => id
  }
}

///|
pub fn OpenRpcError::message(self : OpenRpcError) -> String {
  let text = match self {
    InvalidConfiguration(_, text)
    | InvalidContract(_, text)
    | SchemaConversion(_, text)
    | UnsupportedMapping(_, text) => text
  }
  self.shape().to_string() + ": " + text
}

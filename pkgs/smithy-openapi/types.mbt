///|
/// A root shape ID naming the service selected for conversion.
pub struct ServiceId(@smithy.ShapeId) derive(Eq, Debug, Hash)

///|
pub fn ServiceId::parse(text : String) -> ServiceId? {
  guard @smithy.ShapeId::parse(text) is Some(id) && id.root() == id else {
    return None
  }
  Some(ServiceId(id))
}

///|
pub fn ServiceId::shape_id(self : ServiceId) -> @smithy.ShapeId {
  self.0
}

///|
pub fn ServiceId::to_string(self : ServiceId) -> String {
  self.0.to_string()
}

///|
/// The trait ID of the selected serialization protocol.
pub struct ProtocolId(@smithy.ShapeId) derive(Eq, Debug, Hash)

///|
pub fn ProtocolId::parse(text : String) -> ProtocolId? {
  guard @smithy.ShapeId::parse(text) is Some(id) && id.root() == id else {
    return None
  }
  Some(ProtocolId(id))
}

///|
pub fn ProtocolId::shape_id(self : ProtocolId) -> @smithy.ShapeId {
  self.0
}

///|
pub fn ProtocolId::to_string(self : ProtocolId) -> String {
  self.0.to_string()
}

///|
pub(all) enum OpenApiVersion {
  V3_0_2
  V3_1_0
} derive(Eq, Debug)

///|
pub fn OpenApiVersion::parse(text : String) -> OpenApiVersion? {
  match text {
    "3.0.2" => Some(V3_0_2)
    "3.1.0" => Some(V3_1_0)
    _ => None
  }
}

///|
pub fn OpenApiVersion::to_string(self : OpenApiVersion) -> String {
  match self {
    V3_0_2 => "3.0.2"
    V3_1_0 => "3.1.0"
  }
}

///|
pub(all) enum PrefixHeadersPolicy {
  Fail
  Warn
} derive(Eq, Debug)

///|
/// Stable conversion warning classifications. Warnings retain the affected
/// semantic shape instead of parsing a rendered diagnostic later.
pub(all) enum WarningCode {
  OmittedPrefixHeaders
  OmittedUnsupportedTrait
  OmittedHttpMethod
  OmittedAuthScheme
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
pub fn OpenApiError::message(self : OpenApiError) -> String {
  match self {
    InvalidConfiguration(message) | SchemaConversion(message) => message
    MissingService(id) => "Service `" + id.to_string() + "` was not found"
    InvalidService(id) => "Shape `" + id.to_string() + "` is not a service"
    ProtocolResolution(id, message) =>
      "Service `" + id.to_string() + "`: " + message
    UnsupportedProtocol(id) => "Unsupported protocol `" + id.to_string() + "`"
    UnsupportedTrait(shape, trait_id) =>
      "Unsupported trait `" +
      trait_id.to_string() +
      "` on `" +
      shape.to_string() +
      "`"
    PrefixHeaders(shape) =>
      "Unsupported httpPrefixHeaders binding on `" +
      shape.to_string() +
      "`; set onHttpPrefixHeaders to WARN to omit it"
    GreedyLabel(shape) =>
      "Greedy URI label is forbidden on `" + shape.to_string() + "`"
  }
}

///|
pub(all) suberror OpenApiError {
  InvalidConfiguration(String)
  MissingService(ServiceId)
  InvalidService(ServiceId)
  ProtocolResolution(ServiceId, String)
  UnsupportedProtocol(ProtocolId)
  UnsupportedTrait(@smithy.ShapeId, @smithy.ShapeId)
  PrefixHeaders(@smithy.ShapeId)
  GreedyLabel(@smithy.ShapeId)
  SchemaConversion(String)
} derive(Debug)

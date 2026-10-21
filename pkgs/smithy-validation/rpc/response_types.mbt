///|
/// Context is supplied by the caller, never inferred from response fields.
pub(all) enum ResponseContext {
  EnvelopeOnly
  Method(MethodName)
  Operation(@smithy.ShapeId)
  OriginalRequest(String)
} derive(Eq, Debug)

///|
/// JSON-RPC 1.0 defines no code/message/data schema. Opt in explicitly to reuse
/// that application mapping; otherwise legacy errors remain opaque JSON values.
pub(all) enum LegacyErrorMode {
  Opaque
  CodeMessageData
} derive(Eq, Debug)

///|
pub(all) enum ResponseKind {
  Success
  ProtocolError
  ApplicationError
  LegacyError
} derive(Eq, Debug)

///|
pub(all) enum ResponseScope {
  Envelope
  MethodPayload
  RequestContext
} derive(Eq, Debug)

///|
pub(all) struct ResponseResult {
  findings : Array[Finding]
  complete : Bool
  scope : ResponseScope
  kind : ResponseKind?
  id : RequestId
  operation : @smithy.ShapeId?
} derive(Eq, Debug)

///|
pub fn ResponseResult::is_valid(self : ResponseResult) -> Bool {
  self.complete &&
  !self.findings.iter().any(f => f.severity == @validation.Error)
}

///|
pub impl @json.ToJson for ResponseResult with fn to_json(self) {
  Json::object({
    "valid": Json::boolean(self.is_valid()),
    "complete": Json::boolean(self.complete),
    "scope": Json::string(
      match self.scope {
        Envelope => "envelope"
        MethodPayload => "methodPayload"
        RequestContext => "requestContext"
      },
    ),
    "kind": self.kind
    .map(k => {
      Json::string(
        match k {
          Success => "success"
          ProtocolError => "protocolError"
          ApplicationError => "applicationError"
          LegacyError => "legacyError"
        },
      )
    })
    .unwrap_or(Json::null()),
    "operation": self.operation
    .map(id => Json::string(id.to_string()))
    .unwrap_or(Json::null()),
    "idPresent": Json::boolean(self.id is Present(_)),
    "id": match self.id {
      Absent => Json::null()
      Present(value) => @json.to_json(value)
    },
    "findings": Json::array(self.findings.map(f => @json.to_json(f))),
  })
}

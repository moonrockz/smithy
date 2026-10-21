///|
/// OriginalBatch declares the response to one complete supplied request batch.
/// BatchMethod and BatchOperation check payloads without establishing correlation.
pub(all) enum BatchResponseContext {
  BatchEnvelopeOnly
  BatchMethod(MethodName)
  BatchOperation(@smithy.ShapeId)
  OriginalBatch(String)
} derive(Eq, Debug)

///|
pub(all) struct RequestBatchEntry {
  index : Int32
  result : RequestResult
} derive(Eq, Debug)

///|
pub(all) struct RequestBatchResult {
  findings : Array[Finding]
  complete : Bool
  entries : Array[RequestBatchEntry]
} derive(Eq, Debug)

///|
pub fn RequestBatchResult::is_valid(self : RequestBatchResult) -> Bool {
  self.complete &&
  !self.findings.iter().any(f => f.severity == @validation.Error)
}

///|
pub(all) struct ResponseBatchEntry {
  /// None for the single error object returned for an invalid whole batch.
  index : Int32?
  request_index : Int32?
  result : ResponseResult
} derive(Eq, Debug)

///|
pub(all) struct ResponseBatchResult {
  findings : Array[Finding]
  complete : Bool
  scope : ResponseScope
  entries : Array[ResponseBatchEntry]
} derive(Eq, Debug)

///|
pub fn ResponseBatchResult::is_valid(self : ResponseBatchResult) -> Bool {
  self.complete &&
  !self.findings.iter().any(f => f.severity == @validation.Error)
}

///|
pub impl @json.ToJson for RequestBatchResult with fn to_json(self) {
  Json::object({
    "valid": Json::boolean(self.is_valid()),
    "complete": Json::boolean(self.complete),
    "findings": Json::array(self.findings.map(f => @json.to_json(f))),
    "entries": Json::array(
      self.entries.map(e => {
        Json::object({
          "index": Json::number(e.index.to_double()),
          "result": @json.to_json(e.result),
        })
      }),
    ),
  })
}

///|
pub impl @json.ToJson for ResponseBatchResult with fn to_json(self) {
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
    "findings": Json::array(self.findings.map(f => @json.to_json(f))),
    "entries": Json::array(
      self.entries.map(e => {
        Json::object({
          "index": e.index
          .map(i => Json::number(i.to_double()))
          .unwrap_or(Json::null()),
          "requestIndex": e.request_index
          .map(i => Json::number(i.to_double()))
          .unwrap_or(Json::null()),
          "result": @json.to_json(e.result),
        })
      }),
    ),
  })
}

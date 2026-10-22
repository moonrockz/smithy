///|
/// Numeric components are normalized by NodeNumber. Never expand an exponent or
/// use a floating-point approximation as a correlation key.
priv enum BatchId {
  NullId
  StringId(String)
  NumberId(BigInt, BigInt)
} derive(Eq, Hash)

///|
fn batch_id(id : RequestId) -> BatchId? {
  match id {
    Present(@smithy.Null) => Some(NullId)
    Present(@smithy.String(value)) => Some(StringId(value))
    Present(@smithy.Number(value)) =>
      Some(
        NumberId(
          value.coefficient,
          if value.coefficient == BigInt::from_int(0) {
            BigInt::from_int(0)
          } else {
            value.exponent
          },
        ),
      )
    _ => None
  }
}

///|
fn invalid_request_envelope(
  version : ProtocolVersion,
  value : Json,
  request : RequestResult,
) -> Bool {
  let invalid_params = match value {
    Object(fields) =>
      match fields.get("params") {
        Some(Array(_)) => false
        Some(Object(_)) | None => version == V1_0
        _ => true
      }
    _ => false
  }
  invalid_params ||
  request.findings
  .iter()
  .any(f => {
    f.code == InvalidEnvelope ||
    f.code == InvalidVersion ||
    f.code == InvalidId ||
    f.code == UnsupportedMessage
  })
}

///|
/// The ID that the reply to one request batch element carries, and whether the
/// element is invalid. An invalid element without a usable ID is answered with
/// a null ID. A valid notification needs no reply, so it gives None.
fn batch_reply_id(
  version : ProtocolVersion,
  value : Json,
  request : RequestResult,
) -> (RequestId, Bool)? {
  let invalid = invalid_request_envelope(version, value, request)
  if !invalid && request.kind == Some(Notification) {
    return None
  }
  let id = if invalid &&
    (
      request.id == Absent ||
      request.findings.iter().any(f => f.code == InvalidId)
    ) {
    Present(@smithy.Null)
  } else {
    request.id
  }
  Some((id, invalid))
}

///|
priv struct BatchReport {
  service : @smithy.ShapeId
  limit : Int32
  findings : Array[Finding]
  mut complete : Bool
}

///|
fn PreparedService::batch_report(self : PreparedService) -> BatchReport {
  {
    service: self.service,
    limit: self.finding_limit,
    findings: [],
    complete: true,
  }
}

///|
fn BatchReport::add(self : BatchReport, finding : Finding) -> Finding? {
  if !self.complete {
    return None
  }
  if self.findings.length() >= self.limit {
    let stopped = {
      ..finding,
      code: Value(@validation.LimitExceeded),
      severity: @validation.Error,
      message: "I reached the batch finding limit before completing every check.",
    }
    self.findings[self.limit - 1] = stopped
    self.complete = false
    Some(stopped)
  } else {
    self.findings.push(finding)
    Some(finding)
  }
}

///|
fn BatchReport::emit(
  self : BatchReport,
  code : FindingCode,
  path : @validation.InstancePath,
  message : String,
  severity~ : @validation.FindingSeverity = @validation.Error,
) -> Unit {
  self.add({
    code,
    path,
    message,
    severity,
    shape: self.service,
    operation: None,
    offset: None,
  })
  |> ignore
}

///|
fn BatchReport::collect(
  self : BatchReport,
  findings : Array[Finding],
  base : @validation.InstancePath,
) -> Array[Finding] {
  let collected = []
  for finding in findings {
    if self.add({ ..finding, path: base.append(finding.path), }) is Some(added) {
      collected.push(added)
    }
    if !self.complete {
      break
    }
  }
  collected
}

///|
fn batch_path(index : Int32?) -> @validation.InstancePath {
  let root = @validation.InstancePath::root()
  index.map(i => root.index(i) catch { _ => root }).unwrap_or(root)
}

///|
/// Validate a nonempty 2.0 request array. Findings retain original indices.
pub fn PreparedService::validate_request_batch(
  self : PreparedService,
  text : String,
) -> RequestBatchResult {
  if self.version == V1_0 {
    return self.validate_request_batch_json(Json::null())
  }
  let value = @validation.parse_json_value(text) catch {
    _ => {
      let failed = self.validate_request(text)
      return { findings: failed.findings, complete: false, entries: [], }
    }
  }
  self.validate_request_batch_json(value)
}

///|
/// In-memory numbers retain only the precision supplied by their caller.
pub fn PreparedService::validate_request_batch_json(
  self : PreparedService,
  value : Json,
) -> RequestBatchResult {
  let report = self.batch_report()
  let root = @validation.InstancePath::root()
  if self.version == V1_0 {
    report.emit(
      UnsupportedMessage,
      root,
      "I cannot validate a version 1.0 batch; multiple HTTP messages are a separate framing concern.",
    )
    return {
      findings: report.findings,
      complete: report.complete,
      entries: [],
    }
  }
  let document = self.document.validate_json(value)
  if !document.is_valid() {
    return {
      findings: value_findings(document, None),
      complete: document.complete,
      entries: [],
    }
  }
  guard value is Array(values) && !values.is_empty() else {
    report.emit(
      InvalidEnvelope,
      root,
      "I expected a nonempty JSON-RPC 2.0 request batch array.",
    )
    return {
      findings: report.findings,
      complete: report.complete,
      entries: [],
    }
  }
  let entries = []
  let seen : Set[BatchId] = Set([])
  for index, value in values {
    let result = self.validate_json(value)
    let base = batch_path(Some(index))
    let findings = report.collect(result.findings, base)
    if report.complete &&
      !invalid_request_envelope(self.version, value, result) &&
      result.kind == Some(Call) &&
      batch_id(result.id) is Some(id) {
      if seen.contains(id) {
        findings.append(
          report.collect(
            [
              {
                code: AmbiguousId,
                path: root.field("id") catch {
                  _ => root
                },
                shape: self.service,
                operation: None,
                offset: None,
                message: "I found a repeated call ID; these requests cannot be correlated uniquely.",
                severity: @validation.Advisory,
              },
            ],
            base,
          ),
        )
      }
      seen.add(id)
    }
    report.complete = report.complete && result.complete
    entries.push({
      index,
      result: {
        ..result,
        findings,
        complete: result.complete && report.complete,
      },
    })
    if !report.complete {
      break
    }
  }
  { findings: report.findings, complete: report.complete, entries, }
}

///|
priv struct BatchCall {
  index : Int32
  value : Json
  request : RequestResult
}

///|
priv struct BatchCandidates {
  calls : Array[BatchCall]
  invalid : Array[BatchCall]
  mut next_call : Int32
  mut next_invalid : Int32
}

///|
fn BatchCandidates::take(
  self : BatchCandidates,
  invalid_reply : Bool,
) -> BatchCall? {
  if (invalid_reply && !self.invalid.is_empty()) || self.calls.is_empty() {
    if self.next_invalid >= self.invalid.length() {
      return None
    }
    let call = self.invalid[self.next_invalid]
    self.next_invalid += 1
    Some(call)
  } else {
    if self.next_call >= self.calls.length() {
      return None
    }
    let call = self.calls[self.next_call]
    self.next_call += 1
    Some(call)
  }
}

///|
/// None is absence of a response, never a JSON null or an empty array.
/// OriginalBatch supplies the complete batch association to check.
pub fn PreparedService::validate_response_batch(
  self : PreparedService,
  text : String?,
  context~ : BatchResponseContext? = None,
) -> ResponseBatchResult {
  let value = match text {
    None => None
    Some(text) =>
      Some(@validation.parse_json_value(text)) catch {
        _ => {
          if self.version == V1_0 {
            return self.validate_response_batch_json(None, context~)
          }
          let failed = self.validate_request(text)
          return {
            findings: failed.findings,
            complete: false,
            scope: Envelope,
            entries: [],
          }
        }
      }
  }
  self.validate_response_batch_json(value, context~)
}

///|
pub fn PreparedService::validate_response_batch_json(
  self : PreparedService,
  value : Json?,
  context~ : BatchResponseContext? = None,
) -> ResponseBatchResult {
  let report = self.batch_report()
  let root = @validation.InstancePath::root()
  let entries : Array[ResponseBatchEntry] = []
  let mut scope = Envelope
  fn finish() -> ResponseBatchResult {
    { findings: report.findings, complete: report.complete, scope, entries, }
  }
  if self.version == V1_0 {
    report.emit(
      UnsupportedMessage,
      root,
      "I cannot validate a version 1.0 response batch; multiple HTTP messages are a separate framing concern.",
    )
    return finish()
  }
  if value is Some(value) {
    let document = self.document.validate_json(value)
    if !document.is_valid() {
      report.collect(value_findings(document, None), root) |> ignore
      report.complete = report.complete && document.complete
      return finish()
    }
  }
  let mut selected : ResponseContext? = None
  let mut original_values : Array[Json]? = None
  let calls : Map[BatchId, BatchCandidates] = Map([])
  let original_calls : Array[BatchCall] = []
  let mut whole_error : ErrorCode? = None
  match context {
    None =>
      report.emit(
        MissingContext,
        root,
        "I expected explicit batch response context.",
      )
    Some(BatchEnvelopeOnly) => selected = Some(ResponseContext::EnvelopeOnly)
    Some(BatchMethod(name)) => {
      scope = MethodPayload
      selected = Some(ResponseContext::Method(name))
    }
    Some(BatchOperation(id)) => {
      scope = MethodPayload
      selected = Some(ResponseContext::Operation(id))
    }
    Some(OriginalBatch(text)) => {
      scope = RequestContext
      let parsed = Some(@validation.parse_json_value(text)) catch { _ => None }
      match parsed {
        None => {
          let failed = self.validate_request(text)
          if failed.findings.iter().any(f => f.code == InvalidJson) {
            whole_error = Some(error_code("-32700"))
          } else {
            report.emit(
              InvalidContext,
              root,
              "I could not completely check the original batch under deterministic input and resource policies.",
            )
            report.complete = false
            return finish()
          }
        }
        Some(parsed) => {
          let checked = self.validate_request_batch_json(parsed)
          if !checked.complete {
            report.emit(
              InvalidContext,
              root,
              "I could not completely validate the original batch under the resource limits.",
            )
            report.complete = false
            return finish()
          }
          match parsed {
            Array(values) if !values.is_empty() => {
              original_values = Some(values)
              for entry in checked.entries {
                let request = entry.result
                guard batch_reply_id(self.version, values[entry.index], request)
                  is Some((id, invalid)) else {
                  continue
                }
                if batch_id(id) is Some(key) {
                  let group = calls.get_or_default(key, {
                    calls: [],
                    invalid: [],
                    next_call: 0,
                    next_invalid: 0,
                  })
                  if !invalid && !group.calls.is_empty() {
                    report.emit(
                      AmbiguousId,
                      root,
                      "I cannot associate responses uniquely with repeated original call IDs.",
                    )
                  }
                  let call = {
                    index: entry.index,
                    value: values[entry.index],
                    request,
                  }
                  (if invalid { group.invalid } else { group.calls }).push(call)
                  original_calls.push(call)
                  calls[key] = group
                }
                if !report.complete {
                  return finish()
                }
              }
              if report.findings.iter().any(f => f.code == AmbiguousId) {
                return finish()
              }
            }
            _ => whole_error = Some(error_code("-32600"))
          }
        }
      }
    }
  }
  if whole_error is Some(code) {
    guard value is Some(value) && value is Object(_) else {
      report.emit(
        InvalidEnvelope,
        root,
        "I expected one protocol error object for an invalid whole batch.",
      )
      return finish()
    }
    let result = self.validate_response_checked(value, InvalidBatch(code))
    let findings = report.collect(result.findings, root)
    report.complete = report.complete && result.complete
    entries.push({
      index: None,
      request_index: None,
      result: {
        ..result,
        findings,
        complete: result.complete && report.complete,
      },
    })
    return finish()
  }
  let used : Set[Int32] = Set([])
  let responses = match value {
    None => {
      if original_values is None {
        report.emit(
          MissingContext,
          root,
          "I need the original batch to establish whether no response is permitted.",
        )
      }
      []
    }
    Some(Array(values)) if !values.is_empty() => values
    _ => {
      report.emit(
        InvalidEnvelope,
        root,
        "I expected a nonempty response batch array, or absence for an all-notification batch.",
      )
      return finish()
    }
  }
  for index, response in responses {
    let base = batch_path(Some(index))
    let mut request_index = None
    let mut checked_context = Selected(selected)
    if original_values is Some(_) {
      let id = match response {
        Object(fields) =>
          fields
          .get("id")
          .bind(v => {
            Some(Present(@smithy.NodeValue::from_json(v))) catch {
              _ => None
            }
          })
          .bind(batch_id)
        _ => None
      }
      let group = id.bind(key => calls.get(key))
      // Null-ID invalid-element errors form a multiset. Distinguish them from
      // a valid explicit-null call by the required invalid-request error code.
      let invalid_reply = match response {
        Object(fields) =>
          match fields.get("error") {
            Some(Object(error)) =>
              match error.get("code") {
                Some(Number(n, repr~)) =>
                  @smithy.NodeNumber::parse(repr.unwrap_or(n.to_string())).bind(
                    ErrorCode::from_number,
                  ) ==
                  Some(error_code("-32600"))
                _ => false
              }
            _ => false
          }
        _ => false
      }
      let candidate = group.bind(g => g.take(invalid_reply))
      if candidate is Some(call) {
        request_index = Some(call.index)
        used.add(call.index)
        checked_context = CheckedRequest(Some(call.value), call.request, true)
      } else {
        report.emit(
          if group is None {
            UnexpectedResponse
          } else {
            DuplicateResponse
          },
          base.field("id") catch {
            _ => base
          },
          "I expected one response for an unmatched original call or invalid element.",
        )
        checked_context = Selected(Some(ResponseContext::EnvelopeOnly))
      }
    }
    let result = self.validate_response_checked(response, checked_context)
    let findings = report.collect(result.findings, base)
    report.complete = report.complete && result.complete
    entries.push({
      index: Some(index),
      request_index,
      result: {
        ..result,
        findings,
        complete: result.complete && report.complete,
      },
    })
    if !report.complete {
      return finish()
    }
  }
  for call in original_calls {
    if !used.contains(call.index) {
      report.emit(
        MissingResponse,
        root,
        "I expected a response for original batch element " +
        call.index.to_string() +
        ".",
      )
    }
  }
  finish()
}

///|
priv enum CheckedResponseContext {
  Selected(ResponseContext?)
  CheckedRequest(Json?, RequestResult, Bool)
  InvalidBatch(ErrorCode)
}

///|
fn PreparedService::check_response_context(
  self : PreparedService,
  context : ResponseContext?,
) -> CheckedResponseContext {
  match context {
    Some(OriginalRequest(text)) => {
      let parsed = Some(@validation.parse_json_value(text)) catch { _ => None }
      let request = match parsed {
        Some(value) => self.validate_json(value)
        None => self.validate_request(text)
      }
      CheckedRequest(parsed, request, false)
    }
    _ => Selected(context)
  }
}

///|
fn PreparedService::finish_response(
  self : PreparedService,
  result : ResponseResult,
) -> ResponseResult {
  let bounded = self.finish({
    findings: result.findings,
    complete: result.complete,
    kind: None,
    id: result.id,
    operation: result.operation,
  })
  { ..result, findings: bounded.findings, complete: bounded.complete, }
}

///|
/// Validate one response. Missing context fails; EnvelopeOnly is an explicit,
/// limited check. OriginalRequest accepts the original text, including invalid JSON.
pub fn PreparedService::validate_response(
  self : PreparedService,
  text : String,
  context~ : ResponseContext? = None,
  legacy_errors~ : LegacyErrorMode = Opaque,
) -> ResponseResult {
  let value = @validation.parse_json_value(text) catch {
    _ => {
      let failed = self.validate_request(text)
      return {
        findings: failed.findings,
        complete: false,
        scope: Envelope,
        kind: None,
        id: Absent,
        operation: None,
      }
    }
  }
  self.validate_response_json(value, context~, legacy_errors~)
}

///|
/// In-memory values retain only the precision supplied by their caller.
pub fn PreparedService::validate_response_json(
  self : PreparedService,
  value : Json,
  context~ : ResponseContext? = None,
  legacy_errors~ : LegacyErrorMode = Opaque,
) -> ResponseResult {
  self.validate_response_checked(
    value,
    self.check_response_context(context),
    legacy_errors~,
  )
}

///|
fn PreparedService::validate_response_checked(
  self : PreparedService,
  value : Json,
  context : CheckedResponseContext,
  legacy_errors~ : LegacyErrorMode = Opaque,
) -> ResponseResult {
  let document = self.document.validate_json(value)
  if !document.is_valid() {
    return {
      findings: value_findings(document, None),
      complete: document.complete,
      scope: Envelope,
      kind: None,
      id: Absent,
      operation: None,
    }
  }
  let findings : Array[Finding] = []
  let mut operation = None
  let mut scope = Envelope
  let mut complete = true
  let mut method_ : PreparedMethod? = None
  let mut original : RequestResult? = None
  let mut expected_code : ErrorCode? = None
  let mut expected_id : RequestId? = None
  let mut expected_legacy_error = false
  let root = @validation.InstancePath::root()
  fn emit(
    code : FindingCode,
    path : @validation.InstancePath,
    message : String,
  ) -> Unit {
    findings.push({
      code,
      path,
      message,
      shape: operation.unwrap_or(self.service),
      operation,
      offset: None,
      severity: if code == LimitedScope {
        @validation.Advisory
      } else {
        @validation.Error
      },
    })
  }
  fn field(name : String) -> @validation.InstancePath {
    root.field(name) catch {
      _ => root
    }
  }
  match context {
    Selected(None) =>
      emit(
        MissingContext,
        root,
        "I expected explicit method, operation, original-request or envelope-only context.",
      )
    Selected(Some(EnvelopeOnly)) =>
      emit(
        LimitedScope,
        root,
        "I checked only the response envelope; payload contracts and request ID correlation were not checked.",
      )
    Selected(Some(Method(name))) => {
      scope = MethodPayload
      method_ = self.methods.get(name)
      if method_ is None {
        emit(
          InvalidContext,
          root,
          "I expected a method declared by the selected service.",
        )
      }
    }
    Selected(Some(Operation(id))) => {
      scope = MethodPayload
      method_ = self.methods.values().find_first(m => m.operation == id)
      if method_ is None {
        emit(
          InvalidContext,
          root,
          "I expected an operation reachable from the selected service.",
        )
      }
    }
    Selected(Some(OriginalRequest(_))) => ()
    InvalidBatch(code) => {
      scope = RequestContext
      expected_code = Some(code)
      expected_id = Some(Present(@smithy.Null))
    }
    CheckedRequest(parsed, request, batch_element) => {
      scope = RequestContext
      original = Some(request)
      if parsed is Some(Array(_)) && !batch_element {
        emit(
          UnsupportedMessage,
          root,
          "I expected a single original request, not a batch context.",
        )
      } else if !request.complete {
        if self.version == V2_0 &&
          request.findings.iter().any(f => f.code == InvalidJson) {
          expected_code = Some(error_code("-32700"))
          expected_id = Some(Present(@smithy.Null))
        } else {
          complete = false
          emit(
            InvalidContext,
            root,
            "I could not completely check the original request under the deterministic input and resource policies.",
          )
        }
      } else {
        let envelope_invalid = invalid_request_envelope(
          self.version,
          parsed.unwrap_or(Json::null()),
          request,
        )
        if envelope_invalid {
          if self.version == V1_0 {
            emit(
              InvalidContext,
              root,
              "I expected a well-formed original version 1.0 request envelope; that protocol defines no standard invalid-request error mapping.",
            )
          } else {
            expected_code = Some(error_code("-32600"))
          }
          // A detectable, valid ID is echoed; otherwise the unknown ID is null.
          expected_id = Some(
            if request.findings.iter().any(f => f.code == InvalidId) ||
              request.id == Absent {
              Present(@smithy.Null)
            } else {
              request.id
            },
          )
        } else if request.kind == Some(Notification) {
          emit(
            UnexpectedResponse,
            root,
            "I expected no response to the supplied notification.",
          )
        } else {
          expected_id = Some(request.id)
          let invalid_call = !request.complete ||
            request.findings
            .iter()
            .any(f => {
              f.severity == @validation.Error && f.code != NotificationExpected
            })
          if self.version == V1_0 && invalid_call {
            expected_legacy_error = true
          } else if request.findings.iter().any(f => f.code == UnknownMethod) {
            expected_code = Some(error_code("-32601"))
          } else if invalid_call {
            expected_code = Some(error_code("-32602"))
          }
        }
        if request.operation is Some(id) {
          method_ = self.methods.values().find_first(m => m.operation == id)
        }
      }
    }
  }
  operation = method_.map(m => m.operation)
  guard value is Object(envelope) else {
    emit(
      if value is Array(_) {
        UnsupportedMessage
      } else {
        InvalidEnvelope
      },
      root,
      "I expected one response object; batch validation requires a separate entry point.",
    )
    return self.finish_response({
      findings,
      complete,
      scope,
      kind: None,
      id: Absent,
      operation,
    })
  }
  if self.version == V2_0 {
    if envelope.get("jsonrpc") != Some(Json::string("2.0")) {
      emit(
        InvalidVersion,
        field("jsonrpc"),
        "I expected the JSON-RPC version marker to be the string 2.0.",
      )
    }
  } else if envelope.contains("jsonrpc") {
    emit(
      InvalidVersion,
      field("jsonrpc"),
      "I expected no jsonrpc marker in the version 1.0 profile.",
    )
  }
  let id = match envelope.get("id") {
    None => {
      emit(InvalidId, field("id"), "I expected an id member in the response.")
      Absent
    }
    Some(value) => {
      let node = @smithy.NodeValue::from_json(value) catch {
        _ => {
          emit(InvalidId, field("id"), "I expected an exact JSON ID value.")
          return self.finish_response({
            findings,
            complete: false,
            scope,
            kind: None,
            id: Absent,
            operation,
          })
        }
      }
      if self.version == V2_0 &&
        !(node is @smithy.String(_) ||
        node is @smithy.Number(_) ||
        node is @smithy.Null) {
        emit(
          InvalidId,
          field("id"),
          "I expected a string, number or null response ID in version 2.0.",
        )
      }
      Present(node)
    }
  }
  if expected_id is Some(expected) && expected != id {
    emit(
      IdMismatch,
      field("id"),
      "I expected the exact ID of the supplied original request, or null when its ID was unknown.",
    )
  }
  let result = envelope.get("result")
  let error = envelope.get("error")
  let mut kind = None
  let success = if self.version == V2_0 {
    if (result is Some(_)) == (error is Some(_)) {
      emit(
        InvalidEnvelope,
        root,
        "I expected exactly one of result and error in a version 2.0 response.",
      )
    }
    result is Some(_) && error is None
  } else {
    if result is None || error is None {
      emit(
        InvalidEnvelope,
        root,
        "I expected both result and error members in a version 1.0 response.",
      )
    }
    if error is Some(Null) {
      result is Some(_)
    } else {
      if result != Some(Json::null()) {
        emit(
          InvalidEnvelope,
          field("result"),
          "I expected a null result on a version 1.0 error response.",
        )
      }
      false
    }
  }
  let mut response_code : ErrorCode? = None
  if success {
    kind = Some(Success)
    if method_ is Some(method_) {
      match method_.result_validator {
        Some(validator) => {
          let checked = validator.validate(
            Original(result.unwrap()),
            base_path=field("result"),
          )
          complete = complete && checked.complete
          findings.append(value_findings(checked, operation))
        }
        None =>
          if result != Some(Json::null()) {
            emit(
              Value(@validation.TypeMismatch),
              field("result"),
              "I expected a null result for the selected operation.",
            )
          }
      }
    }
  } else if error is Some(error) && !(self.version == V1_0 && error is Null) {
    if self.version == V1_0 && legacy_errors == Opaque {
      kind = Some(LegacyError)
      emit(
        LimitedScope,
        field("error"),
        "I checked an opaque legacy error; no code/message/data application mapping was selected.",
      )
    } else {
      guard error is Object(error_fields) else {
        emit(
          InvalidError,
          field("error"),
          "I expected an error object with integer code and string message.",
        )
        return self.finish_response({
          findings,
          complete,
          scope,
          kind,
          id,
          operation,
        })
      }
      response_code = match error_fields.get("code") {
        Some(Number(n, repr~)) =>
          @smithy.NodeNumber::parse(repr.unwrap_or(n.to_string())).bind(
            ErrorCode::from_number,
          )
        _ => None
      }
      let code_path = field("error").field("code") catch { _ => root }
      if response_code is Some(code) {
        if code.is_reserved() {
          kind = Some(ProtocolError)
          if !code.is_protocol() {
            emit(
              InvalidError,
              code_path,
              "I expected a defined protocol code or an implementation server error, not a reserved future code.",
            )
          }
        } else {
          kind = Some(ApplicationError)
          if method_ is None && scope == RequestContext {
            emit(
              LimitedScope,
              field("error"),
              "I could not check application error data without a modeled method for the original request.",
            )
          }
          if method_ is Some(method_) {
            match method_.errors.iter().find_first(e => e.code == code) {
              None =>
                emit(
                  UnknownError,
                  code_path,
                  "I expected an application error code modeled for the selected operation.",
                )
              Some(mapping) => {
                let path = field("error").field("data") catch { _ => root }
                match (mapping.data_validator, error_fields.get("data")) {
                  (None, Some(_)) =>
                    findings.push({
                      code: InvalidError,
                      path,
                      shape: mapping.shape,
                      operation,
                      offset: None,
                      severity: @validation.Error,
                      message: "I expected absent data for the selected application error.",
                    })
                  (Some(validator), Some(data)) => {
                    let checked = validator.validate(
                      Original(data),
                      base_path=path,
                    )
                    complete = complete && checked.complete
                    findings.append(value_findings(checked, operation))
                  }
                  (Some(_), None) =>
                    if mapping.data_required {
                      findings.push({
                        code: Value(@validation.RequiredMember),
                        path,
                        shape: mapping.data_target,
                        operation,
                        offset: None,
                        severity: @validation.Error,
                        message: "I expected data for the selected application error contract.",
                      })
                    }
                  (None, None) => ()
                }
              }
            }
          }
        }
      } else {
        emit(InvalidError, code_path, "I expected an exact integer error code.")
      }
      if !(error_fields.get("message") is Some(String(_))) {
        emit(
          InvalidError,
          field("error").field("message") catch {
            _ => root
          },
          "I expected a string error message.",
        )
      }
    }
  }
  if self.version == V2_0 &&
    response_code == Some(error_code("-32700")) &&
    id != Present(@smithy.Null) {
    emit(
      InvalidId,
      field("id"),
      "I expected a null unknown ID for a parse-error response.",
    )
  }
  if expected_legacy_error && (kind is None || kind == Some(Success)) {
    emit(
      InvalidContext,
      field("error"),
      "I expected a nonnull legacy error for the supplied unknown method or invalid modeled parameters.",
    )
  }
  if expected_code is Some(expected) && response_code != Some(expected) {
    emit(
      InvalidContext,
      field("error"),
      "I expected protocol error " +
      expected.to_string() +
      " for the supplied original request.",
    )
  }
  if original is Some(request) &&
    request.is_valid() &&
    (
      response_code == Some(error_code("-32700")) ||
      response_code == Some(error_code("-32600"))
    ) {
    emit(
      InvalidContext,
      field("error"),
      "I expected a response compatible with the supplied valid request.",
    )
  }
  self.finish_response({ findings, complete, scope, kind, id, operation, })
}

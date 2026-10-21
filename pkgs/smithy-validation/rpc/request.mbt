///|
priv enum ParameterValue {
  Original(Json)
  Parameters(Array[@validation.LocatedField[ParameterValue]])
}

///|
impl @validation.ValueView for ParameterValue with fn inspect(self) {
  match self {
    Parameters(fields) => @validation.LocatedObject(fields)
    Original(value) =>
      match value {
        Null => @validation.Null
        True => @validation.Boolean(true)
        False => @validation.Boolean(false)
        String(s) => @validation.String(s)
        Number(n, repr~) =>
          match @smithy.NodeNumber::parse(repr.unwrap_or(n.to_string())) {
            Some(number) => @validation.Number(number)
            None => @validation.InvalidNumber
          }
        Array(values) => @validation.Array(values.map(v => Original(v)))
        Object(fields) => {
          let names = fields.keys().to_array()
          names.sort()
          @validation.Object(
            names.map(name => (name, Original(fields.get(name).unwrap()))),
          )
        }
      }
  }
}

///|
fn value_findings(
  result : @validation.ValidationResult,
  operation : @smithy.ShapeId?,
) -> Array[Finding] {
  result.findings.map(f => {
    code: Value(f.code),
    severity: f.severity,
    path: f.path,
    shape: f.shape,
    operation,
    offset: None,
    message: f.message,
  })
}

///|
fn PreparedService::finish(
  self : PreparedService,
  result : RequestResult,
) -> RequestResult {
  let result = {
    ..result,
    findings: result.findings.map(f => {
      if f.operation is None {
        { ..f, operation: result.operation, }
      } else {
        f
      }
    }),
  }
  if result.findings.length() <= self.finding_limit {
    return result
  }
  let findings = result.findings[:self.finding_limit - 1].to_owned()
  findings.push({
    code: Value(@validation.LimitExceeded),
    severity: @validation.Error,
    path: @validation.InstancePath::root(),
    shape: self.service,
    operation: result.operation,
    offset: None,
    message: "I reached the message finding limit before reporting every violation.",
  })
  { ..result, findings, complete: false, }
}

///|
/// Validate exactly one JSON-RPC request or notification, without executing it.
/// Use validate_response for responses. Batches and exchanges are separate checks.
pub fn PreparedService::validate_request(
  self : PreparedService,
  text : String,
) -> RequestResult {
  let value = @validation.parse_json_value(text) catch {
    error => {
      let (code, offset, message) = match error {
        @validation.InvalidJson(at, message) => (InvalidJson, at, message)
        @validation.DuplicateJsonKey(at) =>
          (DuplicateJsonKey, at, "I expected unique JSON object member names.")
        @validation.JsonInputLimit(at, message) => (JsonInputLimit, at, message)
      }
      return {
        complete: false,
        kind: None,
        id: Absent,
        operation: None,
        findings: [
          {
            code,
            offset: Some(offset),
            message,
            path: @validation.InstancePath::root(),
            shape: self.service,
            operation: None,
            severity: @validation.Error,
          },
        ],
      }
    }
  }
  self.validate_json(value)
}

///|
/// In-memory JSON is checked under the same bounded JSON value profile. Numbers
/// can only be as exact as the caller retained; prefer validate_request for text.
pub fn PreparedService::validate_json(
  self : PreparedService,
  value : Json,
) -> RequestResult {
  let document = self.document.validate_json(value)
  if !document.is_valid() {
    return {
      findings: value_findings(document, None),
      complete: document.complete,
      kind: None,
      id: Absent,
      operation: None,
    }
  }
  let findings = []
  let mut operation = None
  fn emit(code : FindingCode, field : String?, message : String) -> Unit {
    let root = @validation.InstancePath::root()
    findings.push({
      code,
      path: field
      .map(name => root.field(name) catch { _ => root })
      .unwrap_or(root),
      shape: operation.unwrap_or(self.service),
      operation,
      offset: None,
      message,
      severity: if code == DiscouragedId {
        @validation.Advisory
      } else {
        @validation.Error
      },
    })
  }
  guard value is Object(envelope) else {
    emit(
      if value is Array(_) {
        UnsupportedMessage
      } else {
        InvalidEnvelope
      },
      None,
      "I expected one request object; batch validation is not supported by this entry point.",
    )
    return self.finish({
      findings,
      complete: true,
      kind: None,
      id: Absent,
      operation,
    })
  }
  if !envelope.contains("method") &&
    (envelope.contains("result") || envelope.contains("error")) {
    emit(
      UnsupportedMessage,
      None,
      "I expected a request; contextual response validation is not supported by this entry point.",
    )
    return self.finish({
      findings,
      complete: true,
      kind: None,
      id: Absent,
      operation,
    })
  }
  if self.version == V2_0 {
    if envelope.get("jsonrpc") != Some(Json::string("2.0")) {
      emit(
        InvalidVersion,
        Some("jsonrpc"),
        "I expected the JSON-RPC version marker to be the string 2.0.",
      )
    }
  } else if envelope.contains("jsonrpc") {
    emit(
      InvalidVersion,
      Some("jsonrpc"),
      "I expected no jsonrpc marker in the version 1.0 profile.",
    )
  }
  let id = match envelope.get("id") {
    None => Absent
    Some(value) =>
      Present(
        @smithy.NodeValue::from_json(value) catch {
          _ => {
            emit(InvalidId, Some("id"), "I expected an exact JSON ID value.")
            return self.finish({
              findings,
              complete: false,
              kind: None,
              id: Absent,
              operation,
            })
          }
        },
      )
  }
  let kind = if self.version == V1_0 {
    match id {
      Absent => {
        emit(
          InvalidId,
          Some("id"),
          "I expected an id member in a version 1.0 request.",
        )
        None
      }
      Present(Null) => Some(Notification)
      Present(_) => Some(Call)
    }
  } else {
    match id {
      Absent => Some(Notification)
      Present(Null) => {
        emit(
          DiscouragedId,
          Some("id"),
          "I recommend a nonnull ID for a version 2.0 call.",
        )
        Some(Call)
      }
      Present(Number(number)) => {
        let spelling = number.to_string()
        // Validate the exact number as an integer without a lossy Double conversion.
        if !number_is_integer(spelling) {
          emit(
            DiscouragedId,
            Some("id"),
            "I recommend an integer ID for a version 2.0 call.",
          )
        }
        Some(Call)
      }
      Present(String(_)) => Some(Call)
      Present(_) => {
        emit(
          InvalidId,
          Some("id"),
          "I expected a string, number or null ID in a version 2.0 call.",
        )
        Some(Call)
      }
    }
  }
  let method_ = match envelope.get("method") {
    Some(String(raw_name)) =>
      match MethodName::parse(raw_name) {
        Some(name) => self.methods.get(name)
        None => {
          emit(
            InvalidEnvelope,
            Some("method"),
            "I expected a nonempty application method name outside the reserved rpc. namespace.",
          )
          None
        }
      }
    _ => {
      emit(
        InvalidEnvelope,
        Some("method"),
        "I expected a string method member in the request.",
      )
      None
    }
  }
  let params = envelope.get("params")
  if self.version == V1_0 && !(params is Some(Array(_))) {
    emit(
      InvalidParams,
      Some("params"),
      "I expected a positional params array in version 1.0.",
    )
  } else if params is Some(_) &&
    !(params is Some(Array(_)) || params is Some(Object(_))) {
    emit(
      InvalidParams,
      Some("params"),
      "I expected params to be an object or array when present.",
    )
  }
  guard method_ is Some(method_) else {
    if envelope.get("method") is Some(String(name)) &&
      MethodName::parse(name) is Some(_) {
      emit(
        UnknownMethod,
        Some("method"),
        "I expected a method declared by the selected service, but found " +
        name +
        ".",
      )
    }
    return self.finish({ findings, complete: true, kind, id, operation, })
  }
  operation = Some(method_.operation)
  let root = @validation.InstancePath::root()
  let base = root.field("params") catch { _ => root }
  let input = match params {
    Some(Object(_)) if self.version == V2_0 && method_.mode != Positional =>
      Some(Original(params.unwrap()))
    Some(Array(values)) if method_.mode != Named =>
      if values.length() > method_.order.length() {
        emit(
          InvalidParams,
          Some("params"),
          "I expected no more positional arguments than the explicit member order.",
        )
        None
      } else {
        Some(
          Parameters(
            values.mapi((i, value) => {
              @validation.LocatedField::new(
                method_.order[i],
                Original(value),
                root.index(i) catch {
                  _ => root
                },
              )
            }),
          ),
        )
      }
    None if self.version == V2_0 => Some(Parameters([]))
    Some(Object(_)) | Some(Array(_)) => {
      emit(
        InvalidParams,
        Some("params"),
        "I expected params to match the method's declared parameter mode.",
      )
      None
    }
    _ => None
  }
  let mut complete = true
  if input is Some(input) {
    let result = method_.validator.validate(input, base_path=base)
    complete = result.complete
    for finding in value_findings(result, operation) {
      // A missing positional argument has no source node, but its slot is known.
      let path = if params is Some(Array(_)) &&
        finding.code == Value(@validation.RequiredMember) {
        match finding.path.steps() {
          [@validation.Field("params", 0), @validation.Field(name, 0)] =>
            match method_.order.search(name) {
              Some(index) => base.index(index) catch { _ => finding.path }
              None => finding.path
            }
          _ => finding.path
        }
      } else {
        finding.path
      }
      findings.push({ ..finding, path, })
    }
  }
  self.finish({ findings, complete, kind, id, operation, })
}

///|
fn number_is_integer(text : String) -> Bool {
  let parts = text.replace_all(old="E", new="e").split("e").to_array()
  let mantissa = parts[0].to_owned()
  let power = if parts.length() == 2 {
    BigInt::from_string(parts[1].trim_start(chars="+").to_owned())
  } else {
    BigInt::from_int(0)
  }
  let fraction = mantissa
    .find(".")
    .map(i => mantissa.length() - i - 1)
    .unwrap_or(0)
  let digits = mantissa
    .replace_all(old=".", new="")
    .trim_start(chars="-")
    .to_owned()
  let trimmed = digits.trim_end(chars="0")
  trimmed.is_empty() ||
  power -
  BigInt::from_int(fraction) +
  BigInt::from_int(digits.length() - trimmed.length()) >=
  BigInt::from_int(0)
}

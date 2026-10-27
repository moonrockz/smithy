///|
/// A reusable codec of one model root under one profile. Checking, decoding and encoding use the same
/// detached wire contract, the same adapters and the same Smithy value constraints.
pub struct PreparedCodec {
  priv contract : @contract.WireContract
  priv validator : @validation.PreparedValidator
  priv adapters : AdapterRegistry
  priv limits : CodecLimits
  priv root : SemanticRoot
}

///|
/// Prepare a codec. Without a profile, the base rules and the standard layouts apply. Preparation fails
/// on an unknown profile, a missing adapter or an inconsistent or unsupported declaration; it never falls
/// back to another layout.
pub fn PreparedCodec::prepare(
  model : @smithy.Model,
  root : @smithy.ShapeId,
  profile~ : @contract.ProfileId? = None,
  adapters~ : AdapterRegistry = AdapterRegistry::new(),
  limits~ : CodecLimits = CodecLimits::default(),
) -> PreparedCodec raise @contract.ContractError {
  let contract = @contract.WireContract::prepare(
    model,
    root,
    profile~,
    adapters=adapters.signatures(),
  )
  let config = @validation.Config::new(
    limits=@validation.Limits::new(
      depth=limits.depth,
      work=limits.work,
      findings=limits.findings,
    ) catch {
      @validation.ConfigurationError(message) =>
        raise @contract.InvalidTarget(root, message)
    },
  )
  let validator = @validation.PreparedValidator::prepare(model, root, config~) catch {
    @validation.InvalidTarget(id, message) =>
      raise @contract.InvalidTarget(id, message)
    @validation.InvalidConfiguration(message) =>
      raise @contract.InvalidTarget(root, message)
    @validation.InvalidModel(id, message) =>
      raise @contract.InvalidDeclaration(id, message)
    @validation.UnsupportedConstraint(id, message) =>
      raise @contract.UnsupportedDeclaration(id, message)
  }
  {
    contract,
    validator,
    adapters,
    limits,
    root: { shape: root, fingerprint: contract.fingerprint, },
  }
}

///|
/// The detached wire contract, for generators and schema exporters.
pub fn PreparedCodec::contract(self : PreparedCodec) -> @contract.WireContract {
  self.contract
}

///|
pub fn PreparedCodec::semantic_root(self : PreparedCodec) -> SemanticRoot {
  self.root
}

///|
pub fn PreparedCodec::limits(self : PreparedCodec) -> CodecLimits {
  self.limits
}

///|
fn utf8_bytes(text : String) -> Int32 {
  let mut bytes = 0
  for c in text.iter() {
    let n = c.to_int()
    bytes += if n < 0x80 {
      1
    } else if n < 0x800 {
      2
    } else if n < 0x10000 {
      3
    } else {
      4
    }
  }
  bytes
}

///|
/// Parse bounded, duplicate-aware JSON text. Findings go to the request.
fn parse_text(
  request : Request,
  text : String,
  shape : @smithy.ShapeId,
) -> Json? {
  let root = @validation.InstancePath::root()
  let bytes = utf8_bytes(text)
  if bytes > request.limits.input_bytes {
    request.stop(root, shape, "input size")
    return None
  }
  // Parsing charges one unit for each 64 bytes of input.
  if !request.charge(root, shape, units=bytes / 64 + 1) {
    return None
  }
  let parsed = @validation.parse_json_value(text) catch {
    @validation.InvalidJson(offset, message) => {
      request.emit(InvalidJson, root, shape, "At offset \{offset}: " + message)
      return None
    }
    @validation.DuplicateJsonKey(offset) => {
      request.emit(
        DuplicateName,
        root,
        shape,
        "At offset \{offset}: I found a duplicate decoded object member name.",
      )
      return None
    }
    @validation.JsonInputLimit(offset, message) => {
      request.stop(root, shape, "input nesting")
      request.findings[request.findings.length() - 1] = {
        ..request.findings[request.findings.length() - 1],
        message: "At offset \{offset}: " + message,
      }
      return None
    }
  }
  Some(parsed)
}

///|
/// Check a projected node against the Smithy value constraints, sharing the request's work meter.
fn PreparedCodec::constrain(
  self : PreparedCodec,
  request : Request,
  node : LNode,
) -> Unit {
  let result = self.validator.validate_metered(node, meter=request.meter)
  self.absorb(request, result)
}

///|
fn PreparedCodec::absorb(
  self : PreparedCodec,
  request : Request,
  result : @validation.ValidationResult,
) -> Unit {
  for finding in result.findings {
    if finding.code == LimitExceeded {
      request.stop(finding.path, finding.shape, "work")
    } else {
      request.emit(
        Constraint(finding.code),
        finding.path,
        finding.shape,
        finding.message,
      )
    }
  }
  if !result.complete {
    request.stop(@validation.InstancePath::root(), self.root.shape, "work")
  }
}

///|
/// Read a parsed JSON value under this codec's contract, sharing `request`.
fn PreparedCodec::read_parsed(
  self : PreparedCodec,
  request : Request,
  json : Json,
) -> LogicalValue? {
  match
    read_json(
      self.contract,
      self.adapters,
      request,
      json,
      @validation.InstancePath::root(),
    ) {
    Some(node) => {
      self.constrain(request, node)
      if request.complete && request.findings.is_empty() {
        Some(node.to_logical())
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn PreparedCodec::read_text(
  self : PreparedCodec,
  request : Request,
  text : String,
) -> LogicalValue? {
  match parse_text(request, text, self.root.shape) {
    Some(json) => self.read_parsed(request, json)
    None => None
  }
}

///|
/// Check JSON text. A complete check without findings agrees with a successful decode.
pub fn PreparedCodec::check(self : PreparedCodec, text : String) -> CodecResult {
  let request = Request::new(self.limits)
  ignore(self.read_text(request, text))
  request.result()
}

///|
/// Decode JSON text into a value of this codec's semantic root.
pub fn PreparedCodec::decode(
  self : PreparedCodec,
  text : String,
) -> CodecValue raise CodecFailure {
  let request = Request::new(self.limits)
  match self.read_text(request, text) {
    Some(value) => { root: self.root, value, }
    None => raise CodecFailure(request.result())
  }
}

///|
/// Check a caller's logical value against this codec's root and return it as a codec value. This is the
/// validated builder: the value is copied into its normalized form.
pub fn PreparedCodec::value(
  self : PreparedCodec,
  value : LogicalValue,
) -> CodecValue raise CodecFailure {
  let request = Request::new(self.limits)
  match self.admit(request, value) {
    Some(normalized) => { root: self.root, value: normalized, }
    None => raise CodecFailure(request.result())
  }
}

///|
fn PreparedCodec::admit(
  self : PreparedCodec,
  request : Request,
  value : LogicalValue,
) -> LogicalValue? {
  guard normalize(self.contract, request, value) is Some(normalized) else {
    return None
  }
  let result = self.validator.validate_metered(normalized, meter=request.meter)
  self.absorb(request, result)
  if request.complete && request.findings.is_empty() {
    Some(normalized)
  } else {
    None
  }
}

///|
/// Encode a value of this codec's semantic root. The value is checked again before any output exists, and
/// a value of another root is refused.
pub fn PreparedCodec::encode(
  self : PreparedCodec,
  value : CodecValue,
) -> String raise CodecFailure {
  let request = Request::new(self.limits)
  match self.encode_in(request, value) {
    Some(text) => text
    None => raise CodecFailure(request.result())
  }
}

///|
fn PreparedCodec::encode_in(
  self : PreparedCodec,
  request : Request,
  value : CodecValue,
) -> String? {
  if value.root != self.root {
    request.emit(
      IncompatibleValue,
      @validation.InstancePath::root(),
      self.root.shape,
      "I expected a value of \{self.root}, but found a value of \{value.root}. Convert it explicitly.",
    )
    return None
  }
  guard self.admit(request, value.value) is Some(normalized) else {
    return None
  }
  guard write_value(self.contract, self.adapters, request, normalized)
    is Some(text) else {
    return None
  }
  if utf8_bytes(text) > self.limits.output_bytes {
    request.stop(
      @validation.InstancePath::root(),
      self.root.shape,
      "output size",
    )
    return None
  }
  Some(text)
}

///|
/// Decode and re-encode JSON text in this codec's canonical form. One request budget covers both.
pub fn PreparedCodec::canonicalize(
  self : PreparedCodec,
  text : String,
) -> String raise CodecFailure {
  let request = Request::new(self.limits)
  guard self.read_text(request, text) is Some(value) else {
    raise CodecFailure(request.result())
  }
  match self.encode_in(request, { root: self.root, value, }) {
    Some(out) => out
    None => raise CodecFailure(request.result())
  }
}

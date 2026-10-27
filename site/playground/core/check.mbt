///|
/// The line of the finding as the CLI prints it for the input file `file`. A
/// `Found` has the format of `smithy validate rpc`, which is the format of
/// `smithy validate value` when the offset is `None`. A `Stopped` names its
/// source, else the input file, and does not print the offset.
pub fn DataFinding::cli_line(self : DataFinding, file~ : String) -> String {
  match self {
    Found(code~, severity~, path~, shape~, message~, offset~) => {
      let at = offset.map(at => ":" + at.to_string()).unwrap_or("")
      "\{file}\{at}\{path}: \{severity}[\{code}] \{shape}: \{message}"
    }
    Stopped(code~, message~, source~, offset=_) =>
      "\{source.unwrap_or(file)}: error[\{code}]: \{message}"
  }
}

///|
/// The configuration of the validation library for the options of a check.
fn value_config(options : ValueOptions) -> @validation.Config {
  @validation.Config::new(
    unknown_members=match options.unknown_members {
      Reject => @validation.Reject
      Ignore => @validation.Ignore
    },
    member_names=match options.member_names {
      Smithy => @validation.Smithy
      JsonName => @validation.JsonName
    },
  )
}

///|
/// The severity of a finding as the CLI prints it.
fn severity_text(severity : @validation.FindingSeverity) -> String {
  match severity {
    @validation.Error => "error"
    @validation.Advisory => "advisory"
  }
}

///|
/// A finding of the validation library as a `Found`.
fn found_of(finding : @validation.Finding) -> DataFinding {
  Found(
    code=finding.code.to_string(),
    severity=severity_text(finding.severity),
    path=finding.path.pointer(),
    shape=finding.shape.to_string(),
    message=finding.message,
    offset=None,
  )
}

///|
/// A finding of the JSON-RPC library as a `Found`, with its offset.
fn rpc_found_of(finding : @rpc.Finding) -> DataFinding {
  Found(
    code=finding.code.to_string(),
    severity=severity_text(finding.severity),
    path=finding.path.pointer(),
    shape=finding.shape.to_string(),
    message=finding.message,
    offset=finding.offset,
  )
}

///|
/// A check that stopped with one problem.
fn stopped(
  seq : Int32,
  code : String,
  message : String,
  source~ : String? = None,
  offset~ : Int32? = None,
) -> Response {
  DataChecked(seq~, valid=false, findings=[
    Stopped(code~, message~, source~, offset~),
  ])
}

///|
/// Check a JSON value against a data shape, as `smithy validate value` does
/// (`run_value_validation` in `apps/smithy/value_cli.mbt`), with the same
/// library calls in the same order and the same codes and messages. As the
/// CLI, it checks the shape ID before it loads the model.
fn check_value(
  seq : Int32,
  files : Array[(String, String)],
  shape : String,
  value : String,
  options : ValueOptions,
) -> Response {
  guard @smithy.ShapeId::parse(shape) is Some(target) else {
    return blocked(
      seq~,
      reason="I expected an absolute shape ID for the shape, but found '\{shape}'.",
    )
  }
  let model = match clean_model(load(files)) {
    Ok(model) => model
    Err((reason, kind)) => return Blocked(seq~, reason~, kind~)
  }
  if options.profile is Some(profile) {
    return check_codec_value(seq, model, target, profile, value)
  }
  let prepared = @validation.PreparedValidator::prepare(
    model,
    target,
    config=value_config(options),
  ) catch {
    InvalidTarget(id, message) =>
      return stopped(
        seq,
        "InvalidTarget",
        id.to_string() + ": " + message,
        source=Some("--shape"),
      )
    InvalidConfiguration(message) =>
      return stopped(seq, "InvalidConfiguration", message)
    InvalidModel(id, message) =>
      return stopped(
        seq,
        "InvalidModel",
        id.to_string() + ": " + message,
        source=model.shapes.get(id).map(s => s.source.file),
      )
    UnsupportedConstraint(id, message) =>
      return stopped(
        seq,
        "UnsupportedConstraint",
        id.to_string() + ": " + message,
        source=model.shapes.get(id).map(s => s.source.file),
      )
  }
  let json = @validation.parse_json_value(value) catch {
    InvalidJson(at, message) =>
      return stopped(seq, "InvalidJson", message, offset=Some(at))
    DuplicateJsonKey(at) =>
      return stopped(
        seq,
        "DuplicateJsonKey",
        "I expected unique JSON object member names, but found a duplicate.",
        offset=Some(at),
      )
    JsonInputLimit(at, message) =>
      return stopped(seq, "JsonInputLimit", message, offset=Some(at))
  }
  let result = prepared.validate_json(json)
  DataChecked(
    seq~,
    valid=result.is_valid(),
    findings=result.findings.map(found_of),
  )
}

///|
/// The response context of the library for a context of the request, or the
/// reason to block. The checks are the option checks of the CLI.
fn rpc_context(
  context : ResponseContext,
) -> Result[@rpc.ResponseContext, String] {
  match context {
    EnvelopeOnly => Ok(@rpc.EnvelopeOnly)
    Method(name) =>
      match @rpc.MethodName::parse(name) {
        Some(name) => Ok(@rpc.Method(name))
        None =>
          Err("I expected an application method name, but found '\{name}'.")
      }
    Operation(id) =>
      match @smithy.ShapeId::parse(id) {
        Some(parsed) if parsed.member_name() is None =>
          Ok(@rpc.Operation(parsed))
        _ => Err("I expected an absolute operation ID, but found '\{id}'.")
      }
    OriginalRequest(text) => Ok(@rpc.OriginalRequest(text))
  }
}

///|
/// Check one JSON-RPC message against a service, as `smithy validate rpc`
/// does with `--message` or `--response` (`apps/smithy/cli.mbt` and
/// `run_rpc_validation` in `apps/smithy/rpc_cli.mbt`), with the same library
/// calls in the same order and the same codes and messages. As the CLI, it
/// checks the options and the service ID before it loads the model. The
/// library reads the message as text, so an id keeps all of its digits.
fn check_message(
  seq : Int32,
  files : Array[(String, String)],
  service : String,
  version : RpcVersion,
  message : String,
  kind : MessageKind,
  options : ValueOptions,
) -> Response {
  let rpc_version = match version {
    V1_0 => @rpc.V1_0
    V2_0 => @rpc.V2_0
  }
  let response = match kind {
    RequestMessage => None
    ResponseMessage(context~, legacy_errors~) => {
      if legacy_errors is Some(_) && version != V1_0 {
        return blocked(seq~, reason="--legacy-errors requires version 1.0")
      }
      let legacy_errors = match legacy_errors {
        None | Some(Opaque) => @rpc.Opaque
        Some(CodeMessageData) => @rpc.CodeMessageData
      }
      let context = match context {
        None => None
        Some(context) =>
          match rpc_context(context) {
            Ok(context) => Some(context)
            Err(reason) => return blocked(seq~, reason~)
          }
      }
      Some((context, legacy_errors))
    }
  }
  guard @smithy.ShapeId::parse(service) is Some(id) else {
    return blocked(
      seq~,
      reason="I expected an absolute shape ID for the service, but found '\{service}'.",
    )
  }
  let model = match clean_model(load(files)) {
    Ok(model) => model
    Err((reason, kind)) => return Blocked(seq~, reason~, kind~)
  }
  let prepared = @rpc.PreparedService::prepare(
    model,
    id,
    rpc_version,
    config=value_config(options),
  ) catch {
    @rpc.InvalidContract(id, message) =>
      return stopped(
        seq,
        "InvalidContract",
        id.to_string() + ": " + message,
        source=Some("--service"),
      )
    @validation.UnsupportedConstraint(id, message) =>
      return stopped(
        seq,
        "UnsupportedConstraint",
        id.to_string() + ": " + message,
      )
    error => return stopped(seq, "InvalidConfiguration", error.to_string())
  }
  let (valid, findings) = match response {
    None => {
      let result = prepared.validate_request(message)
      (result.is_valid(), result.findings)
    }
    Some((context, legacy_errors)) => {
      let result = prepared.validate_response(message, context~, legacy_errors~)
      (result.is_valid(), result.findings)
    }
  }
  DataChecked(seq~, valid~, findings=findings.map(rpc_found_of))
}

///|
/// Check a JSON value with a declared serialization profile of the target, as
/// `smithy validate value --profile` does (the node selection of `run_codec`
/// in `apps/smithy/codec_cli.mbt`): the same adapters, the same preparation
/// before the value is read, and the same codes and messages. A refused
/// preparation names `--profile`, as the CLI prints it.
fn check_codec_value(
  seq : Int32,
  model : @smithy.Model,
  target : @smithy.ShapeId,
  profile : String,
  value : String,
) -> Response {
  let id = @codec_contract.ProfileId::parse(profile) catch {
    _ =>
      return blocked(
        seq~,
        reason="expected a profile identifier after --profile, but found '\{profile}'.",
      )
  }
  let codec = @codec.PreparedCodec::prepare(
    model,
    target,
    profile=Some(id),
    adapters=@morphir.registry(),
  ) catch {
    error =>
      return stopped(
        seq,
        error.code(),
        error.message(),
        source=Some("--profile"),
      )
  }
  let result = codec.check(value)
  DataChecked(
    seq~,
    valid=result.is_valid(),
    findings=result.findings.map(finding => {
      Found(
        code=finding.code.to_string(),
        severity="error",
        path=finding.path.pointer(),
        shape=finding.shape.to_string(),
        message=finding.message,
        offset=None,
      )
    }),
  )
}

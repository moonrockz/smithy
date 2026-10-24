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
/// A finding of the validation library as a `Found`.
fn found_of(finding : @validation.Finding) -> DataFinding {
  Found(
    code=finding.code.to_string(),
    severity=if finding.severity == @validation.Error {
      "error"
    } else {
      "advisory"
    },
    path=finding.path.pointer(),
    shape=finding.shape.to_string(),
    message=finding.message,
    offset=None,
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
/// library calls in the same order and the same codes and messages.
fn check_value(
  seq : Int32,
  files : Array[(String, String)],
  shape : String,
  value : String,
  options : ValueOptions,
) -> Response {
  let model = match clean_model(load(files)) {
    Ok(model) => model
    Err((reason, kind)) => return Blocked(seq~, reason~, kind~)
  }
  guard @smithy.ShapeId::parse(shape) is Some(target) else {
    return blocked(
      seq~,
      reason="I expected an absolute shape ID for the shape, but found '\{shape}'.",
    )
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

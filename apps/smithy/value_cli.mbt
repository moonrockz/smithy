///|
priv enum ValueDiagnostics {
  TextFindings
  JsonFindings
} derive(Eq)

///|
priv struct ValueOptions {
  target : @smithy.ShapeId
  file : String
  diagnostics : ValueDiagnostics
  config : @validation.Config
}

///|
fn value_problem(
  opts : ValueOptions,
  code : String,
  message : String,
  status : Int32,
  offset~ : Int32? = None,
  source~ : String? = None,
) -> Int32 {
  let source = source.unwrap_or(opts.file)
  if opts.diagnostics == JsonFindings {
    let finding : Map[String, Json] = {
      "code": Json::string(code),
      "severity": Json::string("error"),
      "message": Json::string(message),
      "shape": Json::string(opts.target.to_string()),
      "source": Json::string(source),
      "path": Json::array([]),
      "pointer": Json::string(""),
    }
    if offset is Some(offset) {
      finding["offset"] = Json::number(offset.to_double())
    }
    let result = Json::object({
      "valid": Json::boolean(false),
      "complete": Json::boolean(false),
      "findings": Json::array([Json::object(finding)]),
    })
    println(result.stringify())
  } else {
    eprintln("\{source}: error[\{code}]: \{message}")
  }
  status
}

///|
fn run_value_validation(
  opts : ValueOptions,
  assembled : @smithy.LoadResult,
) -> Int32 {
  let errors = assembled
    .validation_events()
    .filter(event => event.severity == "ERROR" || event.severity == "DANGER")
  if !errors.is_empty() {
    if opts.diagnostics == JsonFindings {
      let findings = errors.map(event => {
        let finding : Map[String, Json] = {
          "code": Json::string(event.id),
          "severity": Json::string(event.severity),
          "message": Json::string(event.message),
          "shape": event.shape
          .map(id => Json::string(id.to_string()))
          .unwrap_or(Json::null()),
          "source": event.source
          .map(source => Json::string(source.file))
          .unwrap_or(Json::null()),
          "path": Json::array([]),
          "pointer": Json::string(""),
        }
        Json::object(finding)
      })
      println(
        Json::object({
          "valid": Json::boolean(false),
          "complete": Json::boolean(false),
          "findings": Json::array(findings),
        }).stringify(),
      )
    } else {
      for event in errors {
        eprintln(validation_event_text(event))
      }
    }
    return 1
  }
  guard assembled.model is Some(model) else {
    return value_problem(
      opts,
      "InvalidModel",
      assembled.diagnostics
      .map(d => d.source.file + ": " + d.message)
      .join("\n"),
      1,
      source=assembled.diagnostics.get(0).map(d => d.source.file),
    )
  }
  let prepared = @validation.PreparedValidator::prepare(
    model,
    opts.target,
    config=opts.config,
  ) catch {
    @validation.InvalidTarget(id, message) =>
      return value_problem(
        opts,
        "InvalidTarget",
        id.to_string() + ": " + message,
        2,
        source=Some("--shape"),
      )
    @validation.InvalidConfiguration(message) =>
      return value_problem(opts, "InvalidConfiguration", message, 2)
    @validation.InvalidModel(id, message) =>
      return value_problem(
        opts,
        "InvalidModel",
        id.to_string() + ": " + message,
        1,
        source=model.shapes.get(id).map(s => s.source.file),
      )
    @validation.UnsupportedConstraint(id, message) =>
      return value_problem(
        opts,
        "UnsupportedConstraint",
        id.to_string() + ": " + message,
        2,
        source=model.shapes.get(id).map(s => s.source.file),
      )
  }
  let text = try {
    if opts.file == "-" {
      read_stdin()
    } else {
      @fs.read_file_to_string(opts.file)
    }
  } catch {
    _ =>
      return value_problem(
        opts, "InputRead", "I could not read the JSON value input.", 1,
      )
  }
  let value = @validation.parse_json_value(text) catch {
    @validation.InvalidJson(offset, message) =>
      return value_problem(opts, "InvalidJson", message, 1, offset=Some(offset))
    @validation.DuplicateJsonKey(offset) =>
      return value_problem(
        opts,
        "DuplicateJsonKey",
        "I expected unique JSON object member names, but found a duplicate.",
        1,
        offset=Some(offset),
      )
    @validation.JsonInputLimit(offset, message) =>
      return value_problem(
        opts,
        "JsonInputLimit",
        message,
        1,
        offset=Some(offset),
      )
  }
  let result = prepared.validate_json(value)
  if opts.diagnostics == JsonFindings {
    println(@json.to_json(result).stringify())
  } else {
    for finding in result.findings {
      eprintln(
        "\{opts.file}\{finding.path.pointer()}: error[\{finding.code.to_string()}] \{finding.shape}: \{finding.message}",
      )
    }
  }
  if result.is_valid() {
    0
  } else {
    1
  }
}

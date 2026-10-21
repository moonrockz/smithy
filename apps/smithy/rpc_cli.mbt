///|
fn run_rpc_validation(
  opts : ValueOptions,
  version : @rpc.ProtocolVersion,
  assembled : @smithy.LoadResult,
) -> Int32 {
  if !validation_model_ok(opts, assembled) {
    return 1
  }
  let prepared = @rpc.PreparedService::prepare(
    assembled.model.unwrap(),
    opts.target,
    version,
    config=opts.config,
  ) catch {
    @rpc.InvalidContract(id, message) =>
      return value_problem(
        opts,
        "InvalidContract",
        id.to_string() + ": " + message,
        2,
        source=Some("--service"),
      )
    @validation.UnsupportedConstraint(id, message) =>
      return value_problem(
        opts,
        "UnsupportedConstraint",
        id.to_string() + ": " + message,
        2,
      )
    error =>
      return value_problem(opts, "InvalidConfiguration", error.to_string(), 2)
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
        opts, "InputRead", "I could not read the JSON-RPC message input.", 1,
      )
  }
  let result = prepared.validate_request(text)
  if opts.diagnostics == JsonFindings {
    println(@json.to_json(result).stringify())
  } else {
    for finding in result.findings {
      let severity = if finding.severity == @validation.Error {
        "error"
      } else {
        "advisory"
      }
      let offset = finding.offset.map(at => ":" + at.to_string()).unwrap_or("")
      eprintln(
        "\{opts.file}\{offset}\{finding.path.pointer()}: \{severity}[\{finding.code.to_string()}] \{finding.shape}: \{finding.message}",
      )
    }
  }
  if result.is_valid() {
    0
  } else {
    1
  }
}

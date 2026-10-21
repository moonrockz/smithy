///|
struct RpcOptions {
  response : Bool
  batch : Bool
  no_response : Bool
  request : String?
  context : @rpc.ResponseContext?
  legacy_errors : @rpc.LegacyErrorMode
}

///|
fn run_rpc_validation(
  opts : ValueOptions,
  version : @rpc.ProtocolVersion,
  rpc_opts : RpcOptions,
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
    if rpc_opts.no_response {
      ""
    } else if opts.file == "-" {
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
  let context = if rpc_opts.request is Some(file) {
    let request = try {
      if file == "-" {
        read_stdin()
      } else {
        @fs.read_file_to_string(file)
      }
    } catch {
      _ =>
        return value_problem(
          opts,
          "InputRead",
          "I could not read the original JSON-RPC request input.",
          1,
          source=Some(file),
        )
    }
    Some(@rpc.OriginalRequest(request))
  } else {
    rpc_opts.context
  }
  if rpc_opts.batch {
    if rpc_opts.response {
      let batch_context = context.map(c => {
        match c {
          @rpc.EnvelopeOnly => @rpc.BatchEnvelopeOnly
          @rpc.Method(name) => @rpc.BatchMethod(name)
          @rpc.Operation(id) => @rpc.BatchOperation(id)
          @rpc.OriginalRequest(text) => @rpc.OriginalBatch(text)
        }
      })
      let result = prepared.validate_response_batch(
        if rpc_opts.no_response {
          None
        } else {
          Some(text)
        },
        context=batch_context,
      )
      if opts.diagnostics == JsonFindings {
        println(@json.to_json(result).stringify())
      } else {
        print_rpc_findings(opts.file, result.findings)
      }
      return if result.is_valid() { 0 } else { 1 }
    }
    let result = prepared.validate_request_batch(text)
    if opts.diagnostics == JsonFindings {
      println(@json.to_json(result).stringify())
    } else {
      print_rpc_findings(opts.file, result.findings)
    }
    return if result.is_valid() { 0 } else { 1 }
  }
  if rpc_opts.response {
    let result = prepared.validate_response(
      text,
      context~,
      legacy_errors=rpc_opts.legacy_errors,
    )
    if opts.diagnostics == JsonFindings {
      println(@json.to_json(result).stringify())
    } else {
      print_rpc_findings(opts.file, result.findings)
    }
    return if result.is_valid() { 0 } else { 1 }
  }
  let result = prepared.validate_request(text)
  if opts.diagnostics == JsonFindings {
    println(@json.to_json(result).stringify())
  } else {
    print_rpc_findings(opts.file, result.findings)
  }
  if result.is_valid() {
    0
  } else {
    1
  }
}

///|
fn print_rpc_findings(file : String, findings : Array[@rpc.Finding]) -> Unit {
  for finding in findings {
    let severity = if finding.severity == @validation.Error {
      "error"
    } else {
      "advisory"
    }
    let offset = finding.offset.map(at => ":" + at.to_string()).unwrap_or("")
    eprintln(
      "\{file}\{offset}\{finding.path.pointer()}: \{severity}[\{finding.code.to_string()}] \{finding.shape}: \{finding.message}",
    )
  }
}

///|
/// What a profile-aware command selects: a node root and profile, or a versioned bundle.
priv enum CodecSelection {
  NodeSelection(@smithy.ShapeId, @codec_contract.ProfileId?)
  BundleSelection(@codec_contract.BundleId, @codec_contract.ProfileId?)
}

///|
priv struct CodecOptions {
  selection : CodecSelection
  /// Canonicalize instead of check.
  canonicalize : Bool
  /// The bundle profile that writes the output; default the reading profile.
  output_profile : @codec_contract.ProfileId?
  file : String
  output : String?
  diagnostics : ValueDiagnostics
}

///|
/// Parse the shared selection of `validate value` and `codec canonicalize`. The selection names declared
/// contracts only; it cannot change a profile's rules.
fn codec_selection(
  shape : String?,
  bundle : String?,
  profile : String?,
) -> CodecSelection raise CliError {
  let profile = match profile {
    None => None
    Some(text) =>
      Some(
        @codec_contract.ProfileId::parse(text) catch {
          _ =>
            raise CliError("expected a profile identifier after --profile", 2)
        },
      )
  }
  match (shape, bundle) {
    (Some(_), Some(_)) =>
      raise CliError("use either --shape or --bundle, not both", 2)
    (None, None) =>
      raise CliError(
        "select a root with --shape or a document bundle with --bundle", 2,
      )
    (Some(text), None) => {
      guard @smithy.ShapeId::parse(text) is Some(id) && id.member_name() is None else {
        raise CliError("expected an absolute Smithy shape ID after --shape", 2)
      }
      NodeSelection(id, profile)
    }
    (None, Some(text)) => {
      let id = @codec_contract.BundleId::parse(text) catch {
        _ => raise CliError("expected a bundle identifier after --bundle", 2)
      }
      BundleSelection(id, profile)
    }
  }
}

///|
/// The adapters that this host trusts. Model content names them; it cannot add one.
fn host_adapters() -> @codec.AdapterRegistry {
  @morphir.registry()
}

///|
fn codec_problem(
  opts : CodecOptions,
  code : String,
  message : String,
  status : Int32,
  source~ : String? = None,
) -> Int32 {
  let source = source.unwrap_or(opts.file)
  if opts.diagnostics == JsonFindings {
    println(
      Json::object({
        "valid": Json::boolean(false),
        "complete": Json::boolean(false),
        "findings": Json::array([
          Json::object({
            "code": Json::string(code),
            "severity": Json::string("error"),
            "message": Json::string(message),
            "source": Json::string(source),
            "path": Json::array([]),
            "pointer": Json::string(""),
          }),
        ]),
      }).stringify(),
    )
  } else {
    eprintln("\{source}: error[\{code}]: \{message}")
  }
  status
}

///|
fn report_codec_result(
  opts : CodecOptions,
  result : @codec.CodecResult,
) -> Int32 {
  if opts.diagnostics == JsonFindings {
    println(result.to_json().stringify())
  } else {
    for finding in result.findings {
      eprintln(
        "\{opts.file}\{finding.path.pointer()}: error[\{finding.code}] \{finding.shape}: \{finding.message}",
      )
    }
  }
  if result.is_valid() {
    0
  } else {
    1
  }
}

///|
/// A codec preparation or selection error is a configuration error: exit 2.
fn codec_preparation_problem(
  opts : CodecOptions,
  error : @codec_contract.ContractError,
) -> Int32 {
  codec_problem(
    opts,
    error.code(),
    error.message(),
    2,
    source=Some("--profile"),
  )
}

///|
priv enum PreparedSelection {
  PreparedNode(@codec.PreparedCodec)
  PreparedDocuments(@codec.PreparedBundle, @codec_contract.ProfileId?)
}

///|
fn run_codec(opts : CodecOptions, assembled : @smithy.LoadResult) -> Int32 {
  let model_opts : ValueOptions = {
    target: match opts.selection {
      NodeSelection(id, _) => id
      BundleSelection(_, _) =>
        @smithy.ShapeId::parse("smithy.api#Document").unwrap()
    },
    file: opts.file,
    diagnostics: opts.diagnostics,
    config: @validation.Config::new(),
    input_format: JsonInput,
    ion_index: None,
  }
  if !validation_model_ok(model_opts, assembled) {
    return 1
  }
  let model = assembled.model.unwrap()
  let limits = @codec.CodecLimits::default()
  let adapters = host_adapters()
  // Prepare before reading the value, so a configuration error leaves every input unread.
  let prepared = match opts.selection {
    NodeSelection(root, profile) => {
      if opts.output_profile is Some(_) {
        return codec_problem(
          opts,
          "InvalidSelection",
          "--output-profile needs --bundle; select the profile of a root with --profile.",
          2,
          source=Some("--output-profile"),
        )
      }
      PreparedNode(
        @codec.PreparedCodec::prepare(model, root, profile~, adapters~, limits~) catch {
          error => return codec_preparation_problem(opts, error)
        },
      )
    }
    BundleSelection(id, profile) =>
      PreparedDocuments(
        @codec.PreparedBundle::prepare(model, id, adapters~, limits~) catch {
          error => return codec_preparation_problem(opts, error)
        },
        profile,
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
      return codec_problem(
        opts, "InputRead", "I could not read the JSON value input.", 1,
      )
  }
  if !opts.canonicalize {
    let result = match prepared {
      PreparedNode(codec) => codec.check(text)
      PreparedDocuments(bundle, profile) => bundle.check(text, profile~)
    }
    return report_codec_result(opts, result)
  }
  let canonical = try {
    match prepared {
      PreparedNode(codec) => codec.canonicalize(text)
      PreparedDocuments(bundle, profile) =>
        bundle.canonicalize(text, profile~, output=opts.output_profile)
    }
  } catch {
    @codec.CodecFailure(result) => return report_codec_result(opts, result)
  }
  // The output exists only after the whole value is checked and written.
  match opts.output {
    Some(path) =>
      @fs.write_string_to_file(path, canonical + "\n") catch {
        _ =>
          return codec_problem(
            opts,
            "OutputWrite",
            "I could not write the canonical output.",
            1,
            source=Some(path),
          )
      }
    None => println(canonical)
  }
  0
}

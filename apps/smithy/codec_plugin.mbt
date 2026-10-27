///|
/// A loader that resolves the bundled smithy.rpc and smithy.serialization traits.
fn model_loader(protocol_tests~ : Bool = false) -> @smithy.Loader {
  @rpc.loader(protocol_tests~).add_builtin_idl(
    @codec_contract.trait_source,
    @codec_contract.trait_definitions(),
  )
}

///|
let json_codec_settings : Array[String] = [
  "action", "shape", "bundle", "profile", "outputProfile", "values",
]

///|
fn codec_build_error(message : String) -> @build.BuildError {
  @build.InvalidBuildConfig("jsonCodec: " + message)
}

///|
/// The `jsonCodec` build plugin. Its settings select a declared root or bundle and a profile, and name
/// the value files; they cannot change a profile's rules. `check` writes a report and fails the build on
/// an invalid value; `canonicalize` writes each value in canonical form. Inputs resolve relative to the
/// build configuration.
fn json_codec_plugin(
  base : String,
  model : @smithy.Model,
  settings : Json,
  read~ : (String) -> String raise = path => @fs.read_file_to_string(path),
) -> Map[String, String] raise @build.BuildError {
  guard settings is Object(fields) else {
    raise codec_build_error("settings must be an object")
  }
  for name, _ in fields {
    if !json_codec_settings.contains(name) {
      raise codec_build_error(
        "unknown setting `\{name}`; settings select declared profiles and cannot change their representation rules",
      )
    }
  }
  let text = fn(name : String) raise @build.BuildError {
    match fields.get(name) {
      None => None
      Some(String(value)) => Some(value)
      _ => raise codec_build_error("setting `\{name}` must be a string")
    }
  }
  let canonicalize = match text("action") {
    Some("check") => false
    Some("canonicalize") => true
    _ =>
      raise codec_build_error("setting `action` must be check or canonicalize")
  }
  let (shape, bundle, profile) = (
    text("shape"),
    text("bundle"),
    text("profile"),
  )
  let selection = codec_selection(shape, bundle, profile) catch {
    CliError(message, _) => raise codec_build_error(message)
  }
  let output_profile = match text("outputProfile") {
    None => None
    Some(value) =>
      Some(
        @codec_contract.ProfileId::parse(value) catch {
          _ =>
            raise codec_build_error(
              "expected a profile identifier in `outputProfile`",
            )
        },
      )
  }
  guard fields.get("values") is Some(Array(entries)) && !entries.is_empty() else {
    raise codec_build_error("setting `values` must list at least one value")
  }
  let values : Array[(String, String)] = []
  for entry in entries {
    guard entry is Object(value) && value.get("input") is Some(String(input)) else {
      raise codec_build_error("each value needs an `input` path")
    }
    for name, _ in value {
      if name != "input" && name != "output" {
        raise codec_build_error("unknown value setting `\{name}`")
      }
    }
    let input_path : @path.Path = input
    if input_path.is_absolute() ||
      !build_path_contains(base, build_path(base, input)) {
      raise codec_build_error(
        "value `\{input}` must be a path inside the build configuration directory",
      )
    }
    let output = match value.get("output") {
      None => input_path.basename().to_owned()
      Some(String(name)) => name
      Some(_) => raise codec_build_error("value `output` must be a string")
    }
    values.push((input, output))
  }
  let limits = @codec.CodecLimits::default()
  let adapters = host_adapters()
  let run : (String) -> Result[String, @codec.CodecResult] = match selection {
    NodeSelection(root, profile) => {
      if output_profile is Some(_) {
        raise codec_build_error("`outputProfile` needs `bundle`")
      }
      let codec = @codec.PreparedCodec::prepare(
        model,
        root,
        profile~,
        adapters~,
        limits~,
      ) catch {
        error => raise codec_build_error(error.message())
      }
      fn(input) {
        if canonicalize {
          let out = codec.canonicalize(input) catch {
            @codec.CodecFailure(result) => return Err(result)
          }
          Ok(out)
        } else {
          let result = codec.check(input)
          if result.is_valid() {
            Ok("")
          } else {
            Err(result)
          }
        }
      }
    }
    BundleSelection(id, profile) => {
      let bundle = @codec.PreparedBundle::prepare(model, id, adapters~, limits~) catch {
        error => raise codec_build_error(error.message())
      }
      fn(input) {
        if canonicalize {
          let out = bundle.canonicalize(input, profile~, output=output_profile) catch {
            @codec.CodecFailure(result) => return Err(result)
          }
          Ok(out)
        } else {
          let result = bundle.check(input, profile~)
          if result.is_valid() {
            Ok("")
          } else {
            Err(result)
          }
        }
      }
    }
  }
  let files : Map[String, String] = Map([])
  let report : Array[Json] = []
  let failures : Array[String] = []
  for entry in values {
    let (input, output) = entry
    let content = read(build_path(base, input)) catch {
      _ => raise codec_build_error("cannot read value `\{input}`")
    }
    match run(content) {
      Ok(canonical) => {
        report.push(
          Json::object({
            "input": Json::string(input),
            "valid": Json::boolean(true),
          }),
        )
        if canonicalize {
          if files.contains(output) {
            raise codec_build_error("two values write the output `\{output}`")
          }
          files[output] = canonical + "\n"
        }
      }
      Err(result) => {
        report.push(
          Json::object({
            "input": Json::string(input),
            "result": result.to_json(),
          }),
        )
        for finding in result.findings {
          failures.push(
            "\{input}\{finding.path.pointer()}: error[\{finding.code}] \{finding.message}",
          )
        }
        if result.findings.is_empty() {
          failures.push("\{input}: incomplete")
        }
      }
    }
  }
  if !failures.is_empty() {
    raise codec_build_error("invalid values:\n" + failures.join("\n"))
  }
  if !canonicalize {
    files["json-codec-check.json"] = Json::array(report).stringify(indent=2) +
      "\n"
  }
  files
}

///|
/// Generators and exporters keep their standard contracts. A request for a serialization profile is
/// refused rather than answered with an object-only contract under that profile's name.
fn refuse_profile(
  name : String,
  plugin : (@smithy.Model, Json) -> Map[String, String] raise @build.BuildError,
) -> (@smithy.Model, Json) -> Map[String, String] raise @build.BuildError {
  (model, settings) => {
    if settings is Object(fields) {
      for key in ["profile", "serializationProfile", "jsonProfile", "bundle"] {
        if fields.contains(key) {
          raise @build.InvalidBuildConfig(
            "\{name} does not support serialization profiles; remove `\{key}`. Use the jsonCodec plugin to check or canonicalize profile JSON.",
          )
        }
      }
    }
    plugin(model, settings)
  }
}

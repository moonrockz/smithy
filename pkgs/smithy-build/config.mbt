///|
pub(all) suberror BuildError {
  InvalidBuildConfig(String)
} derive(Eq, Debug)

///|
pub(all) struct TransformConfig {
  name : String
  args : Json
} derive(Eq, Debug)

///|
pub(all) struct ProjectionConfig {
  name : String
  is_abstract : Bool
  transforms : Array[TransformConfig]
  plugins : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct BuildConfig {
  version : String
  sources : Array[String]
  imports : Array[String]
  output_directory : String
  projections : Array[ProjectionConfig]
  plugins : Map[String, Json]
  ignore_missing_plugins : Bool
} derive(Eq, Debug)

///|
fn config_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn config_string(value : Json, key : String) -> String? {
  match config_field(value, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn config_bool(value : Json, key : String) -> Bool {
  config_field(value, key) == Some(Json::boolean(true))
}

///|
fn config_strings(value : Json, key : String) -> Array[String] raise BuildError {
  match config_field(value, key) {
    None => []
    Some(Array(values)) => {
      let result : Array[String] = []
      for entry in values {
        guard entry is String(text) else {
          raise InvalidBuildConfig(
            "Expected `" + key + "` to contain only strings",
          )
        }
        result.push(text)
      }
      result
    }
    _ => raise InvalidBuildConfig("Expected `" + key + "` to be an array")
  }
}

///|
fn config_object(
  value : Json,
  key : String,
) -> Map[String, Json] raise BuildError {
  match config_field(value, key) {
    None => Map([])
    Some(Object(fields)) => fields
    _ => raise InvalidBuildConfig("Expected `" + key + "` to be an object")
  }
}

///|
fn strip_json_comments(source : String) -> String raise BuildError {
  let chars = source.iter().to_array()
  let out = StringBuilder()
  let mut i = 0
  let mut quoted = false
  let mut escaped = false
  while i < chars.length() {
    let c = chars[i]
    if quoted {
      out.write_char(c)
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
      i += 1
    } else if c == '"' {
      quoted = true
      out.write_char(c)
      i += 1
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '/' {
      i += 2
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
    } else if c == '/' && i + 1 < chars.length() && chars[i + 1] == '*' {
      i += 2
      let mut closed = false
      while i + 1 < chars.length() {
        if chars[i] == '*' && chars[i + 1] == '/' {
          i += 2
          closed = true
          break
        }
        if chars[i] == '\n' {
          out.write_char('\n')
        }
        i += 1
      }
      if !closed {
        raise InvalidBuildConfig(
          "Unterminated block comment in smithy-build.json",
        )
      }
    } else {
      out.write_char(c)
      i += 1
    }
  }
  out.to_string()
}

///|
pub fn BuildConfig::parse(source : String) -> BuildConfig raise BuildError {
  let clean = strip_json_comments(source)
  let document = @json.parse(clean) catch {
    _ => raise InvalidBuildConfig("Invalid smithy-build.json")
  }
  guard document is Object(_) else {
    raise InvalidBuildConfig("Expected a JSON object in smithy-build.json")
  }
  guard config_string(document, "version") is Some(version) &&
    (version == "1.0" || version == "2.0") else {
    raise InvalidBuildConfig("Expected Smithy build version 1.0 or 2.0")
  }
  let maven = config_object(document, "maven")
  if maven.get("dependencies") is Some(Array(deps)) && !deps.is_empty() {
    raise InvalidBuildConfig(
      "Maven dependencies are not supported; use local imports",
    )
  }
  let projections : Array[ProjectionConfig] = []
  for name, value in config_object(document, "projections") {
    guard value is Object(_) else {
      raise InvalidBuildConfig(
        "Expected projection `" + name + "` to be an object",
      )
    }
    let transforms : Array[TransformConfig] = []
    match config_field(value, "transforms") {
      None => ()
      Some(Array(entries)) =>
        for entry in entries {
          guard config_string(entry, "name") is Some(transform_name) else {
            raise InvalidBuildConfig(
              "Expected a transform name in projection `" + name + "`",
            )
          }
          transforms.push({
            name: transform_name,
            args: config_field(entry, "args").unwrap_or(Json::object(Map([]))),
          })
        }
      _ =>
        raise InvalidBuildConfig(
          "Expected transforms array in projection `" + name + "`",
        )
    }
    projections.push({
      name,
      is_abstract: config_bool(value, "abstract"),
      transforms,
      plugins: config_object(value, "plugins"),
    })
  }
  {
    version,
    sources: config_strings(document, "sources"),
    imports: config_strings(document, "imports"),
    output_directory: config_string(document, "outputDirectory").unwrap_or(
      "build/smithy",
    ),
    projections,
    plugins: config_object(document, "plugins"),
    ignore_missing_plugins: config_bool(document, "ignoreMissingPlugins"),
  }
}

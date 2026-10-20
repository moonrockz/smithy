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
  imports : Array[BuildInput]
  transforms : Array[TransformConfig]
  plugins : Map[String, Json]
} derive(Eq, Debug)

///|
pub(all) struct BuildConfig {
  version : String
  sources : Array[BuildInput]
  imports : Array[BuildInput]
  cache_directory : @resources.CacheDirectory
  offline : Bool
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
fn config_bool(value : Json, key : String) -> Bool raise BuildError {
  match config_field(value, key) {
    None => false
    Some(True) => true
    Some(False) => false
    _ => raise InvalidBuildConfig("Expected `" + key + "` to be a boolean")
  }
}

///|
fn config_optional_string(
  value : Json,
  key : String,
) -> String? raise BuildError {
  match config_field(value, key) {
    None => None
    Some(String(text)) => Some(text)
    _ => raise InvalidBuildConfig("Expected `" + key + "` to be a string")
  }
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
fn config_plugins(value : Json) -> Map[String, Json] raise BuildError {
  let plugins = config_object(value, "plugins")
  for name, settings in plugins {
    guard settings is Object(_) else {
      raise InvalidBuildConfig(
        "Expected settings for plugin `" + name + "` to be an object",
      )
    }
  }
  plugins
}

///|
fn config_validate_maven(document : Json) -> Unit raise BuildError {
  let maven = Json::object(config_object(document, "maven"))
  let dependencies = config_strings(maven, "dependencies")
  match config_field(maven, "repositories") {
    None => ()
    Some(Array(repositories)) =>
      for repository in repositories {
        guard repository is Object(_) else {
          raise InvalidBuildConfig("Expected a Maven repository object")
        }
        guard config_optional_string(repository, "url") is Some(_) else {
          raise InvalidBuildConfig("Expected a Maven repository `url`")
        }
        for key in ["id", "proxyHost", "httpCredentials", "proxyCredentials"] {
          let value = config_optional_string(repository, key)
          if (key == "httpCredentials" || key == "proxyCredentials") &&
            value is Some(credentials) {
            guard credentials.find(":") is Some(position) &&
              position > 0 &&
              position < credentials.length() - 1 else {
              raise InvalidBuildConfig(
                "Expected Maven `" + key + "` in the format user:pass",
              )
            }
          }
        }
      }
    _ =>
      raise InvalidBuildConfig("Expected Maven `repositories` to be an array")
  }
  if !dependencies.is_empty() {
    raise InvalidBuildConfig(
      "Maven dependencies are not supported; use local imports",
    )
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
fn config_expand_string(
  text : String,
  environment : Map[String, String],
) -> String raise BuildError {
  let output = StringBuilder()
  let mut copied = 0
  let mut offset = 0
  while offset < text.length() {
    // Match the reference regex, which consumes the preceding character.
    let start = if offset == 0 && text.has_prefix("${") {
      0
    } else if offset + 2 < text.length() &&
      text[offset] != 92 &&
      text[offset + 1] == 36 &&
      text[offset + 2] == 123 {
      offset + 1
    } else {
      offset += 1
      continue
    }
    let variable_start = start + 2
    guard text[variable_start:].find("}") is Some(end) && end > 0 else {
      offset += 1
      continue
    }
    let variable = text[variable_start:variable_start + end].to_owned()
    guard environment.get(variable) is Some(replacement) else {
      raise InvalidBuildConfig(
        "Unable to expand variable `" +
        variable +
        "` to an environment variable",
      )
    }
    output.write_string(text[copied:start].to_owned())
    output.write_string(replacement)
    offset = variable_start + end + 1
    copied = offset
  }
  output.write_string(text[copied:].to_owned())
  output
  .to_string()
  .split("\\$")
  .map(part => part.to_owned())
  .to_array()
  .join("$")
}

///|
fn config_expand(
  value : Json,
  environment : Map[String, String],
) -> Json raise BuildError {
  match value {
    String(text) => Json::string(config_expand_string(text, environment))
    Array(entries) =>
      Json::array(entries.map(value => config_expand(value, environment)))
    Object(fields) => {
      let expanded : Map[String, Json] = Map([])
      for key, value in fields {
        expanded[config_expand_string(key, environment)] = config_expand(
          value, environment,
        )
      }
      Json::object(expanded)
    }
    _ => value
  }
}

///|
pub fn BuildConfig::parse(
  source : String,
  environment~ : Map[String, String] = Map([]),
) -> BuildConfig raise BuildError {
  let clean = strip_json_comments(source)
  let document = @json.parse(clean) catch {
    _ => raise InvalidBuildConfig("Invalid smithy-build.json")
  }
  let document = if source.contains("${") {
    config_expand(document, environment)
  } else {
    document
  }
  guard document is Object(_) else {
    raise InvalidBuildConfig("Expected a JSON object in smithy-build.json")
  }
  guard config_optional_string(document, "version") is Some(version) &&
    (version == "1.0" || version == "2.0") else {
    raise InvalidBuildConfig("Expected Smithy build version 1.0 or 2.0")
  }
  config_validate_maven(document)
  let output_directory = config_optional_string(document, "outputDirectory").unwrap_or(
    "build/smithy",
  )
  if output_directory.is_empty() {
    raise InvalidBuildConfig("outputDirectory must be set to a valid directory")
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
          guard entry is Object(_) else {
            raise InvalidBuildConfig(
              "Expected a transform object in projection `" + name + "`",
            )
          }
          guard config_optional_string(entry, "name") is Some(transform_name) else {
            raise InvalidBuildConfig(
              "Expected a transform name in projection `" + name + "`",
            )
          }
          let args = config_field(entry, "args").unwrap_or(
            Json::object(Map([])),
          )
          guard args is Object(_) || args is Array(_) else {
            raise InvalidBuildConfig(
              "Expected transform `args` to be an object or array",
            )
          }
          transforms.push({ name: transform_name, args, })
        }
      _ =>
        raise InvalidBuildConfig(
          "Expected transforms array in projection `" + name + "`",
        )
    }
    let is_abstract = config_bool(value, "abstract")
    let imports = config_inputs(value, "imports")
    let plugins = config_plugins(value)
    if is_abstract && (!imports.is_empty() || !plugins.is_empty()) {
      raise InvalidBuildConfig(
        "Abstract projections must not define plugins or imports",
      )
    }
    projections.push({ name, is_abstract, imports, transforms, plugins, })
  }
  {
    version,
    sources: config_inputs(document, "sources"),
    imports: config_inputs(document, "imports"),
    cache_directory: config_cache_directory(document),
    offline: config_bool(document, "offline"),
    output_directory,
    projections,
    plugins: config_plugins(document),
    ignore_missing_plugins: config_bool(document, "ignoreMissingPlugins"),
  }
}

///|
fn config_cache_directory(
  document : Json,
) -> @resources.CacheDirectory raise BuildError {
  let text = config_optional_string(document, "cacheDirectory").unwrap_or(
    ".smithy/cache",
  )
  guard @resources.CacheDirectory::parse(text) is Some(location) else {
    raise InvalidBuildConfig(
      "Expected `cacheDirectory` to be a portable filesystem directory path",
    )
  }
  location
}

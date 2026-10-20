///|
/// Legacy local discovery or explicitly selected resources in a local container.
pub(all) enum BuildInput {
  Remote(@resources.PublicArchive, @resources.Selection)
  Local(@resources.RepositoryLocation)
  Selected(@resources.RepositoryLocation, @resources.Selection)
} derive(Eq, Debug)

///|
pub fn BuildInput::from_path(path : String) -> BuildInput raise BuildError {
  guard @resources.RepositoryLocation::parse(path) is Some(location) else {
    raise InvalidBuildConfig("Expected a nonempty local input location")
  }
  Local(location)
}

///|
pub fn BuildInput::location(self : BuildInput) -> @resources.RepositoryLocation {
  match self {
    Remote(archive, _) =>
      @resources.RepositoryLocation::parse(archive.url.to_string()).unwrap()
    Local(location) | Selected(location, _) => location
  }
}

///|
pub fn BuildInput::with_location(
  self : BuildInput,
  location : @resources.RepositoryLocation,
) -> BuildInput raise BuildError {
  match self {
    Remote(archive, selection) => {
      guard @resources.HttpUrl::parse(location.to_string()) is Some(url) else {
        raise InvalidBuildConfig(
          "Expected an absolute credential-free HTTP(S) URL",
        )
      }
      Remote({ ..archive, url, }, selection)
    }
    Local(_) => Local(location)
    Selected(_, selection) => Selected(location, selection)
  }
}

///|
pub fn BuildInput::to_json(self : BuildInput) -> Json {
  match self {
    Remote(archive, selection) => {
      let json = Selected(self.location(), selection).to_json()
      guard json is Object(fields) else { abort("selection serialization") }
      ignore(fields.remove("path"))
      fields["url"] = Json::string(archive.url.to_string())
      fields["format"] = Json::string(
        match archive.format {
          @resources.Zip => "zip"
          @resources.Tar => "tar"
          @resources.Tgz => "tgz"
        },
      )
      if archive.expected_digest is Some(digest) {
        fields["digest"] = Json::string(digest.to_string())
      }
      Json::object(fields)
    }
    Local(location) => Json::string(location.to_string())
    Selected(location, selection) => {
      let paths = []
      let globs = []
      for selector in selection.selectors() {
        match selector {
          @resources.Exact(path) => paths.push(Json::string(path.to_string()))
          @resources.Named(path, name) =>
            paths.push(
              Json::object({
                "path": Json::string(path.to_string()),
                "name": Json::string(name.to_string()),
              }),
            )
          @resources.Matching(pattern) =>
            globs.push(Json::string(pattern.to_string()))
        }
      }
      Json::object({
        "path": Json::string(location.to_string()),
        "root": Json::string(selection.root.to_string()),
        "paths": Json::array(paths),
        "globs": Json::array(globs),
      })
    }
  }
}

///|
fn parse_entry_path(text : String) -> @resources.EntryPath raise BuildError {
  @resources.EntryPath::parse(text).unwrap_or_else(() => {
    raise InvalidBuildConfig("Unsafe resource path `" + text + "`")
  })
}

///|
fn config_input(value : Json) -> BuildInput raise BuildError {
  if value is String(path) {
    return BuildInput::from_path(path)
  }
  guard value is Object(fields) else {
    raise InvalidBuildConfig(
      "Expected a local input string or resource selection object",
    )
  }
  let remote = fields.contains("url")
  let allowed = if remote {
    ["url", "format", "digest", "root", "paths", "globs"]
  } else {
    ["path", "root", "paths", "globs"]
  }
  for key, _ in fields {
    if !allowed.contains(key) {
      raise InvalidBuildConfig("Unknown resource selection field `" + key + "`")
    }
  }
  guard config_optional_string(value, if remote { "url" } else { "path" })
    is Some(path) &&
    @resources.RepositoryLocation::parse(path) is Some(location) else {
    raise InvalidBuildConfig("Expected a resource selection `path`")
  }
  guard config_optional_string(value, "root") is Some(root) &&
    @resources.ResourceRoot::parse(root) is Some(root) else {
    raise InvalidBuildConfig(
      "Expected a safe resource `root`, using `.` for the container root",
    )
  }
  let selectors = []
  match config_field(value, "paths") {
    None => ()
    Some(Array(paths)) =>
      for path in paths {
        match path {
          String(path) =>
            selectors.push(@resources.Exact(parse_entry_path(path)))
          Object(fields) => {
            if fields.length() != 2 {
              raise InvalidBuildConfig(
                "A named resource path requires only `path` and `name`",
              )
            }
            guard config_optional_string(path, "path") is Some(entry) &&
              config_optional_string(path, "name") is Some(name) &&
              @resources.ResourceName::parse(name) is Some(name) else {
              raise InvalidBuildConfig(
                "Expected a safe named resource `path` and `name`",
              )
            }
            selectors.push(@resources.Named(parse_entry_path(entry), name))
          }
          _ =>
            raise InvalidBuildConfig(
              "Expected resource paths to be strings or named path objects",
            )
        }
      }
    _ => raise InvalidBuildConfig("Expected resource `paths` to be an array")
  }
  for glob in config_strings(value, "globs") {
    guard @resources.GlobPattern::parse(glob) is Some(pattern) else {
      raise InvalidBuildConfig("Invalid resource glob `" + glob + "`")
    }
    selectors.push(@resources.Matching(pattern))
  }
  guard @resources.Selection::new(root, selectors) is Some(selection) else {
    raise InvalidBuildConfig(
      "A resource selection requires between 1 and 256 paths or globs",
    )
  }
  if remote {
    guard @resources.HttpUrl::parse(path) is Some(url) else {
      raise InvalidBuildConfig(
        "Expected an absolute credential-free HTTP(S) URL without a fragment",
      )
    }
    let format = match
      config_optional_string(value, "format").unwrap_or("zip") {
      "zip" | "jar" => @resources.Zip
      "tar" => @resources.Tar
      "tgz" | "tar.gz" => @resources.Tgz
      _ =>
        raise InvalidBuildConfig(
          "Expected URL archive format zip, jar, tar, tgz or tar.gz",
        )
    }
    let expected_digest = match config_optional_string(value, "digest") {
      None => None
      Some(text) => {
        guard @resources.ContentDigest::parse(text) is Some(digest) else {
          raise InvalidBuildConfig(
            "Expected digest sha256: followed by 64 hexadecimal digits",
          )
        }
        Some(digest)
      }
    }
    Remote({ url, format, expected_digest, }, selection)
  } else {
    Selected(location, selection)
  }
}

///|
fn config_inputs(
  value : Json,
  key : String,
) -> Array[BuildInput] raise BuildError {
  match config_field(value, key) {
    None => []
    Some(Array(values)) => values.map(config_input)
    _ => raise InvalidBuildConfig("Expected `" + key + "` to be an array")
  }
}

///|
/// Smithy accepts only selected model resources; generic selectors stay format-independent.
pub fn selected_models(
  tree : @resources.EntryTree,
  selection : @resources.Selection,
) -> Array[@resources.Resource] raise BuildError {
  let loaded = @resources.select_resources(tree, selection) catch {
    @resources.ResourceError(code, at, message) =>
      raise InvalidBuildConfig(
        "Could not load resource `" +
        at.to_string() +
        "` [" +
        code.to_string() +
        "]: " +
        message,
      )
  }
  for resource in loaded {
    let path = resource.path.to_string()
    let name = resource.name.to_string()
    if (!path.has_suffix(".smithy") && !path.has_suffix(".json")) ||
      path.has_suffix(".smithy") != name.has_suffix(".smithy") ||
      path.has_suffix(".json") != name.has_suffix(".json") {
      raise InvalidBuildConfig(
        "Selected Smithy resource `" +
        resource.provenance.to_string() +
        "` must retain its .smithy or .json format in logical name `" +
        name +
        "`",
      )
    }
  }
  loaded
}

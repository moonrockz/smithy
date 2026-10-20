///|
/// Discover models listed by META-INF/smithy/manifest in a local JAR or ZIP.
/// Keys are relative to META-INF/smithy; no archive files are extracted.
pub fn archive_models(
  data : Bytes,
  origin : String,
) -> Map[String, String] raise BuildError {
  guard @resources.Location::parse(origin) is Some(location) else {
    raise archive_error(origin, "Expected a nonempty archive location")
  }
  let tree = @resources.EntryTree::zip(data, location) catch {
    @resources.ResourceError(_, at, message) =>
      raise archive_error(at.to_string(), message)
  }
  let out : Map[String, String] = Map([])
  for resource in declared_models(tree) {
    out[resource.name.to_string()] = resource.text() catch {
      @resources.ResourceError(_, at, message) =>
        raise archive_error(at.to_string(), message)
    }
  }
  out
}

///|
/// Discover the Smithy manifest in any resource entry tree. Manifest duplicates
/// are ignored, as in archive_models; other resource consumers reject aliases.
pub fn declared_models(
  tree : @resources.EntryTree,
) -> Array[@resources.Resource] raise BuildError {
  let origin = tree.provenance().to_string()
  guard tree.contains(
    @resources.EntryPath::parse("META-INF/smithy/manifest").unwrap(),
  ) else {
    return []
  }
  let manifest = (tree.text(
      @resources.EntryPath::parse("META-INF/smithy/manifest").unwrap(),
    ) catch {
      @resources.ResourceError(_, at, message) =>
        raise archive_error(at.to_string(), message)
    })
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let seen : Set[String] = Set([])
  let declarations = []
  for line in manifest.split("\n") {
    let name = line.to_owned()
    if name == "" || name.has_prefix("#") {
      continue
    }
    if !archive_model_path(name) {
      raise archive_error(origin, "Invalid Smithy manifest path `" + name + "`")
    }
    if seen.contains(name) {
      continue
    }
    if !name.has_suffix(".smithy") && !name.has_suffix(".json") {
      raise archive_error(
        origin,
        "Unrecognized model file `" + name + "` in Smithy manifest",
      )
    }
    if !tree.contains(
        @resources.EntryPath::parse("META-INF/smithy/" + name).unwrap(),
      ) {
      raise archive_error(
        origin,
        "Smithy manifest references missing entry `" + name + "`",
      )
    }
    seen.add(name)
    declarations.push(@resources.Declaration::{
      name: @resources.ResourceName::parse(name).unwrap(),
      path: @resources.EntryPath::parse("META-INF/smithy/" + name).unwrap(),
    })
  }
  @resources.load_resources(tree, declarations) catch {
    @resources.ResourceError(_, at, message) =>
      raise archive_error(at.to_string(), message)
  }
}

///|
fn archive_error(origin : String, message : String) -> BuildError {
  InvalidBuildConfig(
    "Could not read Smithy archive `" + origin + "`: " + message,
  )
}

///|
fn archive_model_path(name : String) -> Bool {
  if name.has_prefix("/") || name.has_suffix("/") {
    return false
  }
  if name
    .iter()
    .any(c => {
      c.to_int() < 32 ||
      c.to_int() == 127 ||
      "\\?%*:|\"'><# ".contains(c.to_string())
    }) {
    return false
  }
  name.split("/").all(part => part != "" && part != "." && part != "..")
}

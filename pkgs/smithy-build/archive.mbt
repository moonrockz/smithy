///|
/// Discover models listed by META-INF/smithy/manifest in a local JAR or ZIP.
/// Keys are relative to META-INF/smithy; no archive files are extracted.
pub fn archive_models(
  data : Bytes,
  origin : String,
) -> Map[String, String] raise BuildError {
  let tree = @resources.EntryTree::zip(data, origin) catch {
    @resources.ResourceError(_, at, message) => raise archive_error(at, message)
  }
  let out : Map[String, String] = Map([])
  for resource in declared_models(tree) {
    out[resource.name] = resource.text() catch {
      @resources.ResourceError(_, at, message) =>
        raise archive_error(at, message)
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
  let origin = tree.provenance()
  guard tree.contains("META-INF/smithy/manifest") else { return [] }
  let manifest = (tree.text("META-INF/smithy/manifest") catch {
      @resources.ResourceError(_, at, message) =>
        raise archive_error(at, message)
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
    if !tree.contains("META-INF/smithy/" + name) {
      raise archive_error(
        origin,
        "Smithy manifest references missing entry `" + name + "`",
      )
    }
    seen.add(name)
    declarations.push(@resources.Declaration::{
      name,
      path: "META-INF/smithy/" + name,
    })
  }
  @resources.load_resources(tree, declarations) catch {
    @resources.ResourceError(_, at, message) => raise archive_error(at, message)
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

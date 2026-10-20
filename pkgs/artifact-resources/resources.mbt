///|
/// Stable code, complete origin and detail. Hosts can render these separately.
pub(all) suberror ResourceError {
  ResourceError(ResourceCode, Provenance, String)
} derive(Debug)

///|
pub(all) struct Limits {
  max_archive_bytes : Int32
  max_entries : Int32
  max_entry_bytes : Int32
  max_match_steps : Int32
  max_total_bytes : Int32
}

///|
pub fn Limits::new(
  max_archive_bytes~ : Int32 = 67108864,
  max_entries~ : Int32 = 10000,
  max_entry_bytes~ : Int32 = 16777216,
  max_total_bytes~ : Int32 = 268435456,
  max_match_steps~ : Int32 = 16000000,
) -> Limits {
  {
    max_archive_bytes,
    max_entries,
    max_entry_bytes,
    max_total_bytes,
    max_match_steps,
  }
}

///|
pub struct EntryTree {
  origin : Location
  priv provenance : Provenance
  priv paths : Array[EntryPath]
  priv members : Set[String]
  priv read_entry : (EntryPath) -> Bytes raise ResourceError
  priv limits : Limits
  priv locate_entry : (EntryPath) -> Location
  digest : ContentDigest?
}

///|
/// Validate portable, relative file paths without normalizing distinct names.
pub fn valid_path(path : String) -> Bool {
  !path.is_empty() &&
  !path
  .iter()
  .any(c => {
    c.to_int() < 32 ||
    c.to_int() == 127 ||
    "\\:?#%*|\"<>".contains(c.to_string())
  }) &&
  path.split("/").all(p => p != "" && p != "." && p != "..")
}

///|
fn check_limits(limits : Limits, origin : Location) -> Unit raise ResourceError {
  if limits.max_archive_bytes < 0 ||
    limits.max_entries < 0 ||
    limits.max_entry_bytes < 0 ||
    limits.max_total_bytes < 0 ||
    limits.max_match_steps < 0 {
    raise ResourceError(
      InvalidLimits,
      Provenance::new(origin),
      "Resource limits must be nonnegative",
    )
  }
}

///|
/// A host-supplied directory reader. Paths are copied and validated before use.
/// The callback receives only listed relative paths and must return file bytes.
pub fn EntryTree::directory(
  paths : Array[EntryPath],
  read : (EntryPath) -> Bytes raise ResourceError,
  origin : Location,
  limits~ : Limits = Limits::new(),
  style~ : PathStyle = Slash,
  directories~ : Array[EntryPath] = [],
) -> EntryTree raise ResourceError {
  check_limits(limits, origin)
  if paths.length() > limits.max_entries ||
    directories.length() > limits.max_entries - paths.length() {
    raise ResourceError(
      ResourceLimit,
      Provenance::new(origin),
      "Too many entries",
    )
  }
  let seen : Set[EntryPath] = Set([])
  for path in paths {
    if seen.contains(path) {
      raise ResourceError(
        DuplicateEntry,
        Provenance::new(origin),
        "Duplicate entry `" + path.to_string() + "`",
      )
    }
    seen.add(path)
  }
  let members = Set(paths.map(path => path.to_string()))
  for directory in directories {
    members.add(directory.to_string() + "/")
  }
  let paths = paths.copy()
  paths.sort()
  {
    origin,
    provenance: Provenance::new(origin),
    paths,
    members,
    read_entry: read,
    limits,
    locate_entry: path => origin.directory_entry(path, style~),
    digest: None,
  }
}

///|
pub fn EntryTree::entries(self : EntryTree) -> Array[EntryPath] {
  self.paths.copy()
}

///|
pub fn EntryTree::contains(self : EntryTree, path : EntryPath) -> Bool {
  self.members.contains(path.to_string())
}

///|
pub fn EntryTree::entry_origin(self : EntryTree, path : EntryPath) -> Location {
  (self.locate_entry)(path)
}

///|
pub fn EntryTree::read(
  self : EntryTree,
  path : EntryPath,
) -> Bytes raise ResourceError {
  if !self.contains(path) {
    raise ResourceError(
      MissingResource,
      self.entry_provenance(path),
      "Missing entry `" + path.to_string() + "`",
    )
  }
  let bytes = (self.read_entry)(path) catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, self.contextualize(at), message)
  }
  if bytes.length() > self.limits.max_entry_bytes ||
    bytes.length() > self.limits.max_total_bytes {
    raise ResourceError(
      ResourceLimit,
      self.entry_provenance(path),
      "Entry exceeds byte limit",
    )
  }
  bytes
}

///|
pub fn EntryTree::text(
  self : EntryTree,
  path : EntryPath,
) -> String raise ResourceError {
  let bytes = self.read(path)
  @utf8.decode(bytes) catch {
    _ =>
      raise ResourceError(
        InvalidUtf8,
        self.entry_provenance(path),
        "Invalid UTF-8 in `" + path.to_string() + "`",
      )
  }
}

///|
/// Logical names are independent of physical paths inside the container.
pub(all) struct Declaration {
  name : ResourceName
  path : EntryPath
} derive(Debug, Eq)

///|
pub struct Resource {
  name : ResourceName
  path : EntryPath
  origin : Location
  provenance : Provenance
  bytes : Bytes
}

///|
pub fn Resource::text(self : Resource) -> String raise ResourceError {
  @utf8.decode(self.bytes) catch {
    _ =>
      raise ResourceError(
        InvalidUtf8,
        self.provenance,
        "Invalid UTF-8 in `" + self.path.to_string() + "`",
      )
  }
}

///|
/// Load declarations in order. Duplicate logical names are always an error.
pub fn load_resources(
  tree : EntryTree,
  declarations : Array[Declaration],
) -> Array[Resource] raise ResourceError {
  if declarations.length() > tree.limits.max_entries {
    raise ResourceError(
      ResourceLimit,
      tree.provenance,
      "Too many declared resources",
    )
  }
  let seen : Set[ResourceName] = Set([])
  let resources = []
  let mut total = 0
  for declaration in declarations {
    if seen.contains(declaration.name) {
      raise ResourceError(
        DuplicateResource,
        tree.provenance,
        "Duplicate logical resource `" + declaration.name.to_string() + "`",
      )
    }
    seen.add(declaration.name)
    let bytes = tree.read(declaration.path)
    if bytes.length() > tree.limits.max_total_bytes - total {
      raise ResourceError(
        ResourceLimit,
        tree.provenance,
        "Resources exceed total byte limit",
      )
    }
    total += bytes.length()
    resources.push({
      name: declaration.name,
      path: declaration.path,
      origin: tree.entry_origin(declaration.path),
      provenance: tree.entry_provenance(declaration.path),
      bytes,
    })
  }
  resources
}

///|
/// The diagnostic chain, including repository and resolved identity after resolution.
pub fn EntryTree::provenance(self : EntryTree) -> Provenance {
  self.provenance
}

///|
pub fn EntryTree::entry_provenance(
  self : EntryTree,
  path : EntryPath,
) -> Provenance {
  self.provenance.at(self.entry_origin(path))
}

///|
fn EntryTree::contextualize(self : EntryTree, at : Provenance) -> Provenance {
  at.through(self.provenance)
}

///|
/// Keep the parent artifact chain when reading a nested ZIP/JAR.
pub fn EntryTree::open_zip(
  self : EntryTree,
  path : EntryPath,
) -> EntryTree raise ResourceError {
  let bytes = self.read(path)
  let tree = EntryTree::zip(bytes, self.entry_origin(path), limits=self.limits) catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, self.contextualize(at), message)
  }
  { ..tree, provenance: self.entry_provenance(path), }
}

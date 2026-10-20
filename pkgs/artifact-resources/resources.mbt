///|
/// Stable code, complete origin and detail. Hosts can render these separately.
pub(all) suberror ResourceError {
  ResourceError(String, String, String)
} derive(Debug)

///|
pub(all) struct Limits {
  max_archive_bytes : Int32
  max_entries : Int32
  max_entry_bytes : Int32
  max_total_bytes : Int32
}

///|
pub fn Limits::new(
  max_archive_bytes~ : Int32 = 67108864,
  max_entries~ : Int32 = 10000,
  max_entry_bytes~ : Int32 = 16777216,
  max_total_bytes~ : Int32 = 268435456,
) -> Limits {
  { max_archive_bytes, max_entries, max_entry_bytes, max_total_bytes, }
}

///|
pub struct EntryTree {
  origin : String
  priv provenance : String
  priv paths : Array[String]
  priv members : Set[String]
  priv read_entry : (String) -> Bytes raise ResourceError
  priv limits : Limits
  priv archive : Bool
  digest : String?
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
fn check_limits(limits : Limits, origin : String) -> Unit raise ResourceError {
  if limits.max_archive_bytes < 0 ||
    limits.max_entries < 0 ||
    limits.max_entry_bytes < 0 ||
    limits.max_total_bytes < 0 {
    raise ResourceError(
      "invalid-limits", origin, "Resource limits must be nonnegative",
    )
  }
}

///|
/// A host-supplied directory reader. Paths are copied and validated before use.
/// The callback receives only listed relative paths and must return file bytes.
pub fn EntryTree::directory(
  paths : Array[String],
  read : (String) -> Bytes raise ResourceError,
  origin : String,
  limits~ : Limits = Limits::new(),
) -> EntryTree raise ResourceError {
  check_limits(limits, origin)
  if paths.length() > limits.max_entries {
    raise ResourceError("resource-limit", origin, "Too many entries")
  }
  let seen : Set[String] = Set([])
  for path in paths {
    if !valid_path(path) {
      raise ResourceError(
        "unsafe-path",
        origin,
        "Unsafe entry path `" + path + "`",
      )
    }
    if seen.contains(path) {
      raise ResourceError(
        "duplicate-entry",
        origin,
        "Duplicate entry `" + path + "`",
      )
    }
    seen.add(path)
  }
  let paths = paths.copy()
  paths.sort()
  {
    origin,
    provenance: origin,
    paths,
    members: seen,
    read_entry: read,
    limits,
    archive: false,
    digest: None,
  }
}

///|
pub fn EntryTree::entries(self : EntryTree) -> Array[String] {
  self.paths.copy()
}

///|
pub fn EntryTree::contains(self : EntryTree, path : String) -> Bool {
  self.members.contains(path)
}

///|
pub fn EntryTree::entry_origin(self : EntryTree, path : String) -> String {
  self.origin + (if self.archive { "!/" } else { "/" }) + path
}

///|
pub fn EntryTree::read(
  self : EntryTree,
  path : String,
) -> Bytes raise ResourceError {
  if !valid_path(path) {
    raise ResourceError(
      "unsafe-path",
      self.provenance,
      "Unsafe entry path `" + path + "`",
    )
  }
  if !self.contains(path) {
    raise ResourceError(
      "missing-resource",
      self.entry_provenance(path),
      "Missing entry `" + path + "`",
    )
  }
  let bytes = (self.read_entry)(path) catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, self.contextualize(at), message)
  }
  if bytes.length() > self.limits.max_entry_bytes ||
    bytes.length() > self.limits.max_total_bytes {
    raise ResourceError(
      "resource-limit",
      self.entry_provenance(path),
      "Entry exceeds byte limit",
    )
  }
  bytes
}

///|
pub fn EntryTree::text(
  self : EntryTree,
  path : String,
) -> String raise ResourceError {
  @utf8.decode(self.read(path)) catch {
    _ =>
      raise ResourceError(
        "invalid-utf8",
        self.entry_provenance(path),
        "Invalid UTF-8 in `" + path + "`",
      )
  }
}

///|
/// Logical names are independent of physical paths inside the container.
pub(all) struct Declaration {
  name : String
  path : String
} derive(Debug, Eq)

///|
pub struct Resource {
  name : String
  path : String
  origin : String
  provenance : String
  bytes : Bytes
}

///|
pub fn Resource::text(self : Resource) -> String raise ResourceError {
  @utf8.decode(self.bytes) catch {
    _ =>
      raise ResourceError(
        "invalid-utf8",
        self.provenance,
        "Invalid UTF-8 in `" + self.path + "`",
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
      "resource-limit",
      tree.provenance,
      "Too many declared resources",
    )
  }
  let seen : Set[String] = Set([])
  let resources = []
  let mut total = 0
  for declaration in declarations {
    if !valid_path(declaration.name) {
      raise ResourceError(
        "unsafe-path",
        tree.provenance,
        "Unsafe logical name `" + declaration.name + "`",
      )
    }
    if seen.contains(declaration.name) {
      raise ResourceError(
        "duplicate-resource",
        tree.provenance,
        "Duplicate logical resource `" + declaration.name + "`",
      )
    }
    seen.add(declaration.name)
    let bytes = tree.read(declaration.path)
    if bytes.length() > tree.limits.max_total_bytes - total {
      raise ResourceError(
        "resource-limit",
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
pub fn EntryTree::provenance(self : EntryTree) -> String {
  self.provenance
}

///|
pub fn EntryTree::entry_provenance(self : EntryTree, path : String) -> String {
  self.contextualize(self.entry_origin(path))
}

///|
fn EntryTree::contextualize(self : EntryTree, at : String) -> String {
  if self.provenance == self.origin {
    at
  } else if at.has_prefix(self.origin) {
    self.provenance + at[self.origin.length():].to_owned()
  } else {
    self.provenance + " -> " + at
  }
}

///|
/// Keep the parent artifact chain when reading a nested ZIP/JAR.
pub fn EntryTree::open_zip(
  self : EntryTree,
  path : String,
) -> EntryTree raise ResourceError {
  let bytes = self.read(path)
  let tree = EntryTree::zip(bytes, self.entry_origin(path), limits=self.limits) catch {
    ResourceError(code, at, message) =>
      raise ResourceError(code, self.contextualize(at), message)
  }
  { ..tree, provenance: self.entry_provenance(path), }
}

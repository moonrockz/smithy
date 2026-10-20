///|
/// Register local directory, file and JAR acquisition using MoonBit's host FS.
/// A repository location is a local root; key "." selects the root itself.
pub fn register(
  registry : @resources.Registry,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> @resources.Registry raise @resources.ResourceError {
  registry.register_provider("local", (repository, reference) => {
    let root : @path.Path = repository.location
    if reference.key != "." && !@resources.valid_path(reference.key) {
      raise @resources.ResourceError(
        "unsafe-path",
        repository.location,
        "Unsafe local artifact key `" + reference.key + "`",
      )
    }
    let path = if reference.key == "." {
      root.normalize().to_string()
    } else {
      root.join(reference.key).to_string()
    }
    let tree = open(path, limits~)
    { reference, identity: path, tree, }
  })
}

///|
/// Open local input without writing or extracting files. Directories are read
/// lazily. The host controls filesystem access and symlink policy.
pub fn open(
  path : String,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> @resources.EntryTree raise @resources.ResourceError {
  open_host(path, limits) catch {
    @resources.ResourceError(code, origin, message) =>
      raise @resources.ResourceError(code, origin, message)
    @fs.IOError(message) =>
      raise @resources.ResourceError("local-io", path, message)
    error => raise @resources.ResourceError("local-io", path, error.to_string())
  }
}

///|
fn open_host(
  path : String,
  limits : @resources.Limits,
) -> @resources.EntryTree raise {
  let root : @path.Path = path
  if !@fs.is_dir(path) {
    if path.has_suffix(".jar") {
      return @resources.EntryTree::zip(
        @fs.read_file_to_bytes(path),
        path,
        limits~,
      )
    }
    let name = root.basename().to_owned()
    let parent = root.dirname().to_string()
    return @resources.EntryTree::directory(
      [name],
      _ => read_file(path),
      parent,
      limits~,
    )
  }
  let paths = []
  let pending = [""]
  let mut visited = 0
  while !pending.is_empty() {
    let relative = pending.pop().unwrap()
    let directory = if relative == "" {
      path
    } else {
      root.join(relative).to_string()
    }
    let names = @fs.read_dir(directory).to_owned()
    names.sort()
    for name in names {
      visited += 1
      if visited > limits.max_entries {
        raise @resources.ResourceError(
          "resource-limit", path, "Too many directory entries",
        )
      }
      let child = if relative == "" { name } else { relative + "/" + name }
      if !@resources.valid_path(child) {
        raise @resources.ResourceError(
          "unsafe-path",
          path,
          "Unsafe directory entry `" + child + "`",
        )
      }
      if @fs.is_dir(root.join(child).to_string()) {
        pending.push(child)
      } else {
        paths.push(child)
      }
    }
  }
  @resources.EntryTree::directory(
    paths,
    relative => read_file(root.join(relative).to_string()),
    path,
    limits~,
  )
}

///|
fn read_file(path : String) -> Bytes raise @resources.ResourceError {
  @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) =>
      raise @resources.ResourceError("local-io", path, message)
  }
}

///|
/// Register local directory, file and ZIP/JAR acquisition using the host FS.
pub fn register(
  registry : @resources.Registry,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> @resources.Registry raise @resources.ResourceError {
  registry.register_provider(@resources.ProviderId::parse("local").unwrap(), (
    repository,
    reference,
  ) => {
    let root : @path.Path = repository.location.to_string()
    let key = reference.key.to_string()
    let origin = @resources.Location::Source(repository.location)
    if key != "." && @resources.EntryPath::parse(key) is None {
      raise @resources.ResourceError(
        @resources.UnsafePath,
        @resources.Provenance::new(origin),
        "Unsafe local artifact key `" + key + "`",
      )
    }
    let path = if key == "." {
      root.normalize().to_string()
    } else {
      root.join(key).to_string()
    }
    let tree = open(
      @resources.RepositoryLocation::parse(path).unwrap(),
      limits~,
    )
    {
      reference,
      identity: @resources.ArtifactIdentity::parse(path).unwrap(),
      tree,
    }
  })
}

///|
pub fn open(
  location : @resources.RepositoryLocation,
  limits~ : @resources.Limits = @resources.Limits::new(),
) -> @resources.EntryTree raise @resources.ResourceError {
  let origin = @resources.Location::Source(location)
  open_host(location.to_string(), origin, limits) catch {
    @resources.ResourceError(code, at, message) =>
      raise @resources.ResourceError(code, at, message)
    @fs.IOError(message) =>
      raise @resources.ResourceError(
        @resources.LocalIo,
        @resources.Provenance::new(origin),
        message,
      )
    error =>
      raise @resources.ResourceError(
        @resources.LocalIo,
        @resources.Provenance::new(origin),
        error.to_string(),
      )
  }
}

///|
fn open_host(
  path : String,
  origin : @resources.Location,
  limits : @resources.Limits,
) -> @resources.EntryTree raise {
  let root : @path.Path = path
  if !@fs.is_dir(path) {
    if path.has_suffix(".jar") || path.has_suffix(".zip") {
      return @resources.EntryTree::zip(
        @fs.read_file_to_bytes(path),
        origin,
        limits~,
      )
    }
    let name = root.basename().to_owned()
    guard @resources.EntryPath::parse(name) is Some(entry) else {
      raise @resources.ResourceError(
        @resources.UnsafePath,
        @resources.Provenance::new(origin),
        "Unsafe filename `" + name + "`",
      )
    }
    let parent = @resources.Location::parse(root.dirname().to_string()).unwrap()
    return @resources.EntryTree::directory(
      [entry],
      _ => read_file(path, origin),
      parent,
      limits~,
      style=path_style(),
    )
  }
  let paths : Array[@resources.EntryPath] = []
  let directories = []
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
          @resources.ResourceLimit,
          @resources.Provenance::new(origin),
          "Too many directory entries",
        )
      }
      let child = if relative == "" { name } else { relative + "/" + name }
      guard @resources.EntryPath::parse(child) is Some(entry) else {
        raise @resources.ResourceError(
          @resources.UnsafePath,
          @resources.Provenance::new(origin),
          "Unsafe directory entry `" + child + "`",
        )
      }
      if @fs.is_dir(root.join(child).to_string()) {
        pending.push(child)
        directories.push(entry)
      } else {
        paths.push(entry)
      }
    }
  }
  @resources.EntryTree::directory(
    paths,
    relative => {
      read_file(
        root.join(relative.to_string()).to_string(),
        origin.directory_entry(relative, style=path_style()),
      )
    },
    origin,
    limits~,
    style=path_style(),
    directories~,
  )
}

///|
fn path_style() -> @resources.PathStyle {
  if @path.sep == '\\' {
    @resources.Backslash
  } else {
    @resources.Slash
  }
}

///|
fn read_file(
  path : String,
  origin : @resources.Location,
) -> Bytes raise @resources.ResourceError {
  @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) =>
      raise @resources.ResourceError(
        @resources.LocalIo,
        @resources.Provenance::new(origin),
        message,
      )
  }
}

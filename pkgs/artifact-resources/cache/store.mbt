///|
/// Filesystem cache on native hosts and Node.js. The directory is owned by the
/// caller. Keys are validated domain values and cannot traverse out of it.
pub fn open(
  location : @resources.RepositoryLocation,
) -> @resources.VerifiedCache {
  let root : @path.Path = location.to_string()
  let origin = @resources.Provenance::new(@resources.Location::Source(location))
  @resources.VerifiedCache::new({
    read: (key, bound) => {
      let result = read(
        @utf8.encode(root.join(key.to_string()).to_string() + "\u0000"),
        bound,
      )
      match result[0] {
        0 => None
        1 => Some(result[1:].to_owned())
        2 =>
          raise @resources.ResourceError(
            @resources.ResourceLimit,
            origin,
            "Cached value exceeds byte limit",
          )
        4 =>
          raise @resources.ResourceError(
            @resources.UnsupportedTransport,
            origin,
            "Filesystem caching requires native or Node.js",
          )
        _ =>
          raise @resources.ResourceError(
            @resources.CacheIo,
            origin,
            "Could not read cache value",
          )
      }
    },
    publish: (key, bytes) => {
      mkdir(root.to_string()) catch {
        _ =>
          raise @resources.ResourceError(
            @resources.CacheIo,
            origin,
            "Could not create cache directory",
          )
      }
      if !publish(
          @utf8.encode(root.join(key.to_string()).to_string() + "\u0000"),
          bytes,
        ) {
        raise @resources.ResourceError(
          @resources.CacheIo,
          origin,
          "Could not atomically publish cache value",
        )
      }
    },
  })
}

///|
fn mkdir(path : String) -> Unit raise {
  if @fs.path_exists(path) {
    return
  }
  let current : @path.Path = path
  let parent = current.dirname().to_string()
  if parent != path {
    mkdir(parent)
  }
  @fs.create_dir(path) catch {
    error => if !@fs.is_dir(path) { raise error }
  }
}

///|
priv struct TarFileRange {
  offset : Int32
  size : Int32
}

///|
/// Read V7, POSIX ustar and per-file pax tar data without extraction.
pub fn EntryTree::tar(
  data : Bytes,
  origin : Location,
  limits~ : Limits = Limits::new(),
) -> EntryTree raise ResourceError {
  check_limits(limits, origin)
  if data.length() > limits.max_archive_bytes {
    raise ResourceError(
      ResourceLimit,
      Provenance::new(origin),
      "Archive exceeds byte limit",
    )
  }
  tar_tree(data, origin, limits, ContentDigest::sha256(data))
}

///|
/// Decode gzip members with bounded inflation, then read their joined tar data.
/// The digest identifies the original compressed bytes.
pub fn EntryTree::tgz(
  data : Bytes,
  origin : Location,
  limits~ : Limits = Limits::new(),
) -> EntryTree raise ResourceError {
  check_limits(limits, origin)
  if data.length() > limits.max_archive_bytes {
    raise ResourceError(
      ResourceLimit,
      Provenance::new(origin),
      "Archive exceeds byte limit",
    )
  }
  let expanded = gunzip_bounded(data, origin, limits.max_expanded_bytes)
  tar_tree(expanded, origin, limits, ContentDigest::sha256(data))
}

///|
fn tar_tree(
  data : Bytes,
  origin : Location,
  limits : Limits,
  digest : ContentDigest,
) -> EntryTree raise ResourceError {
  if data.length() > limits.max_expanded_bytes {
    raise ResourceError(
      ResourceLimit,
      Provenance::new(origin),
      "Expanded tar exceeds byte limit",
    )
  }
  let files : Map[EntryPath, TarFileRange] = Map([])
  let members : Set[String] = Set([])
  let seen : Set[EntryPath] = Set([])
  let mut offset = 0
  let mut total = 0
  let mut count = 0
  let mut pending : Map[String, String]? = None
  while true {
    if data.length() - offset < 512 {
      raise archive_error(origin, "Truncated tar header or missing end markers")
    }
    if data[offset:offset + 512].iter().all(b => b == 0) {
      if pending is Some(_) ||
        data.length() - offset < 1024 ||
        (data.length() - offset) % 512 != 0 ||
        !data[offset:].iter().all(b => b == 0) {
        raise archive_error(origin, "Invalid tar end markers or trailing data")
      }
      break
    }
    count += 1
    if count > limits.max_entries {
      raise ResourceError(
        ResourceLimit,
        Provenance::new(origin),
        "Too many tar headers",
      )
    }
    let mut checksum = 0
    for i in 0..<512 {
      checksum += if i >= 148 && i < 156 {
        32
      } else {
        data[offset + i].to_int()
      }
    }
    let expected = tar_octal(data[offset + 148:offset + 156], origin)
    if expected != checksum {
      raise ResourceError(
        IntegrityFailure,
        Provenance::new(origin),
        "Tar header checksum mismatch",
      )
    }
    let magic = data[offset + 257:offset + 265]
    let posix = magic == b"ustar\x0000"[:]
    if !posix && !magic.iter().all(b => b == 0) {
      raise archive_error(
        origin, "Unsupported tar variant; expected V7 or POSIX ustar/pax",
      )
    }
    let name = tar_string(data[offset:offset + 100], origin)
    let prefix = if posix {
      tar_string(data[offset + 345:offset + 500], origin)
    } else {
      ""
    }
    let header_path = if prefix == "" { name } else { prefix + "/" + name }
    let kind = data[offset + 156]
    let header_size = tar_octal(data[offset + 124:offset + 136], origin)
    let extension = kind == b'x'
    if extension && (!posix || pending is Some(_)) {
      raise archive_error(
        origin, "Expected one POSIX pax header before a file or directory",
      )
    }
    if !extension && kind != 0 && kind != b'0' && kind != b'5' {
      raise archive_error(
        origin,
        "Unsupported tar entry type " +
        kind.to_int().to_string() +
        "; only regular files, directories and per-file pax headers are supported",
      )
    }
    let attributes = if extension {
      Map([])
    } else {
      pending.unwrap_or(Map([]))
    }
    let path = attributes.get("path").unwrap_or(header_path)
    let directory = kind == b'5'
    let checked = if directory && path.has_suffix("/") {
      path[:path.length() - 1].to_owned()
    } else {
      path
    }
    guard EntryPath::parse(checked) is Some(entry) else {
      raise ResourceError(
        UnsafePath,
        Provenance::new(origin),
        "Unsafe tar entry `" + path + "`",
      )
    }
    let size = match attributes.get("size") {
      Some(value) => tar_decimal(@utf8.encode(value)[:], origin)
      None => header_size
    }
    if size > limits.max_entry_bytes || size > limits.max_total_bytes - total {
      raise ResourceError(
        ResourceLimit,
        Provenance::new(origin.archive_entry(entry)),
        "Tar entries exceed byte limit",
      )
    }
    total += size
    offset += 512
    let padding = (512 - size % 512) % 512
    if size > data.length() - offset || padding > data.length() - offset - size {
      raise archive_error(origin, "Truncated tar entry or padding")
    }
    if extension {
      pending = Some(tar_pax(data[offset:offset + size], origin))
    } else {
      pending = None
      if seen.contains(entry) {
        raise ResourceError(
          DuplicateEntry,
          Provenance::new(origin.archive_entry(entry)),
          "Duplicate tar entry `" + checked + "`",
        )
      }
      seen.add(entry)
      if directory {
        if size != 0 {
          raise archive_error(
            origin.archive_entry(entry),
            "Tar directory must have zero size",
          )
        }
        members.add(checked + "/")
      } else {
        members.add(checked)
        files[entry] = { offset, size, }
      }
    }
    offset += size + padding
  }
  let paths = files.keys().to_array()
  paths.sort()
  {
    origin,
    provenance: Provenance::new(origin),
    paths,
    members,
    read_entry: path => {
      guard files.get(path) is Some(range) else {
        raise ResourceError(
          MissingResource,
          Provenance::new(origin.archive_entry(path)),
          "Expected a file",
        )
      }
      data[range.offset:range.offset + range.size].to_owned()
    },
    limits,
    locate_entry: path => origin.archive_entry(path),
    digest: Some(digest),
  }
}

///|
fn tar_string(
  data : BytesView,
  origin : Location,
) -> String raise ResourceError {
  let mut end = data.length()
  for i in 0..<data.length() {
    if data[i] == 0 {
      end = i
      break
    }
  }
  if !data[end:].iter().all(b => b == 0) {
    raise archive_error(origin, "Nonzero bytes after tar string terminator")
  }
  @utf8.decode(data[:end].to_owned()) catch {
    _ => raise archive_error(origin, "Invalid UTF-8 tar path or metadata")
  }
}

///|
fn tar_octal(data : BytesView, origin : Location) -> Int32 raise ResourceError {
  let mut start = 0
  let mut end = data.length()
  while start < end && data[start] == b' ' {
    start += 1
  }
  while end > start && (data[end - 1] == 0 || data[end - 1] == b' ') {
    end -= 1
  }
  let mut value = 0
  for i in start..<end {
    let digit = data[i].to_int() - 48
    if digit < 0 || digit > 7 || value > (2147483647 - digit) / 8 {
      raise archive_error(
        origin, "Invalid or oversized tar octal number; base-256 is unsupported",
      )
    }
    value = value * 8 + digit
  }
  value
}

///|
fn tar_decimal(
  data : BytesView,
  origin : Location,
) -> Int32 raise ResourceError {
  if data.is_empty() {
    raise archive_error(origin, "Empty pax decimal number")
  }
  let mut value = 0
  for b in data {
    let digit = b.to_int() - 48
    if digit < 0 || digit > 9 || value > (2147483647 - digit) / 10 {
      raise archive_error(origin, "Invalid or oversized pax decimal number")
    }
    value = value * 10 + digit
  }
  value
}

///|
fn tar_pax(
  data : BytesView,
  origin : Location,
) -> Map[String, String] raise ResourceError {
  let attributes : Map[String, String] = Map([])
  let mut offset = 0
  while offset < data.length() {
    let mut space = offset
    while space < data.length() && data[space] != b' ' {
      space += 1
    }
    let length = tar_decimal(data[offset:space], origin)
    if length > data.length() - offset ||
      length <= space - offset + 3 ||
      data[offset + length - 1] != b'\n' {
      raise archive_error(origin, "Malformed pax record length or terminator")
    }
    let end = offset + length - 1
    let mut equals = space + 1
    while equals < end && data[equals] != b'=' {
      equals += 1
    }
    if equals == end {
      raise archive_error(origin, "Missing pax keyword separator")
    }
    // Pax fields are length-delimited. Never treat a NUL as a terminator as
    // we do for fixed-width tar header strings.
    let key = @utf8.decode(data[space + 1:equals].to_owned()) catch {
      _ => raise archive_error(origin, "Invalid UTF-8 pax keyword")
    }
    let value = @utf8.decode(data[equals + 1:end].to_owned()) catch {
      _ => raise archive_error(origin, "Invalid UTF-8 pax value")
    }
    if attributes.contains(key) {
      raise archive_error(origin, "Duplicate pax keyword `" + key + "`")
    }
    match key {
      "path"
      | "size"
      | "uid"
      | "gid"
      | "uname"
      | "gname"
      | "mtime"
      | "atime"
      | "ctime"
      | "comment" => ()
      _ => raise archive_error(origin, "Unsupported pax keyword `" + key + "`")
    }
    attributes[key] = value
    offset += length
  }
  attributes
}

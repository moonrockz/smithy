///|
/// Read a ZIP32/JAR without extracting files. Validate all entry paths and sizes
/// before decoding. Stored and deflated file contents are read on demand.
pub fn EntryTree::zip(
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
  archive_validate_bounds(data, origin, limits)
  let archive = @zipc.Archive::from_bytes(data) catch {
    @zipc.ZipError(message) => raise archive_error(origin, message)
  }
  let members = archive.to_array()
  let paths = members.filter_map(member_ => {
    if member_.is_dir() {
      None
    } else {
      Some(EntryPath::parse(member_.path()).unwrap())
    }
  })
  paths.sort()
  let read = fn(path : EntryPath) -> Bytes raise ResourceError {
    guard archive.find(path.to_string()) is Some(member_) &&
      member_.kind() is @zipc.File(file) else {
      raise ResourceError(
        MissingResource,
        Provenance::new(origin.archive_entry(path)),
        "Expected a file",
      )
    }
    let bytes = match file.compression() {
      @zipc.Stored => file.data
      @zipc.Deflate =>
        inflate_bounded(
          file.data,
          file.decompressed_size(),
          origin.archive_entry(path),
        )
      _ =>
        raise archive_error(
          origin.archive_entry(path),
          "Unsupported compression method",
        )
    }
    if bytes.length() != file.decompressed_size() ||
      @checksum.crc32(bytes).reinterpret_as_int() != file.decompressed_crc32() {
      raise ResourceError(
        IntegrityFailure,
        Provenance::new(origin.archive_entry(path)),
        "ZIP size or CRC-32 mismatch",
      )
    }
    bytes
  }
  {
    origin,
    provenance: Provenance::new(origin),
    paths,
    members: Set(members.map(member_ => member_.path())),
    read_entry: read,
    limits,
    locate_entry: path => origin.archive_entry(path),
    digest: Some(ContentDigest::sha256(data)),
  }
}

///|
// Use the streaming decoder to enforce the declared size while inflating, even
// when a corrupt entry lies about its uncompressed length.
fn inflate_bounded(
  data : Bytes,
  expected : Int32,
  origin : Location,
) -> Bytes raise ResourceError {
  let inflater = @flate.Inflater::new()
  let buffer : FixedArray[Byte] = FixedArray::make(8192, b'\x00')
  let output : Array[Byte] = []
  let mut offset = 0
  while true {
    let (status, consumed, written) = inflater.step(
      data[offset:],
      buffer.mut_view(),
    ) catch {
      _ => raise archive_error(origin, "Invalid deflated ZIP entry")
    }
    if written > expected - output.length() {
      raise ResourceError(
        IntegrityFailure,
        Provenance::new(origin),
        "ZIP entry exceeds declared size",
      )
    }
    for i in 0..<written {
      output.push(buffer[i])
    }
    offset += consumed
    if status == @flate.Done {
      break
    }
    if consumed == 0 && written == 0 {
      raise archive_error(origin, "Truncated deflated ZIP entry")
    }
  }
  Bytes::from_array(output)
}

///|
// zipc 0.2.2 decodes ZIP32 offsets as signed Int values. Validate every range
// before handing it to the decoder so malformed offsets cannot index Bytes
// outside their bounds. Contents use bounded streaming inflation and CRC checks.
fn archive_validate_bounds(
  data : Bytes,
  origin : Location,
  limits : Limits,
) -> Unit raise ResourceError {
  fn range(start : Int32, size : Int32) -> Unit raise ResourceError {
    if start < 0 ||
      size < 0 ||
      size > data.length() ||
      start > data.length() - size {
      raise archive_error(
        origin, "Truncated ZIP entry or invalid archive offset",
      )
    }
  }
  fn u16(at : Int32) -> Int32 {
    data[at].to_int() | (data[at + 1].to_int() << 8)
  }
  fn u32(at : Int32) -> Int32 raise ResourceError {
    if data[at + 3].to_int() >= 128 {
      raise archive_error(
        origin, "ZIP64 or oversized ZIP32 archives are not supported",
      )
    }
    data[at].to_int() |
    (data[at + 1].to_int() << 8) |
    (data[at + 2].to_int() << 16) |
    (data[at + 3].to_int() << 24)
  }
  if data.length() < 22 || !@zipc.bytes_has_magic(data) {
    raise archive_error(origin, "Not a ZIP archive")
  }
  let mut end : Int32? = None
  let mut at = data.length() - 22
  let limit = if at > 65535 { at - 65535 } else { 0 }
  while at >= limit {
    if data[at] == 0x50 &&
      data[at + 1] == 0x4b &&
      data[at + 2] == 0x05 &&
      data[at + 3] == 0x06 {
      end = Some(at)
      break
    }
    at -= 1
  }
  guard end is Some(end) else {
    raise archive_error(origin, "Missing ZIP end of central directory")
  }
  if u16(end + 4) != 0 || u16(end + 6) != 0 || u16(end + 8) != u16(end + 10) {
    raise archive_error(origin, "Multi-disk ZIP archives are not supported")
  }
  range(end + 22, u16(end + 20))
  let count = u16(end + 10)
  if count > limits.max_entries {
    raise ResourceError(
      ResourceLimit,
      Provenance::new(origin),
      "Too many ZIP entries",
    )
  }
  let seen : Set[String] = Set([])
  let mut total = 0
  let size = u32(end + 12)
  let directory = u32(end + 16)
  range(directory, size)
  if directory + size > end {
    raise archive_error(origin, "Invalid ZIP central directory range")
  }
  let mut offset = directory
  for _ in 0..<count {
    range(offset, 46)
    if u32(offset) != 0x02014b50 {
      raise archive_error(origin, "Invalid ZIP central directory entry")
    }
    if (u16(offset + 8) & 1) != 0 {
      raise archive_error(origin, "Encrypted ZIP entries are not supported")
    }
    let compressed = u32(offset + 20)
    let expanded = u32(offset + 24)
    if expanded > limits.max_entry_bytes ||
      expanded > limits.max_total_bytes - total {
      raise ResourceError(
        ResourceLimit,
        Provenance::new(origin),
        "ZIP entries exceed byte limit",
      )
    }
    total += expanded
    let entry_size = 46 + u16(offset + 28) + u16(offset + 30) + u16(offset + 32)
    range(offset, entry_size)
    let name = @utf8.decode(
      data[offset + 46:offset + 46 + u16(offset + 28)].to_owned(),
    ) catch {
      _ => raise archive_error(origin, "Invalid UTF-8 ZIP entry path")
    }
    let checked = if name.has_suffix("/") {
      name[:name.length() - 1].to_owned()
    } else {
      name
    }
    if !valid_path(checked) {
      raise ResourceError(
        UnsafePath,
        Provenance::new(origin),
        "Unsafe ZIP entry `" + name + "`",
      )
    }
    if seen.contains(name) {
      raise ResourceError(
        DuplicateEntry,
        Provenance::new(origin),
        "Duplicate ZIP entry `" + name + "`",
      )
    }
    seen.add(name)
    let local_offset = u32(offset + 42)
    range(local_offset, 30)
    if u32(local_offset) != 0x04034b50 {
      raise archive_error(origin, "Invalid ZIP local file header")
    }
    let header_size = 30 + u16(local_offset + 26) + u16(local_offset + 28)
    range(local_offset, header_size)
    range(local_offset + header_size, compressed)
    offset += entry_size
  }
  if offset > directory + size {
    raise archive_error(origin, "ZIP entries exceed the central directory")
  }
}

///|
fn archive_error(origin : Location, message : String) -> ResourceError {
  ResourceError(InvalidArchive, Provenance::new(origin), message)
}

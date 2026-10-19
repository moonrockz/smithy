///|
/// Discover models listed by META-INF/smithy/manifest in a local JAR or ZIP.
/// Keys are relative to META-INF/smithy; no archive files are extracted.
pub fn archive_models(
  data : Bytes,
  origin : String,
) -> Map[String, String] raise BuildError {
  archive_validate_bounds(data, origin)
  let archive = @zipc.Archive::from_bytes(data) catch {
    @zipc.ZipError(message) => raise archive_error(origin, message)
  }
  let out : Map[String, String] = Map([])
  guard archive.find("META-INF/smithy/manifest") is Some(manifest) else {
    return out
  }
  let manifest = archive_text(manifest, origin)
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  for line in manifest.split("\n") {
    let name = line.to_owned()
    if name == "" || name.has_prefix("#") {
      continue
    }
    if !archive_model_path(name) {
      raise archive_error(origin, "Invalid Smithy manifest path `" + name + "`")
    }
    if out.contains(name) {
      continue
    }
    if !name.has_suffix(".smithy") && !name.has_suffix(".json") {
      raise archive_error(
        origin,
        "Unrecognized model file `" + name + "` in Smithy manifest",
      )
    }
    guard archive.find("META-INF/smithy/" + name) is Some(member_) else {
      raise archive_error(
        origin,
        "Smithy manifest references missing entry `" + name + "`",
      )
    }
    out[name] = archive_text(member_, origin)
  }
  out
}

///|
// zipc 0.2.2 decodes ZIP32 offsets as signed Int values. Validate every range
// before handing it to the decoder so malformed offsets cannot index Bytes
// outside their bounds. Decompression and CRC checks stay with zipc.
fn archive_validate_bounds(
  data : Bytes,
  origin : String,
) -> Unit raise BuildError {
  fn range(start : Int32, size : Int32) -> Unit raise BuildError {
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
  fn u32(at : Int32) -> Int32 raise BuildError {
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
    let _ = u32(offset + 24)
    let entry_size = 46 + u16(offset + 28) + u16(offset + 30) + u16(offset + 32)
    range(offset, entry_size)
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

///|
fn archive_text(
  member_ : @zipc.Member,
  origin : String,
) -> String raise BuildError {
  guard member_.kind() is @zipc.File(file) else {
    raise archive_error(
      origin,
      "Expected a model file at `" + member_.path() + "`",
    )
  }
  let bytes = file.to_bytes() catch {
    @zipc.ZipError(message) =>
      raise archive_error(origin, member_.path() + ": " + message)
  }
  @utf8.decode(bytes) catch {
    _ =>
      raise archive_error(origin, "Invalid UTF-8 in `" + member_.path() + "`")
  }
}

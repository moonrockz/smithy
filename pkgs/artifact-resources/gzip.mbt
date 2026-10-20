///|
fn gzip_u32(data : Bytes, at : Int32) -> UInt32 {
  data[at].to_uint() |
  (data[at + 1].to_uint() << 8) |
  (data[at + 2].to_uint() << 16) |
  (data[at + 3].to_uint() << 24)
}

///|
fn gunzip_bounded(
  data : Bytes,
  origin : Location,
  limit : Int32,
) -> Bytes raise ResourceError {
  let output : Array[Byte] = []
  let buffer : FixedArray[Byte] = FixedArray::make(8192, 0)
  let mut offset = 0
  if data.is_empty() {
    raise archive_error(origin, "Missing gzip member")
  }
  while offset < data.length() {
    let start = offset
    if data.length() - offset < 10 ||
      data[offset] != 0x1f ||
      data[offset + 1] != 0x8b ||
      data[offset + 2] != 8 {
      raise archive_error(
        origin, "Truncated or invalid gzip header or trailing data",
      )
    }
    let flags = data[offset + 3].to_int()
    if (flags & 0xe0) != 0 {
      raise archive_error(origin, "Reserved gzip flags are unsupported")
    }
    offset += 10
    if (flags & 4) != 0 {
      if data.length() - offset < 2 {
        raise archive_error(origin, "Truncated gzip extra length")
      }
      let length = data[offset].to_int() | (data[offset + 1].to_int() << 8)
      offset += 2
      if length > data.length() - offset {
        raise archive_error(origin, "Truncated gzip extra field")
      }
      offset += length
    }
    for flag in [8, 16] {
      if (flags & flag) != 0 {
        while offset < data.length() && data[offset] != 0 {
          offset += 1
        }
        if offset == data.length() {
          raise archive_error(origin, "Truncated gzip name or comment")
        }
        offset += 1
      }
    }
    if (flags & 2) != 0 {
      if data.length() - offset < 2 {
        raise archive_error(origin, "Truncated gzip header checksum")
      }
      let expected = data[offset].to_uint() | (data[offset + 1].to_uint() << 8)
      if (@checksum.crc32(data[start:offset].to_owned()) & 0xffff) != expected {
        raise ResourceError(
          IntegrityFailure,
          Provenance::new(origin),
          "Gzip header CRC-16 mismatch",
        )
      }
      offset += 2
    }
    let inflater = @flate.Inflater::new()
    let crc = @checksum.Crc32::new()
    let member_start = output.length()
    while true {
      let (status, consumed, written) = inflater.step(
        data[offset:],
        buffer.mut_view(),
      ) catch {
        _ => raise archive_error(origin, "Invalid gzip DEFLATE stream")
      }
      if written > limit - output.length() {
        raise ResourceError(
          ResourceLimit,
          Provenance::new(origin),
          "Expanded gzip exceeds byte limit",
        )
      }
      for i in 0..<written {
        output.push(buffer[i])
        crc.update_byte(buffer[i])
      }
      offset += consumed
      if status == @flate.Done {
        break
      }
      if consumed == 0 && written == 0 {
        raise archive_error(origin, "Truncated gzip DEFLATE stream")
      }
    }
    if data.length() - offset < 8 {
      raise archive_error(origin, "Truncated gzip trailer")
    }
    if crc.finish() != gzip_u32(data, offset) ||
      (output.length() - member_start).reinterpret_as_uint() !=
      gzip_u32(data, offset + 4) {
      raise ResourceError(
        IntegrityFailure,
        Provenance::new(origin),
        "Gzip CRC-32 or size mismatch",
      )
    }
    offset += 8
  }
  Bytes::from_array(output)
}

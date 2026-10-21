///|
/// The CLI's MoonBit filesystem host also supplies WASI descriptor I/O. Unlike
/// print_char, fd_write reports failures and flushes stdout/stderr in moonrun.
#unsafe_skip_stub_check
fn output_fd_write(
  fd : Int32,
  iov : Int32,
  count : Int32,
  written : Int32,
) -> Int32 = "wasi_snapshot_preview1" "fd_write"

///|
#unsafe_skip_stub_check
fn output_path_open(
  dir : Int32,
  lookup_flags : Int32,
  path : Int32,
  length : Int32,
  open_flags : Int32,
  rights : UInt64,
  inherited_rights : UInt64,
  fd_flags : Int32,
  result : Int32,
) -> Int32 = "wasi_snapshot_preview1" "path_open"

///|
#unsafe_skip_stub_check
fn output_fd_close(fd : Int32) -> Int32 = "wasi_snapshot_preview1" "fd_close"

///|
fn WasiBuffer::put_u32(
  self : WasiBuffer,
  offset : Int32,
  value : Int32,
) -> Unit {
  for i in 0..<4 {
    self.put(offset + i, (value >> (i * 8)).to_byte())
  }
}

///|
fn wasi_sink(fd : Int32, owned : Bool, buffer : WasiBuffer) -> OutputSink {
  {
    write: bytes => {
      let mut offset = 0
      while offset < bytes.length() {
        let length = Int32::min(8192, bytes.length() - offset)
        for i in 0..<length {
          buffer.put(16 + i, bytes[offset + i])
        }
        buffer.put_u32(0, buffer.address() + 16)
        buffer.put_u32(4, length)
        let error = output_fd_write(
          fd,
          buffer.address(),
          1,
          buffer.address() + 8,
        )
        guard error == 0 else {
          raise CliError("could not write output (WASI errno \{error})", 1)
        }
        let written = buffer.get_u32(8)
        guard written > 0 && written <= length else {
          raise CliError("invalid output write length", 1)
        }
        offset += written
      }
    },
    // WASI fd_write bypasses application buffers. moonrun flushes stdout/stderr
    // on each call and writes files directly. fd_sync would request durability.
    flush: () => (),
    close: () => {
      if owned {
        let error = output_fd_close(fd)
        guard error == 0 else {
          raise CliError("could not close output (WASI errno \{error})", 1)
        }
      }
    },
    flush_records: !owned,
  }
}

///|
fn output_sink(path : String?) -> OutputSink raise {
  let buffer = WasiBuffer::new()
  match path {
    None => wasi_sink(1, false, buffer)
    Some(path) => {
      guard !path.contains("\u0000") else {
        raise CliError("invalid output path", 1)
      }
      let path = @utf8.encode(path)
      guard path.length() <= 8192 else {
        raise CliError("invalid output path", 1)
      }
      for i in 0..<path.length() {
        buffer.put(16 + i, path[i])
      }
      // The MoonBit host preopens the working directory as descriptor 3. Follow
      // symlinks, create/truncate the file, and request only FD_WRITE rights.
      let error = output_path_open(
        3,
        1,
        buffer.address() + 16,
        path.length(),
        9,
        64UL,
        0UL,
        0,
        buffer.address() + 8,
      )
      guard error == 0 else {
        raise CliError("could not open output (WASI errno \{error})", 1)
      }
      wasi_sink(buffer.get_u32(8), true, buffer)
    }
  }
}

///|
#cfg(target="wasm-gc")
fn stderr_sink() -> OutputSink raise {
  wasi_sink(2, false, WasiBuffer::new())
}

///|
#cfg(target="wasm")
fn stderr_sink() -> OutputSink {
  wasi_sink(2, false, WasiBuffer::new())
}

///|
#unsafe_skip_stub_check
fn input_fd_read(
  fd : Int32,
  iov : Int32,
  count : Int32,
  read_count : Int32,
) -> Int32 = "wasi_snapshot_preview1" "fd_read"

///|
extern "wasm" fn input_load_byte(address : Int32) -> Int32 =
  #|(func (param i32) (result i32) local.get 0 i32.load8_u)

///|
/// Opens `path`, or stdin for "-", through WASI. A read gives at most the
/// capacity of the scratch buffer.
fn input_source(path : String) -> InputSource raise {
  let buffer = WasiBuffer::new()
  let owned = path != "-"
  let name = input_name(path)
  let fd = if owned {
    guard !path.contains("\u0000") else {
      raise CliError("invalid input path", 1)
    }
    let encoded = @utf8.encode(path)
    guard encoded.length() <= 8192 else {
      raise CliError("invalid input path", 1)
    }
    for i in 0..<encoded.length() {
      buffer.put(16 + i, encoded[i])
    }
    let error = output_path_open(
      3,
      1,
      buffer.address() + 16,
      encoded.length(),
      0,
      2UL,
      0UL,
      0,
      buffer.address() + 8,
    )
    guard error == 0 else {
      raise CliError("could not open \{name} (WASI errno \{error})", 1)
    }
    buffer.get_u32(8)
  } else {
    0
  }
  {
    read: requested => {
      // One WASI call fills at most the scratch buffer.
      let requested = Int32::min(requested, buffer.capacity())
      buffer.put_u32(0, buffer.address() + 16)
      buffer.put_u32(4, requested)
      let error = input_fd_read(fd, buffer.address(), 1, buffer.address() + 8)
      guard error == 0 else {
        raise CliError("could not read \{name} (WASI errno \{error})", 1)
      }
      let count = buffer.get_u32(8)
      guard count >= 0 && count <= requested else {
        raise CliError("invalid read length of \{name}", 1)
      }
      let bytes : Array[Byte] = []
      for i in 0..<count {
        bytes.push(input_load_byte(buffer.address() + 16 + i).to_byte())
      }
      Bytes::from_array(bytes)
    },
    close: () => {
      if owned {
        let error = output_fd_close(fd)
        guard error == 0 else {
          raise CliError("could not close \{name} (WASI errno \{error})", 1)
        }
      }
    },
  }
}

///|
/// The WASI binary reads as data arrives.
#cfg(target="wasm")
fn chunk_source(path : String) -> InputSource raise {
  input_source(path)
}

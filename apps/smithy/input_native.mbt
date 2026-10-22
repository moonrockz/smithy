///|
#borrow(path)
extern "C" fn native_input_open(path : Bytes) -> Int32 = "smithy_input_open"

///|
extern "C" fn native_input_stdin() -> Int32 = "smithy_input_stdin"

///|
#borrow(buffer)
extern "C" fn native_input_read(
  fd : Int32,
  buffer : Bytes,
  size : Int32,
) -> Int32 = "smithy_input_read"

///|
extern "C" fn native_input_close(fd : Int32) -> Bool = "smithy_input_close"

///|
/// Opens `path`, or stdin for "-". Each read gives what the input has now, so
/// a pipe or a FIFO streams as its writer writes.
fn input_source(path : String) -> InputSource raise {
  let owned = path != "-"
  let name = input_name(path)
  guard !path.contains("\u0000") else {
    raise CliError("invalid input path", 1)
  }
  let fd = if owned {
    native_input_open(@utf8.encode(path + "\u0000"))
  } else {
    native_input_stdin()
  }
  guard fd >= 0 else { raise CliError("could not open \{name}", 1) }
  {
    read: requested => {
      let buffer = Bytes::make(requested, 0)
      let count = native_input_read(fd, buffer, requested)
      guard count >= 0 && count <= requested else {
        raise CliError("could not read \{name}", 1)
      }
      buffer[:count].to_owned()
    },
    close: () => {
      if owned && !native_input_close(fd) {
        raise CliError("could not close \{name}", 1)
      }
    },
  }
}

///|
/// Native reads as data arrives.
fn chunk_source(path : String) -> InputSource raise {
  input_source(path)
}

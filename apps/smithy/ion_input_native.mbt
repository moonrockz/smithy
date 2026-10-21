///|
#borrow(path)
extern "C" fn native_ion_input_open(path : Bytes) -> Int32 = "smithy_ion_input_open"

///|
extern "C" fn native_ion_input_stdin() -> Int32 = "smithy_ion_input_stdin"

///|
#borrow(buffer)
extern "C" fn native_ion_input_read(
  fd : Int32,
  buffer : Bytes,
  size : Int32,
) -> Int32 = "smithy_ion_input_read"

///|
extern "C" fn native_ion_input_close(fd : Int32) -> Bool = "smithy_ion_input_close"

///|
fn ion_input_source(path : String) -> IonInputSource raise {
  guard !path.contains("\u0000") else {
    raise CliError("invalid Ion input path", 1)
  }
  let owned = path != "-"
  let fd = if owned {
    native_ion_input_open(@utf8.encode(path + "\u0000"))
  } else {
    native_ion_input_stdin()
  }
  guard fd >= 0 else { raise CliError("could not open Ion input", 1) }
  {
    read: requested => {
      let buffer = Bytes::make(requested, 0)
      let count = native_ion_input_read(fd, buffer, requested)
      guard count >= 0 && count <= requested else {
        raise CliError("could not read Ion input", 1)
      }
      buffer[:count].to_owned()
    },
    close: () => {
      if owned && !native_ion_input_close(fd) {
        raise CliError("could not close Ion input", 1)
      }
    },
  }
}

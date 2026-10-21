///|
#external
type OutputHandle

///|
#borrow(path)
extern "C" fn output_open(path : Bytes) -> OutputHandle = "smithy_output_open"

///|
extern "C" fn output_stdio(fd : Int32) -> OutputHandle = "smithy_output_stdio"

///|
extern "C" fn output_valid(handle : OutputHandle) -> Bool = "smithy_output_valid"

///|
#borrow(bytes)
extern "C" fn output_write(
  handle : OutputHandle,
  bytes : Bytes,
  size : Int32,
) -> Bool = "smithy_output_write"

///|
extern "C" fn output_flush(handle : OutputHandle) -> Bool = "smithy_output_flush"

///|
extern "C" fn output_close(handle : OutputHandle) -> Bool = "smithy_output_close"

///|
fn native_sink(handle : OutputHandle, owned : Bool) -> OutputSink raise {
  guard output_valid(handle) else { raise CliError("could not open output", 1) }
  {
    write: bytes => {
      guard output_write(handle, bytes, bytes.length()) else {
        raise CliError("could not write output", 1)
      }
    },
    flush: () => {
      guard output_flush(handle) else {
        raise CliError("could not flush output", 1)
      }
    },
    close: () => {
      if owned && !output_close(handle) {
        raise CliError("could not close output", 1)
      }
    },
    flush_records: !owned,
  }
}

///|
fn output_sink(path : String?) -> OutputSink raise {
  match path {
    None => native_sink(output_stdio(1), false)
    Some(path) => {
      guard !path.contains("\u0000") else {
        raise CliError("invalid output path", 1)
      }
      native_sink(output_open(@utf8.encode(path + "\u0000")), true)
    }
  }
}

///|
fn stderr_sink() -> OutputSink raise {
  native_sink(output_stdio(2), false)
}

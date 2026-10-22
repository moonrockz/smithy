///|
#borrow(buffer)
extern "C" fn stdin_chunk(buffer : Bytes, size : Int32) -> Int32 = "smithy_stdin_chunk"

///|
/// Gives each read of stdin to `consume` as it arrives, until end of input.
fn read_stdin_chunks(consume : (Bytes) -> Unit raise) -> Unit raise {
  let buffer = Bytes::make(8192, 0)
  while true {
    let count = stdin_chunk(buffer, buffer.length())
    if count < 0 || count > buffer.length() {
      raise CliError("could not read stdin", 1)
    }
    if count == 0 {
      break
    }
    consume(buffer[:count].to_owned())
  }
}

///|
fn stdin_bytes() -> Bytes raise {
  let bytes : Array[Byte] = []
  read_stdin_chunks(chunk => {
    for byte in chunk {
      bytes.push(byte)
    }
  })
  Bytes::from_array(bytes)
}

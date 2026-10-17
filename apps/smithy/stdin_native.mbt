///|
#borrow(buffer)
extern "C" fn stdin_chunk(buffer : Bytes, size : Int32) -> Int32 = "smithy_stdin_chunk"

///|
fn stdin_bytes() -> Bytes raise {
  let buffer = Bytes::make(8192, 0)
  let bytes : Array[Byte] = []
  while true {
    let count = stdin_chunk(buffer, buffer.length())
    if count < 0 {
      raise CliError("could not read stdin", 1)
    }
    if count == 0 {
      break
    }
    for byte in buffer[:count] {
      bytes.push(byte)
    }
  }
  Bytes::from_array(bytes)
}

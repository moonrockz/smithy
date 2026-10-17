///|
#borrow(bytes)
extern "wasm" fn bytes_address(bytes : Bytes) -> Int32 =
  #|(func (param i32) (result i32) local.get 0)

///|
#unsafe_skip_stub_check
#borrow(iov, count)
fn fd_read(fd : Int32, iov : Bytes, size : Int32, count : Bytes) -> Int32 = "wasi_snapshot_preview1" "fd_read"

///|
fn stdin_bytes() -> Bytes raise {
  // Bytes point at their payload on the linear-memory backend. Keep buffer
  // alive through the read and copy each chunk before reusing it.
  let buffer = Bytes::make(8192, 0)
  let address = bytes_address(buffer)
  let iov = Bytes::from_array([
    address.to_byte(),
    (address >> 8).to_byte(),
    (address >> 16).to_byte(),
    (address >> 24).to_byte(),
    b'\x00',
    b'\x20',
    b'\x00',
    b'\x00',
  ])
  let count = Bytes::make(4, 0)
  let out : Array[Byte] = []
  while true {
    let error = fd_read(0, iov, 1, count)
    if error != 0 {
      raise CliError("could not read stdin (WASI errno \{error})", 1)
    }
    guard count is [u32le(n)] else { raise CliError("could not read stdin", 1) }
    if n == 0 {
      break
    }
    guard n <= 8192 else { raise CliError("invalid stdin read length", 1) }
    for byte in buffer[:n.reinterpret_as_int()] {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

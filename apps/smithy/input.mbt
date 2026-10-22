///|
/// An open input: a file, or stdin. `read(n)` gives at most `n` bytes, and no
/// bytes at end of input. `close` releases a file; stdin stays open.
struct InputSource {
  read : (Int32) -> Bytes raise
  close : () -> Unit raise
}

///|
/// The most bytes that one read of a streamed input asks for: 64 KiB.
const INPUT_CHUNK_BYTES : Int32 = 65536

///|
/// The name of `path` in error messages.
fn input_name(path : String) -> String {
  if path == "-" {
    "stdin"
  } else {
    "'\{path}'"
  }
}

///|
/// Gives each chunk of `source` to `consume` until end of input, then closes
/// the source. A read or close error is given back, not raised, so that the
/// caller can finish the work on the chunks before it. An error that
/// `consume` raises closes the source and propagates.
fn read_chunks(
  source : InputSource,
  consume : (Bytes) -> Unit raise,
) -> Error? raise {
  let mut open = true
  errdefer (if open { (source.close)() catch { _ => () } })
  while true {
    let chunk = (source.read)(INPUT_CHUNK_BYTES) catch {
      error => {
        open = false
        (source.close)() catch {
          _ => ()
        }
        return Some(error)
      }
    }
    if chunk.is_empty() {
      break
    }
    consume(chunk)
  }
  open = false
  (source.close)() catch {
    error => return Some(error)
  }
  None
}

///|
/// Reads all of `path`, or of stdin for "-".
fn read_input_bytes(path : String) -> Bytes raise {
  let bytes : Array[Byte] = []
  let failure = read_chunks(chunk_source(path), chunk => {
    for byte in chunk {
      bytes.push(byte)
    }
  })
  if failure is Some(error) {
    raise error
  }
  Bytes::from_array(bytes)
}

///|
/// A source over bytes already in memory: the js and wasm-gc binaries read
/// the whole input before they check it. Each read gives the next slice.
#cfg(any(target="js", target="wasm-gc"))
fn whole_source(bytes : Bytes) -> InputSource {
  let mut offset = 0
  {
    read: requested => {
      let end = Int32::min(bytes.length(), offset + requested)
      let chunk = bytes[offset:end].to_owned()
      offset = end
      chunk
    },
    close: () => (),
  }
}

///|
struct IonInputSource {
  read : (Int32) -> Bytes raise
  close : () -> Unit raise
}

///|
fn collect_ion_bytes(
  source : IonInputSource,
  max_bytes~ : Int32,
) -> Bytes raise {
  let mut close_needed = true
  errdefer (if close_needed { (source.close)() catch { _ => () } })
  guard max_bytes >= 0 else { raise CliError("invalid Ion input limit", 1) }
  let bytes : Array[Byte] = []
  while true {
    let remaining = max_bytes - bytes.length()
    // Include one excess byte without overflowing at an Int32-sized limit.
    let requested = Int32::min(8191, remaining) + 1
    let chunk = (source.read)(requested)
    guard chunk.length() <= requested else {
      raise CliError("invalid Ion input read length", 1)
    }
    if chunk.is_empty() {
      break
    }
    guard chunk.length() <= remaining else {
      raise IonInputError(
        "IonInputLimit",
        "I expected an Ion input of at most \{max_bytes} bytes.",
        None,
      )
    }
    for byte in chunk {
      bytes.push(byte)
    }
  }
  close_needed = false
  (source.close)()
  Bytes::from_array(bytes)
}

///|
fn read_ion_bytes(
  file : String,
  max_bytes~ : Int32 = 16 * 1024 * 1024,
) -> Bytes raise {
  collect_ion_bytes(ion_input_source(file), max_bytes~)
}

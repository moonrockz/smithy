///|
/// moonrun exposes the host filesystem. Reading this stream through the host
/// avoids the seek-based native x/fs reader.
fn stdin_bytes() -> Bytes raise {
  @fs.read_file_to_bytes("/dev/stdin")
}

///|
/// The host reads all of stdin before the first chunk, so the findings are
/// the same as on native, but they are not live.
fn read_stdin_chunks(consume : (Bytes) -> Unit raise) -> Unit raise {
  consume(stdin_bytes())
}

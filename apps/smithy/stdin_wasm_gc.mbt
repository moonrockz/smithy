///|
/// moonrun exposes the host filesystem. Reading this stream through the host
/// avoids the seek-based native x/fs reader.
fn stdin_bytes() -> Bytes raise {
  @fs.read_file_to_bytes("/dev/stdin")
}

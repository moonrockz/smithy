///|
/// moonrun exposes the host filesystem. Reading stdin through the host avoids
/// the seek-based native x/fs reader. The host reads all of the input before
/// the first chunk, so the findings are the same as on native, but they are
/// not live.
fn chunk_source(path : String) -> InputSource raise {
  @fs.read_file_to_bytes(if path == "-" { "/dev/stdin" } else { path })
  |> whole_source
}

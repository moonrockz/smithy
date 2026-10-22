///|
extern "js" fn stdin_js() -> Bytes =
  #|() => process.getBuiltinModule('node:fs').readFileSync(0)

///|
/// Node reads all of the input before the first chunk, so the findings are
/// the same as on native, but they are not live.
fn chunk_source(path : String) -> InputSource raise {
  whole_source(
    if path == "-" {
      stdin_js()
    } else {
      @fs.read_file_to_bytes(path)
    },
  )
}

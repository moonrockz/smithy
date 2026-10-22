///|
extern "js" fn stdin_js() -> Bytes =
  #|() => process.getBuiltinModule('node:fs').readFileSync(0)

///|
fn stdin_bytes() -> Bytes {
  stdin_js()
}

///|
/// Node reads all of stdin before the first chunk, so the findings are the
/// same as on native, but they are not live.
fn read_stdin_chunks(consume : (Bytes) -> Unit raise) -> Unit raise {
  consume(stdin_bytes())
}

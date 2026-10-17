///|
extern "js" fn stdin_js() -> Bytes =
  #|() => process.getBuiltinModule('node:fs').readFileSync(0)

///|
fn stdin_bytes() -> Bytes {
  stdin_js()
}

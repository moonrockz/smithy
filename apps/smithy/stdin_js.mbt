///|
/// Reads all of stdin. A JS exception cannot be caught from MoonBit, so the
/// snippet catches it and puts a status byte first: 1 for the input, 0 for a
/// read that failed.
extern "js" fn stdin_js() -> Bytes =
  #|() => {
  #|  try {
  #|    const data = process.getBuiltinModule('node:fs').readFileSync(0);
  #|    return Buffer.concat([Buffer.from([1]), data]);
  #|  } catch (_) { return Buffer.from([0]); }
  #|}

///|
/// Node reads all of the input before the first chunk, so the findings are
/// the same as on native, but they are not live.
fn chunk_source(path : String) -> InputSource raise {
  whole_source(
    if path == "-" {
      let result = stdin_js()
      guard result.length() > 0 && result[0] == 1 else {
        raise CliError("could not read stdin", 1)
      }
      result[1:].to_owned()
    } else {
      @fs.read_file_to_bytes(path)
    },
  )
}

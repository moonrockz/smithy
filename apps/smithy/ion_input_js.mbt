///|
extern "js" fn js_ion_input_open(path : String) -> Int32 =
  #|(path) => {
  #|  try { return process.getBuiltinModule('node:fs').openSync(path, 'r'); }
  #|  catch (_) { return -1; }
  #|}

///|
extern "js" fn js_ion_input_read(
  fd : Int32,
  buffer : Bytes,
  size : Int32,
) -> Int32 =
  #|(fd, buffer, size) => {
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  let wait;
  #|  for (;;) {
  #|    try { return fs.readSync(fd, buffer, 0, size, null); }
  #|    catch (error) {
  #|      if (error.code === 'EINTR') continue;
  #|      if (error.code !== 'EAGAIN' && error.code !== 'EWOULDBLOCK') return -1;
  #|      wait ??= new Int32Array(new SharedArrayBuffer(4));
  #|      Atomics.wait(wait, 0, 0, 1);
  #|    }
  #|  }
  #|}

///|
fn ion_input_source(path : String) -> IonInputSource raise {
  let owned = path != "-"
  let fd = if owned { js_ion_input_open(path) } else { 0 }
  guard fd >= 0 else { raise CliError("could not open Ion input", 1) }
  {
    read: requested => {
      let buffer = Bytes::make(requested, 0)
      let count = js_ion_input_read(fd, buffer, requested)
      guard count >= 0 && count <= requested else {
        raise CliError("could not read Ion input", 1)
      }
      buffer[:count].to_owned()
    },
    close: () => {
      if owned && !js_output_close(fd) {
        raise CliError("could not close Ion input", 1)
      }
    },
  }
}

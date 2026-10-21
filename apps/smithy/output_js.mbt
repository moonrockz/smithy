///|
extern "js" fn js_output_open(path : String) -> Int32 =
  #|(path) => {
  #|  try { return process.getBuiltinModule('node:fs').openSync(path, 'w'); }
  #|  catch (_) { return -1; }
  #|}

///|
extern "js" fn js_output_write(fd : Int32, bytes : Bytes) -> Bool =
  #|(fd, bytes) => {
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  try {
  #|    let offset = 0;
  #|    let wait;
  #|    while (offset < bytes.length) {
  #|      let n;
  #|      try { n = fs.writeSync(fd, bytes, offset, bytes.length - offset); }
  #|      catch (error) {
  #|        if (error.code === 'EINTR') continue;
  #|        if (error.code !== 'EAGAIN' && error.code !== 'EWOULDBLOCK') throw error;
  #|        // Node may mark inherited pipes nonblocking. Wait for the consumer
  #|        // without accumulating output or spinning while it applies pressure.
  #|        wait ??= new Int32Array(new SharedArrayBuffer(4));
  #|        Atomics.wait(wait, 0, 0, 1);
  #|        continue;
  #|      }
  #|      if (n <= 0) return false;
  #|      offset += n;
  #|    }
  #|    return true;
  #|  } catch (_) { return false; }
  #|}

///|
extern "js" fn js_output_close(fd : Int32) -> Bool =
  #|(fd) => {
  #|  try { process.getBuiltinModule('node:fs').closeSync(fd); return true; }
  #|  catch (_) { return false; }
  #|}

///|
fn js_sink(fd : Int32, owned : Bool) -> OutputSink raise {
  guard fd >= 0 else { raise CliError("could not open output", 1) }
  {
    write: bytes => {
      guard js_output_write(fd, bytes) else {
        raise CliError("could not write output", 1)
      }
    },
    // writeSync bypasses Node's stream buffers; no filesystem fsync is needed.
    flush: () => (),
    close: () => {
      if owned && !js_output_close(fd) {
        raise CliError("could not close output", 1)
      }
    },
    flush_records: !owned,
  }
}

///|
fn output_sink(path : String?) -> OutputSink raise {
  match path {
    None => js_sink(1, false)
    Some(path) => js_sink(js_output_open(path), true)
  }
}

///|
fn stderr_sink() -> OutputSink raise {
  js_sink(2, false)
}

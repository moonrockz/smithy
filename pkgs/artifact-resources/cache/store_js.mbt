///|
extern "js" fn read(path : Bytes, bound : Int32) -> Bytes =
  #|(encoded, bound) => {
  #|  const path = new TextDecoder().decode(encoded.subarray(0, encoded.length - 1));
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  let fd;
  #|  try {
  #|    fd = fs.openSync(path, 'r');
  #|    const size = fs.fstatSync(fd).size;
  #|    if (size > bound) return new Uint8Array([2]);
  #|    const data = new Uint8Array(size + 1); data[0] = 1;
  #|    let n = 0;
  #|    while (n < size) {
  #|      const got = fs.readSync(fd, data, n + 1, size - n, null);
  #|      if (!got) return new Uint8Array([3]);
  #|      n += got;
  #|    }
  #|    if (fs.readSync(fd, new Uint8Array(1), 0, 1, null)) return new Uint8Array([3]);
  #|    return data;
  #|  } catch (e) { return new Uint8Array([e.code === 'ENOENT' ? 0 : 3]); }
  #|  finally { if (fd !== undefined) fs.closeSync(fd); }
  #|}

///|
extern "js" fn publish(path : Bytes, bytes : Bytes) -> Bool =
  #|(encoded, bytes) => {
  #|  const path = new TextDecoder().decode(encoded.subarray(0, encoded.length - 1));
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  let dir;
  #|  try {
  #|    dir = fs.mkdtempSync(path + '.tmp-');
  #|    fs.writeFileSync(dir + '/value', bytes, {flag: 'wx', mode: 0o600});
  #|    fs.renameSync(dir + '/value', path);
  #|    return true;
  #|  } catch (_) { return false; }
  #|  finally { if (dir) fs.rmSync(dir, {recursive: true, force: true}); }
  #|}

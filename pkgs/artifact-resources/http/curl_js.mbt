///|
extern "js" fn run(url : String, max_bytes : Int32, seconds : Int32) -> Bytes =
  #|(url, maxBytes, seconds) => {
  #|  let code = 0, output = new Uint8Array();
  #|  try {
  #|    const path = process.getBuiltinModule('node:path');
  #|    let curl = 'curl';
  #|    if (process.platform === 'win32') {
  #|      const root = process.env.SystemRoot;
  #|      if (!root || !path.isAbsolute(root)) throw new Error('Missing absolute SystemRoot');
  #|      curl = path.join(root, 'System32', 'curl.exe');
  #|    }
  #|    output = process.getBuiltinModule('node:child_process').execFileSync(curl, [
  #|      '-q', '--silent', '--globoff', '--location', '--max-redirs', '5',
  #|      '--proto', '=http,https', '--proto-redir', url.startsWith('https:') ? '=https' : '=http,https',
  #|      '--disallow-username-in-url', '--max-time', String(seconds),
  #|      '--max-filesize', String(maxBytes), '--write-out', '\n%{http_code}\n%{url_effective}', '--url', url
  #|    ], {maxBuffer: maxBytes + 16384, timeout: seconds * 1000 + 1000,
  #|        killSignal: 'SIGKILL', stdio: ['ignore', 'pipe', 'ignore']});
  #|  } catch (error) {
  #|    code = error.code === 'ENOBUFS' ? 63 : error.code === 'ETIMEDOUT' ? 28 : error.status || 127;
  #|  }
  #|  const result = new Uint8Array(4 + output.length);
  #|  new DataView(result.buffer).setInt32(0, code, true);
  #|  result.set(output, 4);
  #|  return result;
  #|}

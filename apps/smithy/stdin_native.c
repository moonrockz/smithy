#include <stdio.h>
#include <moonbit.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

MOONBIT_FFI_EXPORT int smithy_stdin_chunk(moonbit_bytes_t buffer, int size) {
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY);
#endif
  size_t count = fread(buffer, 1, (size_t)size, stdin);
  return ferror(stdin) ? -1 : (int)count;
}

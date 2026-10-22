#include <stdio.h>
#include <moonbit.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

/* Defined in ion_input_native.c: read(2) with EINTR and EAGAIN handling. */
int smithy_ion_input_read(int fd, unsigned char *buffer, int size);

/* Reads what stdin has now, up to size bytes. Unlike fread, read(2) returns as
   soon as a pipe has data, so a live writer is not held until end of input. */
MOONBIT_FFI_EXPORT int smithy_stdin_chunk(moonbit_bytes_t buffer, int size) {
#ifdef _WIN32
  _setmode(0, _O_BINARY);
#endif
  return smithy_ion_input_read(0, buffer, size);
}

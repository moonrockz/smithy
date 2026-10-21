#include <errno.h>
#include <stdlib.h>
#include <moonbit.h>
#ifdef _WIN32
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#endif

MOONBIT_FFI_EXPORT int smithy_ion_input_open(const unsigned char *path) {
#ifdef _WIN32
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, -1, NULL, 0);
  if (!size) return -1;
  wchar_t *wide = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
  if (!wide) return -1;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, -1, wide, size)) {
    free(wide);
    return -1;
  }
  int fd = _wopen(wide, _O_RDONLY | _O_BINARY);
  free(wide);
  return fd;
#else
  return open((const char *)path, O_RDONLY);
#endif
}

MOONBIT_FFI_EXPORT int smithy_ion_input_stdin(void) {
#ifdef _WIN32
  if (_setmode(0, _O_BINARY) == -1) return -1;
#endif
  return 0;
}

MOONBIT_FFI_EXPORT int smithy_ion_input_read(int fd, unsigned char *buffer, int size) {
  for (;;) {
#ifdef _WIN32
    int count = _read(fd, buffer, (unsigned int)size);
#else
    int count = (int)read(fd, buffer, (size_t)size);
#endif
    if (count >= 0) return count;
    if (errno == EINTR) continue;
#ifndef _WIN32
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      struct pollfd waiting = { fd, POLLIN, 0 };
      int status;
      do { status = poll(&waiting, 1, -1); } while (status < 0 && errno == EINTR);
      if (status > 0) continue;
    }
#endif
    return -1;
  }
}

MOONBIT_FFI_EXPORT int smithy_ion_input_close(int fd) {
#ifdef _WIN32
  return _close(fd) == 0;
#else
  return close(fd) == 0;
#endif
}

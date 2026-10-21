#include <stdio.h>
#include <stdlib.h>
#include <moonbit.h>
#ifdef _WIN32
#include <windows.h>
#include <fcntl.h>
#include <io.h>
#else
#include <signal.h>
#endif

MOONBIT_FFI_EXPORT void *smithy_output_open(const unsigned char *path) {
#ifdef _WIN32
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, -1, NULL, 0);
  if (!size) return NULL;
  wchar_t *wide = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
  if (!wide) return NULL;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path, -1, wide, size)) {
    free(wide);
    return NULL;
  }
  FILE *file = _wfopen(wide, L"wb");
  free(wide);
  return file;
#else
  return fopen((const char *)path, "wb");
#endif
}

MOONBIT_FFI_EXPORT void *smithy_output_stdio(int fd) {
  FILE *file = fd == 1 ? stdout : stderr;
#ifdef _WIN32
  _setmode(_fileno(file), _O_BINARY);
#endif
  return file;
}

MOONBIT_FFI_EXPORT int smithy_output_valid(void *handle) { return handle != NULL; }
MOONBIT_FFI_EXPORT int smithy_output_write(void *handle, const unsigned char *bytes, int size) {
#ifndef _WIN32
  /* Includes named pipes and /dev/stdout opened with --output. */
  signal(SIGPIPE, SIG_IGN);
#endif
  return fwrite(bytes, 1, (size_t)size, (FILE *)handle) == (size_t)size;
}
MOONBIT_FFI_EXPORT int smithy_output_flush(void *handle) { return fflush((FILE *)handle) == 0; }
MOONBIT_FFI_EXPORT int smithy_output_close(void *handle) { return fclose((FILE *)handle) == 0; }

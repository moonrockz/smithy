#include <moonbit.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#include <io.h>
#include <fcntl.h>
#include <sys/stat.h>
static wchar_t *wide(const char *p) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, p, -1, NULL, 0);
  wchar_t *s = n ? malloc((size_t)n * sizeof(wchar_t)) : NULL;
  if (s && !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, p, -1, s, n)) { free(s); return NULL; }
  return s;
}
static FILE *open_read(const char *p) {
  wchar_t *w = wide(p); if (!w) return NULL;
  FILE *f = _wfopen(w, L"rb"); free(w); return f;
}
#else
#include <unistd.h>
#include <fcntl.h>
static FILE *open_read(const char *p) { return fopen(p, "rb"); }
#endif

static moonbit_bytes_t status(int code) { return moonbit_make_bytes(1, code); }
MOONBIT_FFI_EXPORT moonbit_bytes_t smithy_cache_read(const uint8_t *path, int32_t bound) {
  FILE *f = open_read((const char *)path);
  if (!f) return status(errno == ENOENT ? 0 : 3);
  if (fseek(f, 0, SEEK_END)) { fclose(f); return status(3); }
  long size = ftell(f);
  if (size < 0) { fclose(f); return status(3); }
  if (size > bound) { fclose(f); return status(2); }
  rewind(f);
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)size + 1, 0);
  result[0] = 1;
  if (fread(result + 1, 1, (size_t)size, f) != (size_t)size || fgetc(f) != EOF || ferror(f)) result[0] = 3;
  fclose(f); return result;
}

/* Unique, exclusive temporary files in the destination filesystem. The final
 * name becomes visible only after a complete write and close. Interrupted
 * temporary files are never considered by readers. */
MOONBIT_FFI_EXPORT int32_t smithy_cache_publish(const uint8_t *path, const uint8_t *bytes) {
  size_t length = strlen((const char *)path);
  char *temp = malloc(length + 64);
  if (!temp) return -1;
  FILE *f = NULL;
#ifdef _WIN32
  wchar_t *dest = wide((const char *)path), *tmp = NULL;
  if (!dest) { free(temp); return -1; }
  for (unsigned i = 0; i < 1000; ++i) {
    snprintf(temp, length + 64, "%s.tmp-%lu-%u", path, (unsigned long)GetCurrentProcessId(), i);
    tmp = wide(temp); if (!tmp) break;
    int fd = _wopen(tmp, _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY, _S_IREAD | _S_IWRITE);
    if (fd >= 0) { f = _fdopen(fd, "wb"); if (!f) { _close(fd); _wremove(tmp); } break; }
    free(tmp); tmp = NULL;
    if (errno != EEXIST) break;
  }
#else
  snprintf(temp, length + 64, "%s.tmp-XXXXXX", path);
  int fd = mkstemp(temp);
  if (fd >= 0) { f = fdopen(fd, "wb"); if (!f) { close(fd); unlink(temp); } }
#endif
  int result = -1;
  if (f) {
    size_t size = (size_t)Moonbit_array_length(bytes);
    int okay = fwrite(bytes, 1, size, f) == size;
    if (fclose(f)) okay = 0;
#ifdef _WIN32
    if (okay && MoveFileExW(tmp, dest, MOVEFILE_REPLACE_EXISTING)) result = 0;
#else
    if (okay && rename(temp, (const char *)path) == 0) result = 0;
#endif
  }
#ifdef _WIN32
  if (tmp) { _wremove(tmp); free(tmp); } free(dest);
#else
  unlink(temp);
#endif
  free(temp); return result;
}

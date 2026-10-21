#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#else
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <time.h>
#include <errno.h>
extern char **environ;
#endif

/* No shell, temporary files, global descriptors or curl configuration files.
 * Authorization travels through stdin, never process arguments or stderr.
 * Keep the subprocess output bounded even on curl versions which cannot limit
 * unknown-length bodies. The extra space is for curl's final URL and status. */
MOONBIT_FFI_EXPORT moonbit_bytes_t smithy_resource_curl(
    const uint8_t *url, int32_t max_bytes, int32_t seconds, const uint8_t *config) {
  char max_text[32], time_text[32];
  snprintf(max_text, sizeof(max_text), "%d", max_bytes);
  snprintf(time_text, sizeof(time_text), "%d.%03d", seconds / 1000, seconds % 1000);
  size_t limit = (size_t)max_bytes + 32768, length = 0, capacity = 8192;
  unsigned char *data = malloc(capacity);
  int code = 127;
#ifndef _WIN32
  int finished = 0;
#endif
  if (!data) {
    moonbit_bytes_t result = moonbit_make_bytes(4, 0);
    result[0] = 127;
    return result;
  }
#ifdef _WIN32
  HANDLE input_reader = NULL, input_writer = NULL;
  HANDLE reader = NULL, writer = NULL, null_device = INVALID_HANDLE_VALUE;
  SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
  PROCESS_INFORMATION child = {0};
  STARTUPINFOW startup = {0};
  wchar_t curl_path[MAX_PATH], wide_command[10000];
  /* A bare executable name makes CreateProcess search the working directory.
   * Use Windows' installed curl, with an explicit application path. */
  UINT system_length = GetSystemDirectoryW(curl_path, MAX_PATH);
  if (!system_length || system_length + 10 >= MAX_PATH) goto finish;
  wcscat(curl_path, L"\\curl.exe");
  char command[10000];
  /* HttpUrl admits only printable ASCII and excludes quotes/backslashes.
   * Quoting the URL also preserves spaces if the validator ever permits them. */
  snprintf(command, sizeof(command),
    "curl.exe -q --config - --silent --globoff "
    "--proto =http,https --disallow-username-in-url "
    "--max-time %s --max-filesize %s --write-out \"\\n%%{http_code}\\n%%{url_effective}\\n%%{redirect_url}\" --url \"%s\"",
    time_text, max_text, url);
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, command, -1,
                           wide_command, 10000)) goto finish;
  if (!CreatePipe(&input_reader, &input_writer, &security, 65536)) goto finish;
  SetHandleInformation(input_writer, HANDLE_FLAG_INHERIT, 0);
  if (!CreatePipe(&reader, &writer, &security, 0)) goto finish;
  SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0);
  null_device = CreateFileA("NUL", GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdOutput = writer;
  startup.hStdError = null_device;
  startup.hStdInput = input_reader;
  if (!CreateProcessW(curl_path, wide_command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
                      NULL, NULL, &startup, &child)) goto finish;
  CloseHandle(writer); writer = NULL;
  CloseHandle(input_reader); input_reader = NULL;
  DWORD sent = 0;
  if (!WriteFile(input_writer, config, (DWORD)strlen((const char *)config), &sent, NULL) || sent != strlen((const char *)config)) {
    TerminateProcess(child.hProcess, 1);
  }
  CloseHandle(input_writer); input_writer = NULL;
#else
  int pipes[2], inputs[2];
  pid_t child;
  if (pipe(pipes) != 0) goto finish;
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, inputs) != 0) {
    close(pipes[0]); close(pipes[1]); goto finish;
  }
#ifdef SO_NOSIGPIPE
  int no_sigpipe = 1;
  setsockopt(inputs[1], SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO);
  posix_spawn_file_actions_addclose(&actions, pipes[0]);
  posix_spawn_file_actions_addclose(&actions, pipes[1]);
  posix_spawn_file_actions_adddup2(&actions, inputs[0], STDIN_FILENO);
  posix_spawn_file_actions_addclose(&actions, inputs[0]);
  posix_spawn_file_actions_addclose(&actions, inputs[1]);
  posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
  char *args[] = {"curl", "-q", "--config", "-", "--silent", "--globoff",
    "--proto", "=http,https",
    "--disallow-username-in-url", "--max-time", time_text, "--max-filesize", max_text,
    "--write-out", "\n%{http_code}\n%{url_effective}\n%{redirect_url}", "--url", (char *)url, NULL};
  int spawned = posix_spawnp(&child, "curl", &actions, NULL, args, environ);
  posix_spawn_file_actions_destroy(&actions);
  close(pipes[1]);
  close(inputs[0]);
  if (spawned != 0) { close(inputs[1]); close(pipes[0]); goto finish; }
  size_t input_length = strlen((const char *)config), input_sent = 0;
  while (input_sent < input_length) {
    int flags = 0;
#ifdef MSG_NOSIGNAL
    flags = MSG_NOSIGNAL;
#endif
    ssize_t count = send(inputs[1], config + input_sent, input_length - input_sent, flags);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    input_sent += (size_t)count;
  }
  close(inputs[1]);
#endif
  for (;;) {
    if (length == capacity) {
      if (capacity >= limit) { code = 63; break; }
      size_t next = capacity * 2;
      if (next > limit) next = limit;
      unsigned char *grown = realloc(data, next);
      if (!grown) { code = 127; break; }
      data = grown; capacity = next;
    }
#ifdef _WIN32
    DWORD count = 0;
    if (!ReadFile(reader, data + length, (DWORD)(capacity - length), &count, NULL) || !count) {
      WaitForSingleObject(child.hProcess, INFINITE);
      DWORD exit_code = 127;
      GetExitCodeProcess(child.hProcess, &exit_code);
      code = (int)exit_code; break;
    }
#else
    ssize_t count = read(pipes[0], data + length, capacity - length);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      int status;
      pid_t waited;
      do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
      finished = 1;
      code = waited > 0 && WIFEXITED(status) ? WEXITSTATUS(status) : 127;
      break;
    }
#endif
    length += (size_t)count;
  }
#ifdef _WIN32
  if (code == 63 || code == 127) TerminateProcess(child.hProcess, 1);
  WaitForSingleObject(child.hProcess, INFINITE);
  CloseHandle(child.hThread); CloseHandle(child.hProcess);
finish:
  if (input_reader) CloseHandle(input_reader);
  if (input_writer) CloseHandle(input_writer);
  if (reader) CloseHandle(reader);
  if (writer) CloseHandle(writer);
  if (null_device != INVALID_HANDLE_VALUE) CloseHandle(null_device);
#else
  if (!finished) {
    kill(child, SIGKILL);
    while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
  }
  close(pipes[0]);
finish:
#endif
  if (code != 0) length = 0;
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length + 4, 0);
  for (int i = 0; i < 4; i++) result[i] = (uint8_t)((uint32_t)code >> (8 * i));
  if (length) memcpy(result + 4, data, length);
  free(data);
  return result;
}

MOONBIT_FFI_EXPORT double smithy_resource_monotonic_ms(void) {
#ifdef _WIN32
  return (double)GetTickCount64();
#else
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) return 0.0;
  return (double)time.tv_sec * 1000.0 + (double)time.tv_nsec / 1000000.0;
#endif
}

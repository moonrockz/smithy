#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>
extern char **environ;
#endif

/* No shell, temporary files, global descriptors or curl configuration files.
 * Keep the subprocess output bounded even on curl versions which cannot limit
 * unknown-length bodies. The extra space is for curl's final URL and status. */
MOONBIT_FFI_EXPORT moonbit_bytes_t smithy_resource_curl(
    const uint8_t *url, int32_t max_bytes, int32_t seconds) {
  char max_text[32], time_text[32];
  snprintf(max_text, sizeof(max_text), "%d", max_bytes);
  snprintf(time_text, sizeof(time_text), "%d", seconds);
  const char *protocols = strncmp((const char *)url, "https:", 6) == 0
    ? "=https" : "=http,https";
  size_t limit = (size_t)max_bytes + 16384, length = 0, capacity = 8192;
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
  HANDLE reader = NULL, writer = NULL, null_device = INVALID_HANDLE_VALUE;
  SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
  PROCESS_INFORMATION child = {0};
  STARTUPINFOA startup = {0};
  char command[10000];
  /* HttpUrl admits only printable ASCII and excludes quotes/backslashes.
   * Quoting the URL also preserves spaces if the validator ever permits them. */
  snprintf(command, sizeof(command),
    "curl.exe -q --silent --globoff --location --max-redirs 5 "
    "--proto =http,https --proto-redir %s --disallow-username-in-url "
    "--max-time %s --max-filesize %s --write-out \"\\n%%{http_code}\\n%%{url_effective}\" --url \"%s\"",
    protocols, time_text, max_text, url);
  if (!CreatePipe(&reader, &writer, &security, 0)) goto finish;
  SetHandleInformation(reader, HANDLE_FLAG_INHERIT, 0);
  null_device = CreateFileA("NUL", GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdOutput = writer;
  startup.hStdError = startup.hStdInput = null_device;
  if (!CreateProcessA(NULL, command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
                      NULL, NULL, &startup, &child)) goto finish;
  CloseHandle(writer); writer = NULL;
#else
  int pipes[2];
  pid_t child;
  if (pipe(pipes) != 0) goto finish;
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO);
  posix_spawn_file_actions_addclose(&actions, pipes[0]);
  posix_spawn_file_actions_addclose(&actions, pipes[1]);
  posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
  posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
  char *args[] = {"curl", "-q", "--silent", "--globoff", "--location",
    "--max-redirs", "5", "--proto", "=http,https", "--proto-redir", (char *)protocols,
    "--disallow-username-in-url", "--max-time", time_text, "--max-filesize", max_text,
    "--write-out", "\n%{http_code}\n%{url_effective}", "--url", (char *)url, NULL};
  int spawned = posix_spawnp(&child, "curl", &actions, NULL, args, environ);
  posix_spawn_file_actions_destroy(&actions);
  close(pipes[1]);
  if (spawned != 0) { close(pipes[0]); goto finish; }
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

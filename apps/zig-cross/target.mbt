///|
/// A target that zig-cross builds for. `Host` is the machine itself: zig only compiles for it,
/// and the wrappers do not strip anything.
pub(all) enum Target {
  LinuxX64
  LinuxArm64
  DarwinArm64
  DarwinX64
  WindowsX64
  Host
} derive(Eq, Debug)

///|
/// The target names, in the order that the usage text shows them.
fn all_target_names() -> Array[String] {
  [
    "linux-x64", "linux-arm64", "darwin-arm64", "darwin-x64", "windows-x64", "host",
  ]
}

///|
pub fn Target::parse(text : String) -> Target? {
  match text {
    "linux-x64" => Some(LinuxX64)
    "linux-arm64" => Some(LinuxArm64)
    "darwin-arm64" => Some(DarwinArm64)
    "darwin-x64" => Some(DarwinX64)
    "windows-x64" => Some(WindowsX64)
    "host" => Some(Host)
    _ => None
  }
}

///|
pub fn Target::name(self : Target) -> String {
  match self {
    LinuxX64 => "linux-x64"
    LinuxArm64 => "linux-arm64"
    DarwinArm64 => "darwin-arm64"
    DarwinX64 => "darwin-x64"
    WindowsX64 => "windows-x64"
    Host => "host"
  }
}

///|
/// The zig target triple. `Host` has none: zig then compiles for the machine it runs on.
pub fn zig_triple(target : Target) -> String? {
  match target {
    LinuxX64 => Some("x86_64-linux-musl")
    LinuxArm64 => Some("aarch64-linux-musl")
    DarwinArm64 => Some("aarch64-macos")
    DarwinX64 => Some("x86_64-macos")
    WindowsX64 => Some("x86_64-windows-gnu")
    Host => None
  }
}

///|
/// The `Host` wrapper has one more rule. On Linux, a debug build compiles `backtrace.c`, which calls
/// `_Unwind_Backtrace`. gcc links its unwinder (libgcc) by itself, but `zig cc` does not, so a link
/// step needs zig's bundled `-lunwind`. macOS has the unwinder in libSystem and needs nothing. The
/// tool can run on wasm, so the wrapper decides at run time with `uname -s`. A compile step (`-c`)
/// does not link, so it gets no library.
///
/// The `cc` wrapper for `MOON_CC`: a /bin/sh script that runs `zig cc`.
///
/// A cross build needs two workarounds for upstream bugs in moon and in the MoonBit runtime:
///
/// 1. The runtime file `env.c` includes <stdlib.h> before it defines `_CRT_RAND_S`. On Windows
///    (mingw), `rand_s` is then not declared and the compile fails. A `-D_CRT_RAND_S` on the
///    command line defines it before the first include. The flag does no harm on other targets,
///    so every wrapper has it. Upstream: https://github.com/moonbitlang/moonbit-native-runtime/issues/2
/// 2. moon passes `-DMOONBIT_USE_SIMDUTF` and links the prebuilt objects `moonbit_simdutf.o`,
///    `simdutf.o` and `libbacktrace.a`. These objects are built for the machine that runs moon,
///    not for `MOON_CC`'s target, so the link fails or the binary gets the wrong architecture.
///    A cross wrapper removes the flag and the three files. The `Host` wrapper removes nothing.
///    Upstream: https://github.com/moonbitlang/moon/issues/2320
pub fn cc_wrapper(target : Target) -> String {
  match zig_triple(target) {
    None =>
      "#!/bin/sh\n" +
      "case \"$(uname -s)\" in Linux) unwind=-lunwind;; *) unwind=;; esac\n" +
      "for a in \"$@\"; do case \"$a\" in -c) unwind=;; esac; done\n" +
      "exec zig cc -D_CRT_RAND_S \"$@\" $unwind\n"
    Some(triple) =>
      "#!/bin/sh\n" +
      "for a in \"$@\"; do shift; case \"$a\" in -DMOONBIT_USE_SIMDUTF|*/moonbit_simdutf.o|*/simdutf.o|*/libbacktrace.a) ;; *) set -- \"$@\" \"$a\";; esac; done\n" +
      "exec zig cc -target \{triple} -D_CRT_RAND_S \"$@\"\n"
  }
}

///|
/// The `ar` wrapper for `MOON_AR`. moon puts the prebuilt simdutf objects into the runtime
/// archive; a cross build must leave them out (see `cc_wrapper`).
pub fn ar_wrapper(target : Target) -> String {
  match zig_triple(target) {
    None => "#!/bin/sh\nexec zig ar \"$@\"\n"
    Some(_) =>
      "#!/bin/sh\n" +
      "for a in \"$@\"; do shift; case \"$a\" in */moonbit_simdutf.o|*/simdutf.o|moonbit_simdutf.o|simdutf.o) ;; *) set -- \"$@\" \"$a\";; esac; done\n" +
      "exec zig ar \"$@\"\n"
  }
}

# Feasibility spike: moon build --target native cross-compilation via zig cc
> Spike output (2026-10-15): a recommendation, not kept code. Logs stayed in the scratch directory.

## Question

Can `moon build --target native` produce macOS (arm64, x86_64) and Windows x64 release
executables from a Linux CI runner, using `zig cc` as the C compiler, so a release workflow
needs no macOS job?

## Bottom line

**Yes, for the targets probed.** On this spike's test machine (Windows ARM64, so the probe ran
in the *reverse* cross-compilation direction: native target = aarch64-windows, cross targets =
x86_64-windows-gnu, x86_64-linux-gnu, aarch64-macos, x86_64-macos), `moon build --target native
--release` with MOON_CC/MOON_AR pointed at a zig cc / zig ar wrapper produced
correctly-typed binaries for all four cross targets, for both a toy "hello world" module and
a copy of the repo's real apps/smithy (which transitively pulls in moonbitlang/async, which
has per-OS C stub files). The Windows x64 binaries actually ran (via x64-on-arm64 emulation)
and printed correct output, including the real smithy-cli --help. The macOS and Linux binaries
could not be executed on this machine, but their file headers are correct for their targets (see
below) and they linked with zero errors.

The MoonBit native runtime for the version tested (moon 0.1.20261012) is compiled from C
source (runtime.c, utf.c, sync_io.c, env.c, backtrace.c in ~/.moon/lib/runtime) for
`moon build --target native --release`, not linked from prebuilt platform objects, which is what
makes cross-compilation possible at all. See "Source vs. prebuilt" below for the one exception.

## The mechanism moon offers for choosing the C compiler

Three ways, discovered by grepping strings out of moon.exe (no written doc was found under
~/.moon; `moon help build` does not mention it):

1. Environment variable MOON_CC - overrides the C compiler for every package in the build.
   It must be a path to a single executable; moon resolves it with CreateProcess-style lookup,
   so "<path> cc" (shell-style, space-separated) does not work - it must be a real .exe,
   or (on Windows) a .cmd/.bat file, since those are directly spawnable. There is a matching
   MOON_AR for the archiver.
2. Per-package config in moon.pkg: a link.native.cc / link.native.stub-cc key (the
   package's own choice of compiler), with sibling options the binary strings show as a
   NativeLinkConfig struct: cc-flags, cc-link-flags, stub-cc, stub-cc-flags,
   stub-cc-link-flags, stub-lib-deps. (cc itself is presumably also a field; I did not
   confirm the exact moon.pkg DSL syntax for setting it - this toolchain version uses a new
   non-JSON moon.pkg/moon.mod format, e.g. pkgtype(kind: "executable"), and I ran out of
   time budget to find a worked example of the link(...) block. MOON_CC/MOON_AR were
   sufficient for this spike and are also the simpler lever for a CI matrix: one env var per
   target, no per-package file edits.)
3. Auto-discovery when neither is set: on Windows this is a distinct "MSVC direct object
   native target" path (uses cl.exe/link.exe directly, not a cc-style driver - moon's error
   text says MOON_CC is ignored for Windows MSVC direct object native target unless you also
   point it at cl.exe/clang-cl.exe); elsewhere it tries cc/clang on PATH.

Moon also derives the archiver path from the compiler path when MOON_AR/stub-cc-equivalent
isn't set, by swapping the file name in the same directory (classic <prefix>-gcc to
<prefix>-ar convention) - this is why a zigcc.cmd wrapper alone fails ("failed to resolve
native archiver executable ...\zig\ar"); you need both MOON_CC and MOON_AR.

## What was tried

Zig 0.17.0 for windows-aarch64 was downloaded from https://ziglang.org/download/ (92 MiB
zip) into the scratch dir and run portably - no system install. zig.exe cannot be used directly
as MOON_CC because it needs the cc subcommand; a wrapper was required:

- zig/zigcc-<target>.cmd: "@echo off" plus a line calling "<scratch>\zig\...\zig.exe" cc -target <triple>
  -D_CRT_RAND_S %*
- zig/wrapper_ar.c compiled with zig cc (host target) into zig/ar.exe: re-execs
  zig.exe ar <args> via _spawnv, since MOON_AR must be a real executable too (a .cmd for
  the archiver was not tried; ar.exe was built once and reused for every target since zig ar
  is target-agnostic).

Targets attempted, each via a separate MOON_CC=zig\zigcc-<target>.cmd plus MOON_AR=zig\ar.exe,
moon build --target native --release --target-dir _build_<target> -v:

| Target triple | moon exit | Output magic | Expected | Ran? |
|---|---|---|---|---|
| (host) aarch64-windows, default MOON_CC, no -target | 0 | 4D 5A (PE, machine 0xAA64=ARM64) | PE/ARM64 | yes, printed hi |
| x86_64-windows-gnu | 0 | 4D 5A 78 00 (PE) | PE/x64 | yes (emulated), printed hi; real smithy-cli.exe --help also ran and printed its usage text |
| x86_64-linux-gnu | 0 | 7F 45 4C 46 (ELF) | ELF/x64 | not executable here |
| aarch64-macos | 0 | CF FA ED FE (Mach-O 64 LE) | Mach-O/arm64 | not executable here |
| x86_64-macos | 0 | CF FA ED FE (Mach-O 64 LE) | Mach-O/x64 | not executable here |

All four cross targets were also re-run against a copy of the real pkgs/smithy,
pkgs/smithy-syntax, apps/smithy (copied from the selkie repo into the scratch dir per the
probe plan, never built inside the repo itself) for the macOS-arm64 and Windows-x64 cases - both
built clean, including the transitive moonbitlang/async dependency, and the Windows-x64
smithy-cli.exe ran and printed real CLI output.

### One real obstacle found and worked around

The stock build failed on every target (including the host target) with:

C:\Users\damre\.moon\lib\runtime\env.c:244:9: error: call to undeclared function 'rand_s';
ISO C99 and later do not support implicit function declarations

Cause: env.c includes <stdlib.h> once early (unconditionally) and only later does
#define _CRT_RAND_S before re-including <stdlib.h> - which works under MSVC's UCRT headers
(no multiple-inclusion guard quirk there) but not under zig's bundled mingw-w64 headers, which
have a normal include guard, so the second inclusion is a no-op and rand_s's declaration
(gated on _CRT_RAND_S) never appears. Fix: pass -D_CRT_RAND_S on the compiler command line
(i.e., bake it into the zigcc.cmd wrapper) so the macro is already defined at the first
inclusion. This is a real, if small, portability gap in the shipped runtime C - it only surfaces
when compiling Windows targets with a non-MSVC-header toolchain (i.e., exactly the zig/mingw
cross-compilation path a Linux CI runner would use for the Windows x64 leg). It did not affect
the macOS or Linux targets (that code path is #ifdef _WIN32-gated).

No macOS SDK/framework errors were hit for either macOS target - zig bundles enough of the macOS
libc/headers for this program's needs (the runtime's current C surface, plus whatever
moonbitlang/async's macOS kqueue.c/stub pulls in, apparently did not need a framework that
isn't in zig's bundled libc shim). This may not hold for packages that need frameworks
(CoreFoundation, Security, etc. - e.g. for TLS) rather than just POSIX/libc; that was not
exercised here and is a gap in this spike's coverage.

## Source vs. prebuilt runtime

~/.moon/lib/runtime/*.c (runtime.c, env.c, sync_io.c, utf.c, backtrace.c) are
distributed as source and are what moon build --target native --release actually compiles
(confirmed from the -v build log and the .obj/.lib artifacts in _build/native/release/build).
This is the thing that makes cross-compilation possible at all.

Separately, ~/.moon/lib/*.o and *.a (libmoonbitrun.o, bcheck.o, bt-exe.o, bt-log.o,
moonbit_simdutf.o, runmain.o, simdutf.o, libtcc1.a) are prebuilt, host-only objects -
but they were not referenced by any moon build --target native --release run in this spike.
They appear to belong to a different, faster dev-loop path (~/.moon/bin/internal/tcc.exe is a
bundled Tiny C Compiler, almost certainly used by moon run / debug-mode native execution to avoid
invoking a system C compiler at all). Since the spike's question is specifically about
--release executables for a release workflow, this prebuilt path is likely irrelevant to that
workflow - but this was not exhaustively verified (e.g. whether --release ever falls back to
the prebuilt objects for SIMD-heavy code was not tested, since the probed packages do not trigger
MOONBIT_USE_SIMDUTF).

## Secondary data point: this Windows ARM64 machine

- Default moon build --target native --release (no MOON_CC override) used MSVC
  (cl.exe/link.exe - visible as "Creating library ... .lib and object ... .exp" in the
  build log) and produced an x64 PE (machine=0x8664), not ARM64, even though the host OS is
  Windows on ARM64 - i.e., the discovered MSVC toolchain is x64 host tools, and moon's default
  native target follows that discovery rather than the true OS architecture.
- Pointing MOON_CC/MOON_AR at zig instead produced a true ARM64 PE (machine=0xAA64) for
  the "no -target" (host) case, since zig defaults to the actual host triple.
- Zig's windows-aarch64 build ran natively on this machine with no emulation and no system
  install (portable zip).

## Recommendation

(a) Zig cross-compilation looks viable for a Linux-only release matrix for the targets
probed - macOS arm64, macOS x86_64, and Windows x64 all produced correctly-typed, and where
testable, correctly-running binaries from a single non-macOS, non-Windows-native toolchain
invocation. Suggested steps for the real CI workflow (all on one Ubuntu runner):

1. Download a zig Linux x86_64 release into the runner (pinned version, checksum-verified) -
   no system package manager install needed.
2. Build a tiny cc wrapper script per target (zig cc -target <triple> ...) and an ar
   wrapper (zig ar, or just alias ar=zig ar since on Linux a shell script works fine as
   MOON_AR/MOON_CC - the Windows-only "needs a real .exe" issue in this spike was purely a
   Windows CreateProcess quirk and will not apply on the Linux runner).
3. Set MOON_CC/MOON_AR per build invocation, one moon build --target native --release
   --target-dir _build_<target> per target, in a matrix of 4 (macos-arm64, macos-x64,
   windows-x64, linux-x64) or 5 if linux-arm64 is also wanted (untested here, but same mechanism
   should apply).
4. Keep the -D_CRT_RAND_S compiler flag for the Windows target leg specifically (works around
   the env.c header-ordering bug above); this is harmless to pass for the other targets too if
   a single wrapper is reused with per-target -target flag only.
5. Before relying on this for the full smithy toolchain, extend the probe to anything that needs
   TLS/network (frameworks, not just libc) and to moon test --target native (not probed here).

What the user must decide:
- Whether downloading/pinning a third-party toolchain (zig, from ziglang.org, MIT-licensed) in
  CI is acceptable, versus the current implicit reliance on system cc/MSVC. No licensing
  concern - zig itself is MIT; it bundles its own copies of mingw-w64/macOS SDK headers for
  cross-compiling, which carry their own (permissive) licenses worth a quick confirmation if that
  matters to the project.
- Whether to file/patch the env.c rand_s/_CRT_RAND_S ordering issue upstream in MoonBit's
  runtime (it is a real, if minor, bug independent of this spike) rather than carrying the
  -D_CRT_RAND_S workaround indefinitely in CI.
- Whether the untested gaps (macOS frameworks beyond libc, moon test --target native, linux-arm64,
  any SIMD/MOONBIT_USE_SIMDUTF code paths that might reach the prebuilt .o files) need a
  follow-up spike before this fully replaces a real macOS CI job, or whether the probed surface
  (plain MoonBit + moonbitlang/async) is enough to commit to the Linux-only matrix now.

## Logs

Raw build logs for each attempt are alongside this report in the same scratch directory:
build-verbose.log (first default-toolchain hello build), build-zigcc-default.log and
build-zigcc-default2.log (MOON_CC resolution failures before the ar wrapper existed),
build-zigcc-host.log and build-zigcc-host2.log (host-target zig cc, showing the rand_s
failure then the fix), build-win-x64.log, build-linux-x64.log, build-macos-arm64.log,
build-macos-x64.log (the four cross targets on the toy module), build-smithy-macos-arm64.log,
build-smithy-winx64.log (the real apps/smithy copy).

## Outcome (2026-10-16)

The release work (beads smithy-2qe.7) used the zig approach in real use. The tool is the module
`apps/zig-cross` (`moonrockz/zig-cross`). The build machine for this check was macOS arm64, with moon 0.1.20261012,
MoonBit 0.10.15+943464bfa and zig 0.17.0.

### New finding: host-only simdutf and libbacktrace objects

The spike said the prebuilt objects were not used by `--release` builds and marked the SIMD path as untested.
That is no longer true. Moon now always compiles the runtime with `-DMOONBIT_USE_SIMDUTF`. It archives the
prebuilt host objects `lib/moonbit_simdutf.o` and `lib/simdutf.o` into the runtime library. On Apple targets it
also links the prebuilt host `lib/libbacktrace.a`. For any other architecture, these objects cause
`undefined symbol: moonbit_simdutf_*` or `invalid cpu architecture`.

The fix is in the wrappers of `zig-cross`. For each named target, the cc wrapper drops `-DMOONBIT_USE_SIMDUTF` and
each argument that ends in `/moonbit_simdutf.o`, `/simdutf.o` or `/libbacktrace.a`. The ar wrapper drops the two
simdutf objects. The runtime then uses its scalar UTF code path. The `host` wrapper drops nothing, because the
debug test builds need libbacktrace. Every wrapper still adds `-D_CRT_RAND_S` (the `rand_s` finding above).

### What the work confirmed

Verified on macOS arm64 (2026-10-16), during the planning of the release work and in the build task:

- **All 5 targets build** (`mise run build:cross`) from one machine: linux-x64, linux-arm64, darwin-arm64, darwin-x64 and windows-x64.
  linux-arm64 was untested in the spike. `zig-cross` checks the header of each binary (ELF, Mach-O, PE and the
  machine field), and a wrong architecture fails the build.
- **musl works.** The Linux targets use `x86_64-linux-musl` and `aarch64-linux-musl`. Both build and link with
  `moonbitlang/async`. The gnu fallback was not needed. The Linux binaries are static.
- **Native tests under zig.** `moon test --target native` with the `host` wrapper (`mise run test:native-zig`)
  passed 299 of 299 tests on the same machine.
- **The binaries run.** On macOS arm64, `smithy version` from the darwin-arm64 binary and from the darwin-x64
  binary (under Rosetta) prints `smithy 0.1.0 (Smithy 2.0)`. The linux and windows binaries have the right
  headers. They were not run on this machine, because the Docker daemon was not running. The `smoke` job of the
  Release workflow runs each binary on a runner of its own OS (linux-x64, linux-arm64, darwin-arm64, darwin-x64,
  windows-x64). Its first result comes from the first Release run.

### Windows binaries must be built on Windows

The PR #7 Release dry run showed a defect in the cross-built windows-x64 binary. The job Smoke (windows-x64)
ran `smithy.exe version`, and the program printed the usage text. The arguments were wrong. The cause is in
`core/internal/os_string`, which uses `#cfg(platform="windows")`. Moon resolves this setting from the host OS,
because `core` is prebuilt for the host. A Windows binary that is built on Linux or macOS therefore has the
wrong `OsString` code. The release now builds windows-x64 natively on a Windows runner (job `build-windows`)
and cross-builds the other four targets only.

### Still open

- **TLS and macOS frameworks.** No smithy code uses the network, so nothing needed CoreFoundation, Security or
  another framework. This stays untested. Beads has a follow-up issue.
- **The upstream bugs.** The `rand_s` ordering and the host-only objects are workarounds in the wrappers. A draft
  report exists; it is not filed. Beads has a follow-up issue to remove the workarounds after the fix.

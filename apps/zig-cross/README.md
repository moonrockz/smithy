# zig-cross

`zig-cross` cross-compiles MoonBit native binaries with [zig](https://ziglang.org). It builds for Linux, macOS and
Windows from one machine. It runs with `moonx`, so you do not install it.

This tool will move to its own repository.

## Requirements

- Zig 0.17.0 on `PATH`: `mise use zig@0.17.0`.
- The `moon` command.
- Linux or macOS as the build machine. The tool stops on Windows.

## Usage

```sh
moonx moonrockz/zig-cross@<version> build linux-x64 darwin-arm64 -- apps/smithy
moonx moonrockz/zig-cross@<version> exec host -- moon test --target native
moonx moonrockz/zig-cross@<version> --help
```

`build [--target-dir DIR] <target>... [-- <path>...]`

1. It writes the wrappers `cc` and `ar` to `DIR/zig/<target>`. `DIR` is `_build/cross` by default.
2. It runs `moon build --target native --release --target-dir DIR/<target> [paths]` with `MOON_CC` and `MOON_AR`
   set to the wrappers.
3. It reads the header of each `*.exe` under `DIR/<target>/native/release/build`. A binary with the wrong
   architecture is a failure.
4. It prints a table (target, path, size, result). It exits with 1 when one target fails.

`exec <target> -- <command> <arg>...` runs a command with `MOON_CC` and `MOON_AR` set to the wrappers of one
target. Use `host` to compile the tests of a package with zig.

## Targets

| Name           | Zig triple            | Header check          |
| -------------- | --------------------- | --------------------- |
| `linux-x64`    | `x86_64-linux-musl`   | ELF, machine 62       |
| `linux-arm64`  | `aarch64-linux-musl`  | ELF, machine 183      |
| `darwin-arm64` | `aarch64-macos`       | Mach-O, cputype 16777228 |
| `darwin-x64`   | `x86_64-macos`        | Mach-O, cputype 16777223 |
| `windows-x64`  | `x86_64-windows-gnu`  | PE, machine 0x8664    |
| `host`         | none (the host)       | none                  |

## What the wrappers change, and why

Two upstream bugs make a plain `MOON_CC="zig cc -target ..."` fail.

- Every wrapper adds `-D_CRT_RAND_S`. The MoonBit runtime file `env.c` includes `<stdlib.h>` before it defines
  `_CRT_RAND_S`, so `rand_s` is not declared on Windows. The flag defines it before the first include.
- A cross wrapper drops `-DMOONBIT_USE_SIMDUTF` and the arguments that end in `/moonbit_simdutf.o`,
  `/simdutf.o` and `/libbacktrace.a`. moon links these prebuilt objects for the machine that runs moon. They have
  the wrong architecture for the target. The `ar` wrapper drops the two simdutf objects. The `host` wrapper
  drops nothing.

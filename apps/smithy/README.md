# smithy (CLI)

The Smithy command-line application. Build it from the repository root:

```shell
moon build --target native --release
_build/native/release/build/moonrockz/smithy-cli/smithy-cli.exe version
```

## Install

Install a release build with mise:

```shell
mise use -g github:moonrockz/smithy
smithy version
```

The root [README](../../README.md) lists the release assets. The Release workflow builds them with zig
(`apps/zig-cross`).

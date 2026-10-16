# Changelog

All notable changes to `moonrockz/smithy` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

## [0.0.1] - 2026-10-16

This is the first release of moonrockz/smithy. The `moonrockz/smithy-syntax` library parses Smithy IDL 1.0 and 2.0 into a lossless syntax tree and an AST, reports diagnostics with source carets, and gives several ways to walk the AST. The `smithy` command is available for Linux, macOS and Windows: install it with `mise use github:moonrockz/smithy@0.0.1`. In this release the command only prints its version. The new `moonrockz/zig-cross` tool cross-compiles MoonBit native programs with zig: run it with `moonx moonrockz/zig-cross@0.0.1`.

### 🚀 Features

- *(syntax)* Add the Smithy IDL syntax layer (moonrockz/smithy-syntax) ([#5](https://github.com/moonrockz/smithy/pull/5)) by @DamianReeves
- *(traversal)* Add the IDL traversal package ([#6](https://github.com/moonrockz/smithy/pull/6)) by @DamianReeves
- *(release)* Zig cross-compiled release pipeline ([#7](https://github.com/moonrockz/smithy/pull/7)) by @DamianReeves

### 📚 Documentation

- Add the mise trust step to the agent setup instructions by @DamianReeves

### 🏗️ Build and CI

- Set up the MoonBit monorepo with mise and moonx task scripts ([#1](https://github.com/moonrockz/smithy/pull/1)) by @DamianReeves
- Address the Codex review of the monorepo setup ([#2](https://github.com/moonrockz/smithy/pull/2)) by @DamianReeves
- Manage git hooks with lefthook ([#3](https://github.com/moonrockz/smithy/pull/3)) by @DamianReeves

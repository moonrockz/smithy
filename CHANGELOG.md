# Changelog

All notable changes to `moonrockz/smithy` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

## [0.1.1] - 2026-10-17

<!-- Highlights: replace this comment with a few sentences on what this release brings. -->

### 🐛 Bug fixes

- *(release)* Preserve wrapped migration notes ([#15](https://github.com/moonrockz/smithy/pull/15)) by @DamianReeves
- *(release)* Retry moonx asset availability ([#16](https://github.com/moonrockz/smithy/pull/16)) by @DamianReeves
- *(cli)* Use argparse for command help ([#17](https://github.com/moonrockz/smithy/pull/17)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.1.0...v0.1.1

## [0.1.0] - 2026-10-17

Smithy now assembles mixed IDL and JSON files into a semantic model and converts models in either direction. The CLI adds `ast`, `validate`, `format` and `convert`, and runs through `moonx moonrockz/smithy-cli@0.1.0`. Formatting preserves IDL comments; conversion emits flattened Smithy 2 models with exact numbers and one file per namespace. Parsing now rejects adjacent object and trait entries and reports corrected recovery locations. When upgrading from 0.0.1, import `Piece` and `Step` from `scanner`, and `Depth` and `ParseError` from `parser`; `ShapeKind` display now uses IDL keywords, and test helpers moved from `lawkit` to `internal/lawkit`.

### ⚠️ Breaking changes

- *(syntax)* Import `Piece` and `Step` from `scanner`, and `Depth` and `ParseError` from `parser`. `ShapeKind` display uses IDL keywords. Test helpers moved from `lawkit` to `internal/lawkit`. ([#11](https://github.com/moonrockz/smithy/pull/11))

### 🚀 Features

- *(model)* Add JSON AST codec and model assembly ([#10](https://github.com/moonrockz/smithy/pull/10)) by @DamianReeves
- *(cli)* Add commands and model conversion ([#12](https://github.com/moonrockz/smithy/pull/12)) by @DamianReeves

### 🐛 Bug fixes

- *(syntax)* [**breaking**] Harden parsing and traversal contracts ([#11](https://github.com/moonrockz/smithy/pull/11)) by @DamianReeves
- *(release)* Correct publication and CLI checks ([#13](https://github.com/moonrockz/smithy/pull/13)) by @DamianReeves

### 📚 Documentation

- *(zig-cross)* Link the upstream issues for the wrapper workarounds ([#9](https://github.com/moonrockz/smithy/pull/9)) by @DamianReeves

### 🏗️ Build and CI

- Do not unset core.hooksPath in hooks:install ([#4](https://github.com/moonrockz/smithy/pull/4)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.0.1...v0.1.0

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

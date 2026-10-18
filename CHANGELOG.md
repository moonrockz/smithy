# Changelog

All notable changes to `moonrockz/smithy` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

## [0.2.0] - 2026-10-18

Smithy now loads `smithy.contracts#conditions` and validates JMESPath syntax, modeled member references, function arguments, and boolean results during assembly. The new `moonrockz/jmespath` package exposes standalone parsing, an inspectable AST with source spans, JSON evaluation, and diagnostics with source locations. IDL/JSON conversion preserves contract expressions and documentation. Serialization does not evaluate contracts. Existing models without contract traits need no changes.

### 🚀 Features

- Support Smithy contract traits ([#21](https://github.com/moonrockz/smithy/pull/21)) by @DamianReeves
- Add public JMESPath parser and evaluator ([#22](https://github.com/moonrockz/smithy/pull/22)) by @DamianReeves
- Analyze JMESPath contract conditions ([#23](https://github.com/moonrockz/smithy/pull/23)) by @DamianReeves

### 🏗️ Build and CI

- Consume zig-cross from moonx-tools ([#20](https://github.com/moonrockz/smithy/pull/20)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.1.1...v0.2.0

## [0.1.1] - 2026-10-17

The Smithy CLI now uses `moonbitlang/core/argparse` for command-specific help and standard option syntax. Use `smithy help convert`, `smithy convert --help` or `-h` to see a command's options; inline forms such as `--to=json` and `-omodel.json` are supported. Release publishing now retries temporary moonx asset availability failures, and generated migration notes preserve wrapped text.

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

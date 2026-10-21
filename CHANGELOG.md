# Changelog

All notable changes to `moonrockz/smithy` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

## [0.4.0] - 2026-10-21

The new `moonrockz/artifact-resources` package loads selected resource trees from directories, ZIP/JAR, tar/gzip and npm archives, with validated paths, logical aliases and structured provenance. Smithy build sources, global imports and projection imports can now acquire public archive URLs, pinned GitHub release assets, exact npm versions and pinned Maven JARs with integrity verification, shared caching and explicit offline builds. Private repositories accept supplied Bearer or Basic credentials bound to exact origins through environment references; redirects strip authorization across origins and authenticated cache entries are isolated. Existing JSON string inputs and JAR manifest discovery remain compatible. Library callers must migrate resource metadata to domain types, wrap path inputs with `BuildInput::from_path`, initialize the added cache/offline/credential configuration fields, handle the new input/provenance/diagnostic variants, and update custom HTTP transports to receive `HttpRequest` as detailed below.

### ⚠️ Breaking changes

- *(resources)* Resource metadata uses validated domain types; `BuildConfig.sources`, `BuildConfig.imports` and `ProjectionConfig.imports` contain `BuildInput` values. Use `BuildInput::from_path` for legacy library inputs. JSON string configuration remains compatible. API migration and selection rules are documented. ([#28](https://github.com/moonrockz/smithy/pull/28))
- *(resources)* BuildInput adds Remote(PublicArchive, Selection), and with_location can raise BuildError for invalid remote replacement URLs. Exhaustive ResourceCode and ProvenanceStep matches need acquisition cases. ([#30](https://github.com/moonrockz/smithy/pull/30))
- *(resources)* Direct BuildConfig constructors must initialize cache_directory: CacheDirectory and offline. Parsed configuration supplies defaults. Exhaustive Location matches must handle FilesystemDirectory. ([#31](https://github.com/moonrockz/smithy/pull/31))
- *(resources)* Exhaustive matches must handle BuildInput::GitHub, GitHubRequestStep/GitHubStep provenance, and MissingRelease, AmbiguousAsset and RateLimited resource codes. ([#32](https://github.com/moonrockz/smithy/pull/32))
- *(resources)* Exhaustive `BuildInput` matches must handle `Npm(NpmArchive, Selection)` and `Maven(MavenArchive, Selection?)`; `None` selects Maven manifest discovery. Exhaustive `ProvenanceStep` matches must handle `NpmRequestStep`, `NpmStep`, `MavenRequestStep` and `MavenStep`; `ResourceCode` matches must handle `MissingPackageVersion`, `MissingArtifact` and `UnsupportedIntegrity`. Repository input `location()` values are registry/repository bases and `with_location()` validates replacements. ([#33](https://github.com/moonrockz/smithy/pull/33))
- *(resources)* `HttpTransport` receives `HttpRequest` instead of `HttpUrl`. Use `request.url` inside callbacks and `HttpRequest::anonymous(url)` for public host calls. Direct `BuildConfig` constructors must initialize `credentials: Array[CredentialBinding]`; use `[]` for anonymous acquisition. Parsed configuration supplies the default. ([#34](https://github.com/moonrockz/smithy/pull/34))

### 🚀 Features

- Add reusable local artifact resources ([#27](https://github.com/moonrockz/smithy/pull/27)) by @DamianReeves
- *(resources)* [**breaking**] Select local resource trees ([#28](https://github.com/moonrockz/smithy/pull/28)) by @DamianReeves
- *(resources)* Load local tar and npm archives ([#29](https://github.com/moonrockz/smithy/pull/29)) by @DamianReeves
- *(resources)* [**breaking**] Load verified public archives ([#30](https://github.com/moonrockz/smithy/pull/30)) by @DamianReeves
- *(resources)* [**breaking**] Cache artifacts for offline builds ([#31](https://github.com/moonrockz/smithy/pull/31)) by @DamianReeves
- *(resources)* [**breaking**] Load pinned GitHub release assets ([#32](https://github.com/moonrockz/smithy/pull/32)) by @DamianReeves
- *(resources)* [**breaking**] Load npm and Maven artifacts ([#33](https://github.com/moonrockz/smithy/pull/33)) by @DamianReeves
- *(resources)* [**breaking**] Add repository credentials ([#34](https://github.com/moonrockz/smithy/pull/34)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.3.0...v0.4.0

## [0.3.0] - 2026-10-19

Smithy now converts assembled models to JSON Schema through the new `moonrockz/smithy-jsonschema` package and the `jsonSchema` build plugin. The new `moonrockz/smithy-build` package and `smithy build` and `smithy clean` commands support projections, all 28 built-in transforms, local JAR imports and environment substitutions. `smithy select` evaluates selectors, and validation now runs configured and default validators with reference event IDs, severities, shape IDs and suppressions. Build outputs require a dedicated directory separate from sources and imports, with an ownership marker protecting existing files. Code that constructs `Shape`, `ModelDiagnostic` or `LoadResult` records directly must supply the added `provenance`, `event_id` and `validation_findings` fields respectively; loader callers need no record changes.

### 🚀 Features

- Add JSON Schema conversion and build toolchain ([#25](https://github.com/moonrockz/smithy/pull/25)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.2.0...v0.3.0

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

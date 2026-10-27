# Changelog

All notable changes to `moonrockz/smithy` are listed here, newest first.
Versions follow [Semantic Versioning](https://semver.org); while the version
is 0.x, a minor release can contain breaking changes.

<!-- git-cliff: end of header -->

## [0.7.0] - 2026-10-27

This release adds code generation. The new `smithy-codegen` module is a language-neutral core for Smithy code generators, and the `moonbit-jsonrpc-codegen`, `python-jsonrpc-codegen` and `go-jsonrpc-codegen` build plugins generate JSON-RPC peers in MoonBit, Python and Go, with tested runtimes and a payment terminal example. RPC validation now checks the error data of declared server errors, and a service can accept, report or reject a server error code that it does not declare (accept is the default). The model check now evaluates contract conditions on default values, trait values, examples and metadata as the Java Smithy reference does, and the project site has a Smithy language tour with tested examples. Two changes break existing use: suppressions and tests that name SM-MODEL-015, SM-MODEL-016 or SM-MODEL-017 must use the Smithy event IDs (ConditionsTrait, Model, TraitValue, TraitTarget), and a model whose values break a contract condition now gets an error event.

### ⚠️ Breaking changes

- Contract findings use the event IDs of Smithy (ConditionsTrait, Model, TraitValue, TraitTarget) in place of SM-MODEL-015/016/017, and three loader events change their IDs. Suppressions and tests that name an old ID must use the new one. ModelDiagnostic has a new field `report : DiagnosticReport`. A @pattern with a braced \u{...} escape now fails preparation, as in Smithy. ([#67](https://github.com/moonrockz/smithy/pull/67))
- *(smithy)* A model whose values break a contract condition now gets an error event. In pkgs/jmespath, to_number follows Java (null for a string that Java does not parse), number literals print as their source token, -0.0 == 0 is false as in Java, and strings order by UTF-16 code unit. ([#69](https://github.com/moonrockz/smithy/pull/69))

### 🚀 Features

- *(site)* Add the smithy.mbt logo, favicon and app icons ([#65](https://github.com/moonrockz/smithy/pull/65)) by @DamianReeves
- *(site)* Add the Smithy language tour with its first twelve lessons ([#68](https://github.com/moonrockz/smithy/pull/68)) by @DamianReeves
- *(site)* Add the tour sections Traits and Services with tested CLI and API blocks ([#70](https://github.com/moonrockz/smithy/pull/70)) by @DamianReeves
- *(smithy)* [**breaking**] Check model values against contract conditions and compare JMESPath numbers as Smithy does ([#69](https://github.com/moonrockz/smithy/pull/69)) by @DamianReeves
- *(site)* Add the tour sections on querying, validating data and evolving models ([#71](https://github.com/moonrockz/smithy/pull/71)) by @DamianReeves
- *(site)* Add the tour case study on a Smithy DSL for the Morphir IR ([#72](https://github.com/moonrockz/smithy/pull/72)) by @DamianReeves
- *(codegen)* Add the smithy-codegen core and the codegenFixture build plugin ([#73](https://github.com/moonrockz/smithy/pull/73)) by @DamianReeves
- *(jsonrpc)* Add payment terminal model and codegen contracts ([#76](https://github.com/moonrockz/smithy/pull/76)) by @DamianReeves
- *(codegen)* Add the MoonBit and Python JSON-RPC generators and runtimes ([#77](https://github.com/moonrockz/smithy/pull/77)) by @DamianReeves
- *(jsonrpc)* Add Go peers and interop matrix ([#78](https://github.com/moonrockz/smithy/pull/78)) by @DamianReeves
- *(rpc)* Validate declared server error codes and data ([#83](https://github.com/moonrockz/smithy/pull/83)) by @DamianReeves

### 🐛 Bug fixes

- [**breaking**] Match the Smithy reference for patterns, model events and rpcv2Json OpenAPI ([#67](https://github.com/moonrockz/smithy/pull/67)) by @DamianReeves
- Correct pattern and JMESPath validation ([#74](https://github.com/moonrockz/smithy/pull/74)) by @DamianReeves
- *(syntax)* Match Smithy member and doc parsing ([#75](https://github.com/moonrockz/smithy/pull/75)) by @DamianReeves
- *(runtime)* Bound the event-stream lines, events and JSON bodies that the HTTP clients read ([#79](https://github.com/moonrockz/smithy/pull/79)) by @DamianReeves
- *(runtime)* Close MoonBit WebSockets gracefully ([#80](https://github.com/moonrockz/smithy/pull/80)) by @DamianReeves
- *(runtime)* Retain Process handle for MoonBit stdio wait on Windows ([#81](https://github.com/moonrockz/smithy/pull/81)) by @DamianReeves

### 📚 Documentation

- *(brand)* Keep the logo variants that were not chosen ([#66](https://github.com/moonrockz/smithy/pull/66)) by @DamianReeves

### 🏗️ Build and CI

- *(release)* Wait up to 18 minutes for the published CLI asset ([#64](https://github.com/moonrockz/smithy/pull/64)) by @DamianReeves
- *(jsonrpc)* Verify Python JSON-RPC peers on native Windows ([#82](https://github.com/moonrockz/smithy/pull/82)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.6.0...v0.7.0

## [0.6.0] - 2026-10-24

This release adds JSON-RPC support. `smithy validate rpc` checks requests, responses, batches and whole transcripts against a Smithy model, `smithy validate value` checks JSON and native Ion values, and the OpenRPC transform exports Smithy JSON-RPC services. Model validation time is now linear in the shape count: a model of 4,000 shapes validates in less than a second, not in minutes. The new project site has docs, examples and an in-browser playground that validates, transforms and checks transcripts with no server. Two changes break existing use: replace `smithy validate-value` with `smithy validate value`, and add `kind` to code that builds a `SourceLocation` with a struct literal, or use `SourceLocation::new`.

### ⚠️ Breaking changes

- *(validation)* Use `smithy validate value` instead of `smithy validate-value`. Model inputs and options follow the nested subcommand. No legacy alias is provided. ([#44](https://github.com/moonrockz/smithy/pull/44))
- *(cli)* `SourceLocation` has a new field `kind : SourceKind`. Code that builds a `SourceLocation` with a struct literal must add `kind`, or use `SourceLocation::new(file, path~, span?, kind~ = User)`. Code that only reads a location needs no change. ([#57](https://github.com/moonrockz/smithy/pull/57))

### 🚀 Features

- *(validation)* Validate JSON-RPC requests ([#42](https://github.com/moonrockz/smithy/pull/42)) by @DamianReeves
- *(validation)* [**breaking**] Validate JSON-RPC responses ([#44](https://github.com/moonrockz/smithy/pull/44)) by @DamianReeves
- *(openrpc)* Export Smithy JSON-RPC services ([#45](https://github.com/moonrockz/smithy/pull/45)) by @DamianReeves
- Add HTTP protocol test suites ([#46](https://github.com/moonrockz/smithy/pull/46)) by @DamianReeves
- *(validation)* Validate JSON-RPC batches ([#47](https://github.com/moonrockz/smithy/pull/47)) by @DamianReeves
- *(validation)* Validate native Ion values ([#48](https://github.com/moonrockz/smithy/pull/48)) by @DamianReeves
- *(validation)* Validate JSON-RPC transcripts ([#49](https://github.com/moonrockz/smithy/pull/49)) by @DamianReeves
- *(validation)* Finish JSON-RPC transcript follow-ups ([#50](https://github.com/moonrockz/smithy/pull/50)) by @DamianReeves
- *(openrpc)* Build documents with published moonrockz/openrpc 0.2.0 ([#55](https://github.com/moonrockz/smithy/pull/55)) by @DamianReeves
- *(site)* Add the project site with docs and examples ([#56](https://github.com/moonrockz/smithy/pull/56)) by @DamianReeves
- *(site)* Add the in-browser playground ([#60](https://github.com/moonrockz/smithy/pull/60)) by @DamianReeves
- *(site)* Show playground progress, group the Validate list and fold the controls ([#62](https://github.com/moonrockz/smithy/pull/62)) by @DamianReeves

### 🐛 Bug fixes

- *(validation)* Support recorded RFC 3339 leap seconds ([#43](https://github.com/moonrockz/smithy/pull/43)) by @DamianReeves
- *(validation)* Make unreadable transcript input and refused entries consistent ([#52](https://github.com/moonrockz/smithy/pull/52)) by @DamianReeves
- *(cli)* Report an unreadable stdin on js instead of crashing ([#53](https://github.com/moonrockz/smithy/pull/53)) by @DamianReeves
- *(cli)* [**breaking**] Resolve the smithy.rpc traits in every model command ([#57](https://github.com/moonrockz/smithy/pull/57)) by @DamianReeves
- *(site)* Link the other version to a page it has ([#59](https://github.com/moonrockz/smithy/pull/59)) by @DamianReeves

### ⚡ Performance

- *(smithy)* Make model validation linear in the shape count ([#61](https://github.com/moonrockz/smithy/pull/61)) by @DamianReeves

### 🏗️ Build and CI

- Smoke on evidence and stop release dry runs on feature pull requests ([#51](https://github.com/moonrockz/smithy/pull/51)) by @DamianReeves
- File one GitHub issue per smoke breach ([#54](https://github.com/moonrockz/smithy/pull/54)) by @DamianReeves
- *(site)* Build deployable site runs one at a time ([#58](https://github.com/moonrockz/smithy/pull/58)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.5.0...v0.6.0

## [0.5.0] - 2026-10-21

Validate JSON files against Smithy shapes with `smithy validate-value` or reuse prepared contracts from the new `moonrockz/smithy-validation` package. Structured findings identify exact instance paths, preserve numeric precision and enforce bounded traversal and pattern work across supported targets. This release also adds OpenAPI export and model compatibility diffs with JSONL event output. The shared JSON-RPC/OpenRPC design is documented for the next protocol-validation slices; date-time value validation currently excludes leap-second notation.

### 🚀 Features

- *(openapi)* Convert Smithy services to OpenAPI ([#36](https://github.com/moonrockz/smithy/pull/36)) by @DamianReeves
- *(diff)* Compare Smithy model compatibility ([#37](https://github.com/moonrockz/smithy/pull/37)) by @DamianReeves
- *(validation)* Validate JSON values through the library and CLI ([#38](https://github.com/moonrockz/smithy/pull/38)) by @DamianReeves
- *(diff)* Add JSONL event output ([#39](https://github.com/moonrockz/smithy/pull/39)) by @DamianReeves

### 🐛 Bug fixes

- *(release)* Update every package pin in standalone consumers ([#41](https://github.com/moonrockz/smithy/pull/41)) by @DamianReeves

**Full changelog**: https://github.com/moonrockz/smithy/compare/v0.4.0...v0.5.0

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

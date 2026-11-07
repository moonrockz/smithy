# Bounded regex

## Purpose

Provide reusable runtime regular-expression search with finite compilation limits and interruptible, deterministic execution work. Allow Smithy validation and independent moonrockz consumers to share the same resource contract.

## ADDED Requirements

### Requirement: Independent public module

The system SHALL provide `moonrockz/regex` as a standalone module with only MoonBit core dependencies. Consumers SHALL be able to compile runtime patterns and perform Boolean search without importing Smithy, its syntax model, validation findings or application runtimes.

#### Scenario: An independent consumer uses runtime patterns

- **WHEN** a consumer outside this workspace imports the module and supplies a pattern string at runtime
- **THEN** it can compile the pattern and search an input using the public API
- **AND** its dependency closure contains no Smithy module or async runtime

### Requirement: Documented Boolean pattern profile

The matcher SHALL document its supported dialect and agree with the pinned core engine's Boolean search for supported patterns. Searching SHALL be unanchored unless the pattern supplies anchors. Capturing-group syntax SHALL be accepted as grouping, without exposing captures. Unsupported syntax SHALL produce a compilation error.

#### Scenario: Search and explicit anchors

- **WHEN** the consumer searches `!abc!` with `abc` and `^abc$`
- **THEN** the first pattern matches and the second does not

#### Scenario: Grouping does not require capture extraction

- **WHEN** the consumer compiles `(a|b)+` and searches `abba`
- **THEN** the Boolean result agrees with the core engine
- **AND** the API makes no promise to return capture values

#### Scenario: Unsupported syntax is explicit

- **WHEN** a consumer compiles an unsupported lookaround or backreference
- **THEN** it receives a compilation error rather than a successful matcher or a silent non-match

### Requirement: Validated finite compilation limits

Compilation SHALL enforce validated finite limits on source length, nesting and expanded program size before recursive parsing or expanded program allocation can exceed them. Defaults SHALL be at most 4,096 UTF-16 source units, 32 group levels and 1,024 expanded expression units. Limit failure SHALL be distinguishable from invalid pattern syntax.

#### Scenario: A short pattern has excessive expansion

- **WHEN** the consumer compiles `(?:a{256}){256}` under the default limits
- **THEN** compilation rejects it for exceeding the expanded-size limit without allocating the expanded program

#### Scenario: Nesting and source length boundaries

- **WHEN** compilation encounters a pattern beyond its configured nesting or source-length cap
- **THEN** it returns a compilation-limit error without panicking

#### Scenario: Invalid limit configuration

- **WHEN** a caller constructs compilation limits outside the documented supported bounds
- **THEN** construction reports a configuration error before compilation starts

### Requirement: Typed work limits and outcomes

Each search SHALL accept a validated finite work allowance and return either a completed Boolean result with used units or a distinct exhausted result with used units. Zero remaining allowance SHALL be representable. Used units SHALL be nonnegative and SHALL never exceed the allowance. Counter arithmetic SHALL not wrap.

#### Scenario: Failure to match is a completed result

- **WHEN** an adequately funded search proves that `^a$` does not match `b`
- **THEN** the outcome is a completed non-match with its work count
- **AND** the outcome is distinguishable from exhaustion

#### Scenario: No allowance remains

- **WHEN** a caller starts a search with zero remaining work
- **THEN** the outcome is exhausted with zero used units

### Requirement: Interruptible execution and allocation

Search SHALL stop before performing work that exceeds its remaining allowance, including inside transition construction and state lookup. Charges SHALL cover input steps, program visits, key comparisons, probes, resets and logical storage allocation or copying. The documented cost model SHALL bound matcher work and allocation without claiming a wall-clock deadline or process RSS cap.

#### Scenario: A transition exceeds the remaining allowance

- **WHEN** a pattern requires more work to construct its next transition than the call has remaining
- **THEN** the search stops within that construction and returns exhausted
- **AND** no result presents partial execution as a completed match or non-match

#### Scenario: A table requires growth

- **WHEN** execution requires a larger state or transition table
- **THEN** the search charges its allocation and copying before performing the growth
- **AND** it returns exhausted if the required charge cannot be funded

### Requirement: Deterministic accounting and recovery

For the same compiled pattern, limits and input, results and logical work counts SHALL be identical across calls and supported targets, independently of earlier successful or exhausted calls. Exhaustion SHALL leave the compiled pattern reusable without partial mutable execution state.

#### Scenario: Earlier inputs cannot change the outcome

- **WHEN** a reused matcher and a fresh matcher search the same value with the same allowance
- **THEN** their complete or exhausted outcomes and work counts agree

#### Scenario: Reuse after exhaustion

- **WHEN** a call exhausts its allowance midway through state construction and a later call searches the same input with enough work
- **THEN** the later call agrees with a fresh matcher

### Requirement: Portable execution

The public module SHALL support native, JavaScript, wasm and wasm-gc. Supported-pattern Boolean results, configured limit handling and logical work accounting SHALL agree across those targets.

#### Scenario: Target agreement

- **WHEN** the same supported pattern, input and limits run on each supported target
- **THEN** the outcome and used units agree

### Requirement: Smithy validation compatibility

Smithy validation SHALL use the public matcher while retaining its portable ECMA translation, unsupported-constraint diagnostics and shared call budget. Matcher exhaustion SHALL produce incomplete validation with `LimitExceeded`. Existing useful Morphir cases SHALL pass at unchanged defaults. Pattern work SHALL remain charged.

#### Scenario: A useful Morphir value passes

- **WHEN** the existing 97-unit FQName and record of 16 FQName references are validated with default limits
- **THEN** validation completes successfully without raising the allowance

#### Scenario: An expensive value exhausts its shared budget

- **WHEN** matching needs more units than remain after earlier validation work
- **THEN** validation stops with `LimitExceeded` and incomplete status
- **AND** it does not emit a completed pattern mismatch for that search

#### Scenario: Unsupported Smithy patterns retain their diagnostics

- **WHEN** a model uses a construct outside the existing portable Smithy profile
- **THEN** preparation reports `UnsupportedConstraint` through the existing Smithy API

### Requirement: Verifiable source provenance

The module SHALL retain required upstream licensing and attribution, record its exact source commit, and enumerate additions and modified files. The vendor check SHALL detect unexplained drift and run git operations without inherited `GIT_*` variables affecting another checkout.

#### Scenario: Unexplained vendored drift

- **WHEN** an unlisted modification is introduced into a copied file
- **THEN** the vendor check fails

#### Scenario: Inherited git configuration cannot redirect the check

- **WHEN** the vendor check starts with a decoy `GIT_DIR` or `GIT_WORK_TREE`
- **THEN** it operates only on its intended scratch checkout and leaves the decoy untouched

### Requirement: Release-ready distribution

The module SHALL use the repository's shared version and normal publication process, before modules that depend on it. An isolated packaged consumer SHALL exercise its public API. Preparing this change SHALL not publish a version, and historical release status SHALL continue using each tag's original publication inventory.

#### Scenario: Publication dependency order

- **WHEN** the release tooling computes its module publication order
- **THEN** `moonrockz/regex` precedes `moonrockz/smithy-validation`
- **AND** the publication and release-status inventories agree

#### Scenario: Historical release status

- **WHEN** release status checks a tag from before this module existed
- **THEN** it does not require a `moonrockz/regex` publication for that historical version

# Serialization profile behavior

## Purpose

Make version-specific application JSON representations portable across runtime checking and codecs, while preserving explicit semantic model boundaries.

## ADDED Requirements

### Requirement: Portable named profile declarations

Representation rules SHALL be declared as model traits and named profiles with stable identifiers. Configuration SHALL select a declared profile rather than supply a second, conflicting set of representation rules. Profile preparation SHALL resolve one effective contract for every reachable shape.

#### Scenario: One model with two representations

- **WHEN** a model declares object and tagged-array profiles for the same root
- **THEN** callers can select either by identifier without editing the model or generating source
- **AND** both representations preserve the same logical shape and member identities

#### Scenario: Conflicting configuration

- **WHEN** configuration attempts to replace a profile's tag names, member positions or representation rules
- **THEN** the conflict is rejected rather than producing a contract different from the declared profile

### Requirement: Explicit profile resolution

A profile SHALL use selected-profile shape rules before its declared defaults, then applicable base traits and standard defaults. Incompatible declarations at the same precedence SHALL fail preparation. Unknown profiles and missing required bindings SHALL fail explicitly without falling back to a different profile.

#### Scenario: Shape-specific override

- **WHEN** a profile defaults unions to external tagging but explicitly selects adjacent tagging for one union
- **THEN** that union uses adjacent tagging and other unions retain the profile default

#### Scenario: Unknown profile identifier

- **WHEN** a caller requests an undeclared profile
- **THEN** preparation reports the missing profile and returns no prepared codec

### Requirement: Registered domain scalar adapters

A profile SHALL be able to reference a named scalar adapter supplied explicitly by the host. Preparation SHALL validate binding availability and supported input/output kinds. Adapter failures SHALL participate in source diagnostics and resource limits. Model content SHALL NOT execute arbitrary code or load adapters implicitly.

#### Scenario: Morphir name normalization

- **WHEN** a Morphir profile declares a registered name adapter and receives a supported legacy name spelling
- **THEN** decoding preserves the intended name identity and encoding emits that profile's canonical spelling

#### Scenario: Missing or untrusted adapter

- **WHEN** a model names an adapter that the host has not registered
- **THEN** preparation fails before processing the document
- **AND** the model does not cause a module, process or network resource to be loaded

### Requirement: Explicit shorthand dispatch

Compact-form dispatch SHALL use declared, bounded rules for JSON kinds and structural markers. It SHALL remain distinct from JSON-kind-only untagged scalar unions. Overlapping reader rules without a unique semantic interpretation SHALL fail; the order of declarations SHALL NOT decide the value.

#### Scenario: String shorthand with two meanings

- **WHEN** a Morphir profile distinguishes a bare type-variable name from a fully qualified reference using its declared naming rules
- **THEN** each valid string selects the intended semantic member
- **AND** two string-valued alternatives are not silently accepted as an ordinary untagged scalar union

#### Scenario: Ambiguous compact input

- **WHEN** an input matches compact rules for different semantic alternatives
- **THEN** decoding rejects the ambiguity with the original input location

### Requirement: Version-aware document dispatch

A versioned document bundle SHALL declare the version location, accepted version syntax, supported releases and the corresponding semantic roots and profiles. Dispatch SHALL select one root/profile before decoding the payload. Malformed, unsupported or explicitly conflicting versions SHALL be rejected without trial-decoding unrelated versions.

#### Scenario: Select a Morphir family

- **WHEN** a document declares a supported v3 or v4 format version
- **THEN** dispatch chooses its corresponding version-specific root and profile
- **AND** the returned value retains that version identity

#### Scenario: Header and explicit selection conflict

- **WHEN** a v3 artifact is supplied with an explicit v4 document selection
- **THEN** checking and decoding report the mismatch rather than interpreting the payload as v4

#### Scenario: Unsupported release

- **WHEN** a syntactically valid release falls outside the bundle's declared support intervals
- **THEN** dispatch reports an unsupported version distinctly from invalid version syntax

### Requirement: Semantic versions do not migrate implicitly

Version-specific roots SHALL remain distinct when their modeled meanings differ. Reading, checking, canonicalizing or selecting an output representation SHALL NOT migrate a document between those roots. Cross-version conversion requires an explicit conversion supplied outside this capability.

#### Scenario: Canonicalize a historical document

- **WHEN** a supported v3 artifact is decoded and re-encoded through its bundle
- **THEN** output remains v3 and does not acquire v4-only constructs

#### Scenario: Request a different semantic version

- **WHEN** a caller tries to encode a v4 value through an incompatible v3 root without conversion
- **THEN** encoding refuses the request without silently dropping information

### Requirement: Morphir v3 and v4 conformance bundles

The first acceptance bundles SHALL cover Morphir v3 and v4 single-file JSON artifacts, using pinned upstream codec/specification authorities and fixtures. Each bundle SHALL publish its supported release intervals and modeled coverage. Conformance SHALL cover full representative artifacts and individual recursive nodes, not only synthetic union examples.

#### Scenario: Historical tagged arrays

- **WHEN** the pinned v3 greeting artifact and its type, value and pattern nodes are checked and decoded
- **THEN** the v3 bundle accepts the declared historical positional encodings
- **AND** canonical re-encoding preserves their version-specific semantic values

#### Scenario: Modern compatible forms

- **WHEN** pinned v4 artifacts use valid compact, expanded or documented legacy spellings
- **THEN** the v4 bundle accepts them and emits its declared canonical output
- **AND** explicit expanded output represents the same logical value

#### Scenario: Limits of conformance

- **WHEN** coverage documentation describes a Morphir bundle
- **THEN** it distinguishes JSON representation and modeled Smithy constraints from Morphir type checking, reference resolution and other semantic passes
- **AND** v1/v2 and unsupported release families are not claimed as supported

### Requirement: Morphir canonical JSON policy

Morphir profiles SHALL implement the pinned JSON profile's numeric, duplicate-name, header and canonical-form policies. Readers SHALL accept permitted noncanonical spellings without changing semantic identity. Writers SHALL emit the declared canonical version spelling and header order.

#### Scenario: Baseline and exact release strings

- **WHEN** supported inputs use integer `4` or the equivalent baseline string `"4.0.0"`
- **THEN** both select the same baseline release and canonical baseline output uses integer `4`
- **AND** supported nonbaseline releases retain their exact release identity

#### Scenario: Input header order

- **WHEN** a permitted artifact puts `distribution` before `formatVersion`
- **THEN** reading succeeds
- **AND** canonical output puts `formatVersion` before `distribution`

### Requirement: Profile-aware command-line checking

The CLI SHALL support profile-aware application value checking and JSON canonicalization with model, root or bundle, and profile selection. Existing invocations without profile selection SHALL keep their behavior. Invalid values or incomplete checks SHALL exit 1; invalid configuration or unsupported selection SHALL exit 2.

#### Scenario: Check an individual node

- **WHEN** a caller selects a model, node root and declared profile without a document version envelope
- **THEN** the CLI checks the node using that explicit contract

#### Scenario: Failed canonicalization

- **WHEN** canonicalization encounters an invalid value, incompatible version or exhausted budget
- **THEN** the CLI returns the appropriate nonzero exit code
- **AND** it does not create, truncate or replace the requested output file

#### Scenario: Machine-readable diagnostics

- **WHEN** profile-aware checking requests JSON diagnostics
- **THEN** stdout contains one structured diagnostic result with validity and completeness
- **AND** findings identify the original input paths

### Requirement: Build configuration selects portable contracts

Build plugin configuration SHALL select declared profiles for JSON checking and canonicalization without redefining their wire rules. Unsupported profile-aware generation or schema export SHALL be refused when requested; declaring a profile SHALL NOT imply support in every consumer.

#### Scenario: Same selection through library and build

- **WHEN** library and build callers select the same model root, profile and scalar registry
- **THEN** they accept the same inputs and emit semantically equivalent canonical JSON

#### Scenario: Request unsupported profile-aware export

- **WHEN** a caller requests an alternate serialization profile from a generator or exporter without that capability
- **THEN** the request is rejected explicitly instead of emitting an object-only contract under that profile's name

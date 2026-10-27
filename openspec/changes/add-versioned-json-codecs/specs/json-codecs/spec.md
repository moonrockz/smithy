# JSON codec behavior

## Purpose

Provide one schema-driven application JSON contract for checking, reading and writing values across declared wire representations.

## ADDED Requirements

### Requirement: Reusable runtime codecs

The MoonBit runtime SHALL prepare a reusable codec for a model, root shape and selected profile. Checking, decoding and encoding SHALL use the same effective wire contract without requiring generated source code. Preparation SHALL refuse unsupported or inconsistent contracts.

#### Scenario: Prepare once and process multiple values

- **WHEN** a caller prepares a recursive data shape and selects an available profile
- **THEN** the caller can check, decode and encode multiple values with that prepared codec
- **AND** changing the source model after preparation does not alter the prepared contract

#### Scenario: Unsupported encoding declaration

- **WHEN** a reachable encoding declaration requires a capability the runtime does not implement
- **THEN** preparation fails with the offending shape and declaration identified
- **AND** the runtime does not silently fall back to an object-wrapped union

### Requirement: Explicit logical value identity

Decoded values SHALL retain their semantic root and union-member identities independently of JSON spelling. Encoding SHALL reject values incompatible with the selected model and root. Re-encoding through a different profile SHALL NOT itself convert values between different semantic model versions.

#### Scenario: Equivalent spellings retain the same alternative

- **WHEN** two accepted input forms represent the same union member and payload under one profile
- **THEN** decoding produces equal logical values with the same selected member

#### Scenario: Encode through an unrelated root

- **WHEN** a value decoded for one root is passed to an encoder for an incompatible root
- **THEN** encoding refuses the value without producing a document

### Requirement: Object-based tagged unions

Declared profiles SHALL support externally tagged, internally tagged and adjacently tagged unions. Tags and payload fields SHALL follow the effective declared wire names. Internal tagging SHALL require object-compatible alternatives and a discriminator that cannot collide with a payload member.

#### Scenario: Each object representation round-trips

- **WHEN** a union member with payload fields `left` and `right` is configured for external, internal or adjacent tagging
- **THEN** its respective forms `{"Add":{"left":1,"right":2}}`, `{"kind":"Add","left":1,"right":2}` and `{"kind":"Add","value":{"left":1,"right":2}}` decode to the selected member
- **AND** encoding emits the selected profile's declared form

#### Scenario: Invalid discriminator placement

- **WHEN** an internally tagged alternative is scalar-valued or declares a payload field with the discriminator's wire name
- **THEN** preparation rejects that representation

### Requirement: Tagged arrays and explicit positions

Declared profiles SHALL support tag-first arrays with explicit payload-member positions. Fixed tuples SHALL enforce arity; an explicitly declared trailing list SHALL collect remaining positions. Position mappings SHALL identify required members unambiguously and SHALL NOT derive from incidental member order.

#### Scenario: Positional payload validation

- **WHEN** `Add` declares positions `left` then `right` and receives `["Add",1,2]`
- **THEN** it decodes as `Add` with `left=1` and `right=2`
- **AND** a missing, extra or invalid fixed position is rejected at its source array path

#### Scenario: Declared trailing list

- **WHEN** a payload declares one fixed field followed by a trailing list field
- **THEN** the remaining elements are assigned to that list in order
- **AND** a declaration with a nonfinal rest field or overlapping positions fails preparation

### Requirement: Dictionary representations preserve key identity

Profiles SHALL support object dictionaries and two-element entry-array dictionaries with declared key adapters and canonical ordering. Reading SHALL reject duplicate logical keys after normalization. Encoding SHALL preserve key/value associations independently of the selected wire layout.

#### Scenario: Historical entry-array dictionary

- **WHEN** a dictionary profile reads an array of key/value pairs with declared key spellings
- **THEN** decoding preserves each logical key and its corresponding value
- **AND** canonical encoding follows the profile's declared key ordering

#### Scenario: Two spellings normalize to one key

- **WHEN** distinct wire entries normalize to the same logical key
- **THEN** decoding rejects the collision instead of retaining one entry

### Requirement: Deterministic untagged scalar unions

An untagged scalar union SHALL select its member by JSON kind. Preparation SHALL reject alternatives with overlapping accepted JSON kinds, including overlap introduced by scalar conversion policy. It SHALL NOT select an alternative by declaration order or unrestricted trial decoding. (bead: smithy-2qe.34.22)

#### Scenario: Number and string alternatives

- **WHEN** an untagged union contains a number alternative and a string alternative
- **THEN** a JSON number selects the number member and a JSON string selects the string member
- **AND** a boolean or object is rejected

#### Scenario: Ambiguous numeric alternatives

- **WHEN** an untagged union declares two alternatives that both accept JSON numbers
- **THEN** preparation refuses the overlap even if their numeric constraints differ

### Requirement: Accepted forms and canonical output

A profile SHALL distinguish accepted reader forms from canonical writer forms. Compact forms and reader aliases SHALL map to declared semantic fields. Writer selection SHALL be deterministic; absent required information or multiple applicable writer forms SHALL fail rather than choose by incidental order.

#### Scenario: Compact and expanded values

- **WHEN** a profile accepts both a scalar shorthand and an expanded object for the same value
- **THEN** both forms decode to an equivalent logical value
- **AND** encoding chooses the profile's canonical form, independent of the input spelling

#### Scenario: Explicit expanded output

- **WHEN** an expanded-output profile is explicitly selected
- **THEN** encoding uses its expanded form while preserving the logical value

#### Scenario: Alias collision

- **WHEN** a document supplies both a canonical member name and a reader alias for that same member
- **THEN** decoding rejects the collision instead of overwriting either value

### Requirement: Exact and duplicate-aware JSON boundaries

Text input SHALL preserve exact integer and finite decimal values and reject duplicate decoded object member names before a map can erase them. Output SHALL preserve numeric value without narrowing through host floating-point types. Formatting and accepted lexical aliases need not round-trip byte-for-byte.

#### Scenario: Large numeric literal

- **WHEN** a supported numeric shape receives an integer beyond binary64 exact precision or a finite decimal with significant fractional digits
- **THEN** decoding, checking and encoding preserve the exact numeric value

#### Scenario: Duplicate escaped member name

- **WHEN** an object contains `"name"` and `"\u006eame"`
- **THEN** text checking and decoding reject the duplicate before representation conversion

### Requirement: Consistent checks and source diagnostics

Under identical model, profile and limits, a complete successful check SHALL agree with decoding success. Both SHALL enforce existing applicable Smithy value constraints. Findings SHALL identify the semantic shape and original JSON path, including positions inside compact and positional forms.

#### Scenario: Constraint inside a tagged array

- **WHEN** the second payload element violates its target's numeric range
- **THEN** checking and decoding reject it and identify the original array position rather than a fabricated object-field path

#### Scenario: Invalid nested shorthand

- **WHEN** an accepted shorthand contains a value that violates its declared semantic target
- **THEN** checking and decoding report the original source location consistently

### Requirement: Bounded processing and incomplete results

Preparation and value traversal SHALL handle recursive shapes without recursive host-stack growth. Configurable input, depth, work and finding limits SHALL cover parsing, form selection, adapter expansion, constraint checking and output. Exhaustion SHALL never be reported as successful validation or yield a decoded value or partial output.

#### Scenario: Deep or wide hostile input

- **WHEN** an input exceeds a configured processing limit
- **THEN** checking reports an incomplete failure and decoding or encoding refuses to return a successful value
- **AND** the process does not panic or exceed its declared traversal budget

#### Scenario: Repeated recursive values

- **WHEN** a fixed-size recursive value is checked against increasing amounts of unrelated model content
- **THEN** preparation and checking avoid repeated expansion of the same recursive shape closure

### Requirement: Encoding validates before publishing output

Encoding SHALL verify logical shape compatibility and applicable constraints before making output available. An output target SHALL remain unwritten when validation, representation selection or resource limits fail.

#### Scenario: Invalid caller-constructed value

- **WHEN** a caller supplies an incomplete structure or an invalid union payload for encoding
- **THEN** encoding returns findings without returning or publishing partial JSON

### Requirement: Existing default behavior remains compatible

Without an explicitly selected serialization profile, existing value validation, JSON-RPC codecs, native-value validation and Smithy's JSON AST SHALL retain their current behavior. Declaring alternate document encodings SHALL NOT implicitly redefine an existing protocol.

#### Scenario: Existing value-validation invocation

- **WHEN** an existing caller uses the validator without a serialization profile
- **THEN** its union, naming, unknown-member and constraint policies remain unchanged

#### Scenario: Alternate trait on a shared shape

- **WHEN** a model declares an alternate document profile but an existing protocol is used without selecting that profile
- **THEN** that protocol retains its specified encoding rather than adopting the alternate form

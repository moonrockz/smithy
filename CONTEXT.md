# Smithy

Smithy describes data shapes and service contracts. This glossary distinguishes validating those definitions from validating application data.

## Language

**Model validation**:
Checking that a Smithy definition is well formed and semantically consistent.

**Instance validation**:
Checking an application value against a selected Smithy data shape and its constraints.

**Prepared validator**:
A reusable snapshot of the shape contract needed for instance validation.

**Finding**:
A classified validation observation associated with a location in an instance and a Smithy shape or member.

**Instance path**:
An ordered location within an application value, distinguishing array indices, field occurrences and map keys.

**Wire method name**:
The name a JSON-RPC message uses to select an operation, independently of the operation's Smithy shape ID.

**OpenRPC document version**:
The version of the API-description format, independent of the described service's API version and JSON-RPC wire version.

**Schema dialect**:
The JSON Schema version that defines the meaning of exported parameter and result schemas.

**Serialization profile**:
A named set of JSON representation rules that a model declares. Configuration selects a profile; it cannot change the profile's rules.

**Wire contract**:
The detached, prepared decisions of one root under one profile: layouts, tags, positions, forms and adapters.

**Semantic root**:
The identity of a logical contract: a root shape and the fingerprint of the shapes reachable from it. Profiles of one model and root share it; another version of a model does not.

**Compact form**:
A declared alternative spelling of a value, with a reader guard and an optional writer guard. Readers accept every declared form; writers emit one canonical form.

**Scalar adapter**:
Trusted host code, named by a model, that reads domain spellings of a scalar into one logical value and writes its canonical spelling.

**Document bundle**:
A set of version-specific roots and profiles. A document's version selects one root before the payload is read; no document changes version.

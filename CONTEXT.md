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

# smithy_tests

Test module for `moonrockz/smithy-syntax`, not published.

- `tck`: the compatibility kit, parity over the vendored reference corpus (see `NOTICE`).
- `bdd`: moonspec acceptance features from `tests/features`.

`tck/validation-events.json` records the exact event ID, severity and shape ID
multisets produced by Java Smithy 1.74.1 for all 277 validation models with paired
`.errors` files. Its source revision is `tck/validation/REFERENCE_SHA`. The
reference `.errors` files match message prefixes and hierarchical event IDs;
they are not complete event streams. The generated manifest includes suppressed
and deprecation events and is checked by `validation_audit_test.mbt`.

`tck/build-cases.json` declares 94 reference build cases covering all 28 built-in
transforms, environment expansion, local JAR inputs and projection imports.
`build-models.json` contains their Java model artifacts and failure events.
The manifest classifies all vendored resources and records exclusions for Java
test plugins, external processes and examples without their input files.
Focused tests cover source packaging and build-info fields separately.

Run `mise run tck:reference -- all` to regenerate both manifests from the clean,
pinned checkout at `.dev/out/reference-smithy`, or supply another checkout path
after `all`. Generation compiles the reference Java sources and requires a JDK.

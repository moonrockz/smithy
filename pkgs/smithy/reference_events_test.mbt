///|
/// The compared events of a one-file model in namespace `example`, as the tour
/// keys them: `id|SEVERITY|shape`, sorted.
fn reference_keys(body : String) -> Array[String] {
  reference_keys_of("$version: \"2\"\nnamespace example\n" + body + "\n")
}

///|
/// The compared events of the one-file model `text`.
fn reference_keys_of(text : String) -> Array[String] {
  let result = @smithy.Loader::new().add_idl("model.smithy", text).assemble()
  let keys = result
    .validation_events()
    .filter(e => {
      e.severity == "ERROR" || e.severity == "DANGER" || e.severity == "WARNING"
    })
    .map(e => {
      e.id +
      "|" +
      e.severity +
      "|" +
      e.shape.map(s => s.to_string()).unwrap_or("-")
    })
  keys.sort()
  keys
}

///|
test "an unknown trait is Model.UnresolvedTrait, as in Smithy" {
  assert_eq(reference_keys("@tag([\"geo\"])\nstructure City {}"), [
    "Model.UnresolvedTrait|ERROR|example#City",
  ])
}

///|
test "a shape without @trait used as a trait is reported on that shape once per use, as in Smithy" {
  assert_eq(
    reference_keys(
      "structure event {}\n@event\nstructure A {}\n@event\nstructure B {}",
    ),
    ["Model|ERROR|example#event", "Model|ERROR|example#event"],
  )
}

///|
test "a with target without @mixin is a Target error, as in Smithy" {
  assert_eq(
    reference_keys("structure Audited {}\nstructure City with [Audited] {}"),
    ["Target|ERROR|example#City"],
  )
}

///|
test "a mixin of another shape type stays a Model error, as in Smithy" {
  assert_eq(
    reference_keys("@mixin\nstring Name\nstructure City with [Name] {}"),
    ["Model|ERROR|example#City"],
  )
}

///|
/// The key of Smithy's `Model.BadDocumentationComment` event, which has no
/// shape.
let bad_doc : String = "Model.BadDocumentationComment|WARNING|-"

///|
test "a documentation comment after the traits of a shape is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(reference_keys("@required\n/// The name.\nstring Name"), [
    "TraitTarget|ERROR|example#Name", bad_doc,
  ])
  assert_eq(reference_keys("@deprecated\n/// x\n@sensitive\nstring Name"), [
    bad_doc,
  ])
  assert_eq(reference_keys("@deprecated\n/// x\n/// y\nstring S"), [bad_doc])
  assert_eq(reference_keys("/// good\n@deprecated\n/// bad\nstring S"), [
    bad_doc,
  ])
}

///|
test "a documentation comment after the traits of a member is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(
    reference_keys("structure S {\n    @required\n    /// x\n    a: String\n}"),
    [bad_doc],
  )
  assert_eq(
    reference_keys(
      "structure S {\n    @tags([\n        /// x\n        \"a\"\n    ])\n    a: String\n}",
    ),
    [bad_doc],
  )
  assert_eq(reference_keys("enum E {\n    @deprecated\n    /// x\n    A\n}"), [
    bad_doc,
  ])
  assert_eq(
    reference_keys("intEnum E {\n    @deprecated\n    /// x\n    A = 1\n}"),
    [bad_doc],
  )
  assert_eq(
    reference_keys(
      "operation O {\n    input := {\n        @required\n        /// x\n        a: String\n    }\n}",
    ),
    [bad_doc],
  )
}

///|
test "a documentation comment before the closing brace of members is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(
    reference_keys("structure S {\n    a: String\n    /// nothing\n}"),
    [bad_doc],
  )
  assert_eq(
    reference_keys("structure S {\n    a: String\n    /// x\n    /// y\n}"),
    [bad_doc],
  )
  assert_eq(reference_keys("structure S {\n    a: String /// x\n}"), [bad_doc])
}

///|
test "a documentation comment at the end of the file after a shape is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(reference_keys("string S\n/// trailing"), [bad_doc])
  assert_eq(reference_keys("string S\nstring T\n/// x\n/// y"), [bad_doc])
}

///|
test "a documentation comment before a control, metadata, namespace or use statement is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(
    reference_keys_of("/// x\n$version: \"2\"\nnamespace example\nstring S\n"),
    [bad_doc],
  )
  assert_eq(
    reference_keys_of("$version: \"2\"\n/// x\nnamespace example\nstring S\n"),
    [bad_doc],
  )
  assert_eq(
    reference_keys_of(
      "$version: \"2\"\n/// x\nmetadata foo = \"bar\"\nnamespace example\nstring S\n",
    ),
    [bad_doc],
  )
  assert_eq(
    reference_keys_of(
      "$version: \"2\"\n/// x\nmetadata a = [\n    /// y\n    1\n]\nnamespace example\nstring S\n",
    ),
    [bad_doc],
  )
  assert_eq(reference_keys("/// x\nuse smithy.api#String\nstring S"), [bad_doc])
  assert_eq(
    reference_keys(
      "use smithy.api#String\n/// x\nuse smithy.api#Integer\nstring S",
    ),
    [bad_doc],
  )
}

///|
test "a documentation comment inside a shape statement is a BadDocumentationComment warning, as in Smithy" {
  // Before the members: after the traits, between the name and `{`, in the mixins.
  assert_eq(reference_keys("@deprecated\n@sensitive\n/// x\nstructure S {}"), [
    bad_doc,
  ])
  assert_eq(reference_keys("structure S\n/// x\n{\n    a: String\n}"), [bad_doc])
  assert_eq(
    reference_keys(
      "@mixin\nstructure N {}\nstructure S with [\n    /// x\n    N\n] {}",
    ),
    [bad_doc],
  )
  // Inside a trait value, together with one after the traits: one warning.
  assert_eq(
    reference_keys("@tags([\n    /// x\n    \"a\"\n])\n/// y\nstring S"),
    [bad_doc],
  )
  // In an operation, service or resource body.
  assert_eq(
    reference_keys("operation O {\n    /// x\n    input: I\n}\nstructure I {}"),
    [bad_doc],
  )
  assert_eq(reference_keys("service Svc {\n    /// x\n    version: \"1\"\n}"), [
    bad_doc,
  ])
  assert_eq(
    reference_keys(
      "resource R {\n    identifiers: {\n        /// x\n        id: String\n    }\n}",
    ),
    [bad_doc],
  )
  assert_eq(
    reference_keys(
      "operation O {\n    errors: [\n        /// x\n        E\n    ]\n}\n@error(\"client\")\nstructure E {}",
    ),
    [bad_doc],
  )
  // After the traits of an inline structure.
  assert_eq(
    reference_keys(
      "operation O {\n    input := @sensitive\n    /// x\n    {}\n}",
    ),
    [bad_doc],
  )
}

///|
test "a documentation comment in an apply block is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(
    reference_keys("string Foo\napply Foo {\n    /// x\n    @deprecated\n}"),
    [bad_doc],
  )
  assert_eq(
    reference_keys("string Foo\napply Foo {\n    @deprecated\n    /// x\n}"),
    [bad_doc],
  )
}

///|
test "a documentation comment on the line of a statement or a value is a BadDocumentationComment warning, as in Smithy" {
  assert_eq(reference_keys("string S /// trailing\nstring T"), [bad_doc])
  assert_eq(reference_keys("string S /// x"), [bad_doc])
  assert_eq(reference_keys("string S\napply S @deprecated /// x\nstring T"), [
    bad_doc,
  ])
  assert_eq(reference_keys("enum E {\n    A = \"a\" /// x\n    B\n}"), [bad_doc])
  assert_eq(
    reference_keys(
      "structure S {\n    a: String = \"x\" /// y\n    b: String\n}",
    ),
    [bad_doc],
  )
  // The comment on the line of `S` is ignored; the next line documents `T`.
  assert_eq(reference_keys("string S /// a\n/// b\nstring T"), [bad_doc])
}

///|
test "documentation comments that Smithy reads or ignores silently give no event" {
  // Before the traits of a shape or member.
  assert_eq(reference_keys("/// The name.\n@sensitive\nstring Name"), [])
  assert_eq(
    reference_keys("structure S {\n    /// x\n    @required\n    a: String\n}"),
    [],
  )
  // Before `apply`: Smithy builds the event and drops it (IdlModelLoader.java:415).
  assert_eq(reference_keys("string Foo\n/// no\napply Foo @deprecated"), [])
  // Before `:=`, which drops the documentation read so far in the operation.
  assert_eq(reference_keys("operation O {\n    input /// x\n    := {}\n}"), [])
  assert_eq(reference_keys("operation O {\n    /// x\n    input := {}\n}"), [])
  assert_eq(
    reference_keys("@deprecated\n/// x\noperation O {\n    input := {}\n}"),
    [],
  )
  // At the end of a file without a shape statement.
  assert_eq(reference_keys("/// lonely"), [])
  assert_eq(reference_keys("use smithy.api#String\n/// x"), [])
  assert_eq(reference_keys_of("$version: \"2\"\n/// x\n"), [])
  assert_eq(reference_keys_of("$version: \"2\"\nmetadata a = 1\n/// x\n"), [])
  // On the line before a member or an inline structure, which it documents.
  assert_eq(
    reference_keys("structure S {\n    a: String /// x\n    b: String\n}"),
    [],
  )
  assert_eq(reference_keys("enum E {\n    A /// x\n    B\n}"), [])
  assert_eq(reference_keys("structure S { /// x\n    a: String\n}"), [])
  assert_eq(reference_keys("operation O {\n    input := /// x\n    {}\n}"), [])
}

///|
/// Smithy's `valid/doc-comments.smithy` and
/// `errorfiles/loader/detects-invalid-documentation-comments.smithy`, with the
/// events of the Java reference.
test "the reference documentation comment models give Smithy's events" {
  let expected_valid = Array::make(7, bad_doc)
  assert_eq(
    reference_keys_of(
      (
        #|/// This comment is ignored.
        #|$version: "2.0"
        #|
        #|/// This comment is ignored.
        #|metadata foo = [
        #|    /// This comment is ignored.
        #|    "bar"
        #|]
        #|
        #|/// This comment is ignored.
        #|namespace smithy.example
        #|
        #|// The previous doc comment does not affect this shape,
        #|// and this shape is not documented.
        #|string NotDocumented
        #|
        #|/// Foo
        #|/// baz
        #|/// Bar!
        #|string MyString
        #|
        #|/// Structure
        #|structure MyStructure {
        #|    /// Docs on member!
        #|    foo: String = "hi",
        #|
        #|    /// Docs on another member!
        #|    @required
        #|    /// IMPORTANT: These docs are ignored since they come after traits!
        #|    baz: String,
        #|
        #|    /// I'll only have this documentation.
        #|    boot: String
        #|
        #|    // no docs.
        #|    bam: String,
        #|}
        #|
        #|/// The documentation
        #|/// of this trait!
        #|@trait
        #|/// IMPORTANT: These docs are ignored since they come after traits!
        #|structure MyTrait {
        #|    /// These are treated as comments.
        #|    /// more...
        #|}
        #|
        #|operation MyOperation {
        #|    input
        #|        /// These docs are ignored because they come BEFORE the walrus
        #|        /// operator.
        #|        := {}
        #|
        #|    output :=
        #|        /// These are not ignored because they come AFTER the walrus
        #|        /// operator.
        #|        {}
        #|}
        #|
        #|/// This is treated as a comment because it comes before apply.
        #|apply MyOperation @deprecated
        #|
        #|/// This is treated as a comment.
        #|
      ),
    ),
    expected_valid,
  )
  let expected_invalid = Array::make(9, bad_doc)
  expected_invalid.push("ModelDeprecation|WARNING|smithy.example#Features")
  assert_eq(
    reference_keys_of(
      (
        #|/// Invalid 1 (before control)
        #|$version: "2.0"
        #|
        #|/// Invalid 2 (before namespace)
        #|namespace smithy.example
        #|
        #|/// Invalid 3 (before use)
        #|use smithy.api#Boolean
        #|
        #|@enum([
        #|    /// Invalid 4 (inside trait)
        #|    { name: "X", value: "X"}
        #|])
        #|/// Invalid 5 (not before traits)
        #|string Features /// Valid docs for Foo
        #|
        #|@sensitive
        #|/// Invalid 6 (not before traits)
        #|map Foo
        #|/// Invalid 7 (inside shape line)
        #|{
        #|    key: Features,
        #|    value: Boolean
        #|    /// Invalid 8 (dangling)
        #|}
        #|
        #|structure Bar {
        #|    @required
        #|    /// Invalid 9 (not before traits)
        #|    baz: Boolean
        #|    /// Invalid 10 (dangling)
        #|}
        #|
        #|/// Invalid 11 (dangling)
        #|
      ),
    ),
    expected_invalid,
  )
}

///|
test "an elided member that nothing defines is one Model error on the member, as in Smithy" {
  assert_eq(
    reference_keys(
      "resource R {\n    identifiers: { id: String }\n    properties: { name: String }\n    read: Get\n}\n" +
      "@readonly\noperation Get {\n    input := for R {\n        @required\n        $id\n    }\n" +
      "    output := for R {\n        $population\n    }\n}",
    ),
    ["Model|ERROR|example#GetOutput$population"],
  )
}

///|
/// The IDL diagnostic codes and validation event IDs of the one-file model
/// `text`.
fn hints_and_events(text : String) -> (Array[String], Array[String]) {
  let result = @smithy.Loader::new().add_idl("model.smithy", text).assemble()
  (
    result.diagnostics.map(d => d.code),
    result.validation_events().map(e => e.id),
  )
}

///|
test "a documentation comment that Smithy drops silently stays a diagnostic for tools, with no event" {
  // Before `apply`: Smithy builds the event and drops it (IdlModelLoader.java:415).
  assert_eq(
    hints_and_events(
      "$version: \"2\"\nnamespace example\nstring Foo\n/// no\napply Foo @deprecated\n",
    ),
    (["SM-PARSE-008"], []),
  )
  // At the end of a file without a shape statement: Smithy never reads it.
  assert_eq(
    hints_and_events("$version: \"2\"\nnamespace example\n/// lonely\n"),
    (["SM-PARSE-016"], []),
  )
}

///|
test "an elided member that a mixin does not define is one Model error on the member, as in Smithy" {
  assert_eq(
    reference_keys(
      "@mixin\nstructure M {\n    y: String\n}\nstructure S with [M] {\n    $x\n}",
    ),
    ["Model|ERROR|example#S$x"],
  )
}

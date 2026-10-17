///|
fn codes(text : String) -> Array[String] {
  @parser.parse_text(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "control, metadata, namespace and use parse in order" {
  let r = @parser.parse_text(
    (
      #|$version: "2"
      #|metadata a = "x"
      #|namespace com.foo
      #|use smithy.api#String
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  @expect.expect_all(e => {
    e.expect(r.has_errors()).to_be_false()
    e.expect(r.version).to_equal(Some(V2))
    e.expect(f.control.length()).to_equal(1)
    e.expect(f.metadata[0].key.value).to_equal("a")
    e.expect(f.namespace.map(n => n.namespace.value)).to_equal(Some("com.foo"))
    e.expect(f.uses[0].id.value.to_string()).to_equal("smithy.api#String")
    e.expect(r.cst.statements.length()).to_equal(4)
    e
    .expect(r.cst.to_source())
    .to_equal(
      (
        #|$version: "2"
        #|metadata a = "x"
        #|namespace com.foo
        #|use smithy.api#String
        #|
      ),
    )
  })
}

///|
/// `ControlStatement = "$" NodeObjectKey [SP] ":" [SP] NodeValue BR`: only
/// `[SP]` around `:`, not a line break or a comment. Pins the reference's
/// `invalid/control/control-newline.smithy` and `control-colon-newline.smithy`.
test "a control statement's key and value must stay on one line" {
  @expect.expect(
    codes(
      (
        #|$version
        #|: "2"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  @expect.expect(
    codes(
      (
        #|$version:
        #|"2"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
}

///|
/// Pins the reference's `invalid/control/control-version-defined-twice.smithy`.
test "a control statement key may be set at most once" {
  @expect.expect(
    codes(
      (
        #|$version: "2"
        #|$version: "2"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-013"])
}

///|
/// A duplicate `$version` must not change the version the first one set,
/// so later version gating follows the first statement.
test "a duplicate version keeps the first version in force" {
  let r = @parser.parse_text(
    (
      #|$version: "1"
      #|$version: "2"
      #|namespace a
      #|
      #|string S with [M]
      #|
    ),
  )
  @expect.expect(r.diagnostics.map(d => d.code)).to_equal([
    "SM-PARSE-013", "SM-PARSE-007",
  ])
  debug_inspect(r.version, content="Some(V1)")
}

///|
/// `MetadataStatement = "metadata" SP NodeObjectKey [SP] "=" [SP] NodeValue
/// BR`: a mandatory `SP` right after `metadata`, then only `[SP]` (not a
/// line break or a comment) around the key and `=`. Pins the reference's
/// `invalid/metadata/not-newline-after-metadata.smithy`,
/// `space-after-metadata-quoted.smithy` and `metadata-multiple-lines.smithy`.
test "a metadata statement's key and value must stay on one line" {
  @expect.expect(
    codes(
      (
        #|metadata
        #|foo = "bar"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  @expect.expect(
    codes(
      (
        #|metadata"foo"="bar"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  @expect.expect(
    codes(
      (
        #|metadata foo =
        #|"bar"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
}

///|
/// `NamespaceStatement = "namespace" SP Namespace BR` and `UseStatement =
/// "use" SP AbsoluteRootShapeId BR`: only `[SP]` right after the keyword,
/// not a line break or a comment. Pins the reference's
/// `invalid/namespace/namespace-multiple-lines.smithy` and
/// `invalid/use/use-multiple-lines.smithy`.
test "namespace and use must stay on one line as their keyword" {
  @expect.expect(
    codes(
      (
        #|namespace
        #|com.foo
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  @expect.expect(
    codes(
      (
        #|namespace com.foo
        #|use
        #|smithy.api#String
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
}

///|
/// A missing value, namespace segment or shape name right at the true
/// end of a file that ends with a line break is reported right after
/// the last real token, not on the synthetic empty line after the final
/// break. Pins the reference's `invalid/control/control-missing-value.smithy`,
/// `invalid/namespace/namespace-syntax-error.smithy` and
/// `invalid/use/use-missing-after-namespace.smithy`.
test "a missing value, namespace segment or shape name at EOF is reported right after the last token" {
  fn ends_before_eof(text : String) -> Bool raise {
    let r = @parser.parse_text(text)
    let errs = r.diagnostics.iter().filter(d => d.is_error()).collect()
    guard errs.length() > 0 else { fail("no error") }
    errs[0].span.start == errs[0].span.end() &&
    errs[0].span.start.0 < r.cst.to_source().length()
  }

  @expect.expect_all(e => {
    e
    .expect(
      ends_before_eof(
        (
          #|$version:
          #|
        ),
      ),
    )
    .to_be_true()
    e
    .expect(
      ends_before_eof(
        (
          #|namespace com.
          #|
        ),
      ),
    )
    .to_be_true()
    e
    .expect(
      ends_before_eof(
        (
          #|namespace smithy.example
          #|use smithy.api#
          #|
        ),
      ),
    )
    .to_be_true()
  })
}

///|
test "an unsupported version is SM-PARSE-006" {
  @expect.expect(
    codes(
      (
        #|$version: "3"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-006"])
  @expect.expect(
    codes(
      (
        #|$version: "1.0"
        #|
      ),
    ),
  ).to_equal([])
  debug_inspect(
    @parser.parse_text(
      (
        #|$version: "1"
        #|
      ),
    ).version,
    content="Some(V1)",
  )
  debug_inspect(
    @parser.parse_text(
      (
        #|namespace a
        #|
      ),
    ).version,
    content="None",
  )
}

///|
test "two statements on one line is MISSING LINE BREAK, also with CRLF files" {
  @expect.expect(
    codes(
      (
        #|namespace a use b#C
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-003"])
  @expect.expect(codes("namespace a\r\nuse b#C\r\n")).to_equal([])
  @expect.expect(
    codes(
      (
        #|namespace a // ok
        #|use b#C
        #|
      ),
    ),
  ).to_equal([])
  let r = @parser.parse_text(
    (
      #|namespace a use b#C
      #|
    ),
  )
  inspect(r.diagnostics[0].title, content="MISSING LINE BREAK")
  inspect(
    r.diagnostics[0].message,
    content="I was expecting a line break here but found `use`",
  )
}

///|
test "metadata after the namespace is EXPECTED A STATEMENT with an ordering note" {
  let r = @parser.parse_text(
    (
      #|namespace a
      #|metadata x = "y"
      #|
    ),
  )
  @expect.expect(
    codes(
      (
        #|namespace a
        #|metadata x = "y"
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-004"])
  inspect(
    r.diagnostics[0].notes[0],
    content="Control statements (`$...`) come first, then `metadata`, then `namespace`.",
  )
  @expect.expect(
    codes(
      (
        #|use a#B
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-004"])
}

///|
test "a missing namespace is reported once and the shapes after it still parse" {
  let r = @parser.parse_text(
    (
      #|string Foo
      #|string Bar
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  @expect.expect_all(e => {
    e.expect(r.diagnostics.map(d => d.code)).to_equal(["SM-PARSE-004"])
    e.expect(r.diagnostics[0].title).to_equal("MISSING NAMESPACE")
    e.expect(f.shapes().length()).to_equal(2)
  })
}

///|
test "a use statement needs an absolute id" {
  @expect.expect(
    codes(
      (
        #|namespace a
        #|use Foo
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-005"])
  @expect.expect(
    codes(
      (
        #|namespace a
        #|use a.b#Foo$bar
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-005"])
}

///|
test "recovery skips to the next statement and keeps the CST lossless" {
  let text =
    #|namespace a
    #|use Foo
    #|use smithy.api#String
    #|
  let r = @parser.parse_text(text)
  guard r.ast is Some(f) else { fail("no ast") }
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(f.uses.length()).to_equal(1)
    e.expect(r.cst.skipped().length()).to_equal(1)
    e
    .expect(r.cst.skipped()[0].to_source())
    .to_equal(
      (
        #|use Foo
        #|
      ),
    )
    e.expect(r.cst.to_source()).to_equal(text)
  })
}

///|
test "recovery is not fooled by a comma into stopping at column 1" {
  // A leading `,` means `use` is not at column 1, so the skipped run
  // swallows the whole second line too, instead of stopping right
  // before it and parsing `use a#B` as a second statement.
  let text =
    #|namespace a
    #|use Foo
    #|,use a#B
    #|
  let r = @parser.parse_text(text)
  @expect.expect_all(e => {
    e.expect(r.cst.skipped().length()).to_equal(1)
    e
    .expect(r.cst.skipped()[0].to_source())
    .to_equal(
      (
        #|use Foo
        #|,use a#B
        #|
      ),
    )
  })
}

///|
test "an empty file is an empty IdlFile with no errors" {
  let r = @parser.parse_text("")
  guard r.ast is Some(f) else { fail("no ast for an empty file") }
  inspect(f.statements.length(), content="0")
  inspect(f.span.is_empty(), content="true")
  inspect(r.has_errors(), content="false")
  let r = @parser.parse_text(
    (
      #|// just a comment
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast for a comment-only file") }
  inspect(f.statements.length(), content="0")
  inspect(f.span.is_empty(), content="true")
  inspect(r.has_errors(), content="false")
}

///|
test "doc comments before a namespace are detached warnings" {
  let r = @parser.parse_text(
    (
      #|/// hi
      #|namespace a
      #|
    ),
  )
  @expect.expect(
    codes(
      (
        #|/// hi
        #|namespace a
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-009"])
  inspect(r.has_errors(), content="false")
  inspect(r.diagnostics[0].title, content="DETACHED DOC COMMENT")
}

///|
test "a scanner error is a hole the parser steps over" {
  let r = @parser.parse_text(
    (
      #|namespace a
      #|^
      #|use a#B
      #|
    ),
  )
  @expect.expect(
    codes(
      (
        #|namespace a
        #|^
        #|use a#B
        #|
      ),
    ),
  ).to_equal(["SM-SCAN-001"])
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.uses.length(), content="1")
}

///|
test "use after a shape is reported even without a namespace" {
  let r = @parser.parse_text("string S\nuse a#B\n")
  inspect(r.errors().length(), content="2")
  inspect(r.errors()[1].title, content="EXPECTED A STATEMENT")
}

///|
test "a trailing scanner error does not widen a shape or apply span" {
  for
    body in [
      "string S", "structure S {}", "apply S @required", "operation O {input := {}}",
    ] {
    let prefix = "$version: \"2\"\nnamespace a\n"
    let text = prefix + body + " %\n"
    let r = @parser.parse_text(text)
    guard r.ast is Some(f) else { fail("no ast") }
    assert_eq(f.statements[0].span().end().0, prefix.length() + body.length())
    assert_eq(r.cst.to_source(), text)
  }
}

///|
test "recovery keeps scanner holes at a documentation statement boundary" {
  let text = "@\nnamespace a\nuse a#B\n/// orphan\n😀"
  let r = @parser.parse_text(text)
  let joined = r.cst.statements
    .iter()
    .map(s => s.to_source())
    .fold(init="", (a, b) => a + b)
  assert_eq(joined, text)
}

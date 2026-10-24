///|
fn dmodel(body : String) -> @parser.ParseResult {
  @parser.parse_text(
    (
      $|$version: "2"
      $|namespace com.foo
      $|
      $|\{body}
    ),
  )
}

///|
fn dcodes(body : String) -> Array[String] {
  dmodel(body).diagnostics.iter().map(d => d.code).collect()
}

///|
test "doc comments attach to shapes, members, enum members and inline shapes" {
  let r = dmodel(
    (
      #|/// Shape docs.
      #|/// Second line.
      #|@a
      #|structure S {
      #|    /// Member docs.
      #|    @b
      #|    m: String
      #|}
      #|
      #|operation Op {
      #|    input :=
      #|    /// Inline docs.
      #|    {}
      #|}
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  let ss = f.shapes()
  @expect.expect_all(e => {
    e.expect(r.has_errors()).to_be_false()
    e
    .expect(ss[0].docs.map(d => d.text))
    .to_equal([" Shape docs.", " Second line."])
  })
  guard ss[0].shape is Aggregate(members~, ..) else { fail("no members") }
  inspect(members[0].docs[0].text, content=" Member docs.")
  guard ss[1].shape is Operation(properties~, ..) &&
    properties[0] is Input(Inline(inline), _) else {
    fail("no inline")
  }
  inspect(inline.docs[0].text, content=" Inline docs.")
}

///|
test "docs between the traits and the keyword are a warning, not documentation" {
  let r = dmodel(
    (
      #|@a
      #|/// late
      #|string S
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.shapes()[0].docs.length(), content="0")
  inspect(r.has_errors(), content="false")
  @expect.expect(r.diagnostics.map(d => d.code)).to_equal(["SM-PARSE-009"])
  inspect(
    r.diagnostics[0].message,
    content="I ignored the documentation comment `/// late`, because it is not right before a shape or member and its traits",
  )
}

///|
test "the documentation comments ignored before one line break give one warning" {
  let r = dmodel(
    (
      #|@tags([
      #|    /// inside
      #|    "a"
      #|])
      #|/// after
      #|string S
      #|
    ),
  )
  @expect.expect(r.diagnostics.map(d => d.code)).to_equal(["SM-PARSE-009"])
  let d = r.diagnostics[0]
  @expect.expect_all(e => {
    e
    .expect(d.message)
    .to_equal(
      "I ignored 2 documentation comments, from `/// inside`, because they are not right before a shape or member and its traits",
    )
    e.expect(d.labels.map(l => l.text)).to_equal(["I also ignored this one"])
  })
}

///|
test "documentation comments after member traits, before a brace or on a statement line are warnings" {
  @expect.expect_all(e => {
    e
    .expect(
      dcodes(
        (
          #|structure S {
          #|    @required
          #|    /// x
          #|    a: String
          #|}
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-009"])
    e
    .expect(
      dcodes(
        (
          #|structure S
          #|/// x
          #|{}
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-009"])
    e
    .expect(
      dcodes(
        (
          #|string S /// x
          #|string T
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-009"])
    e
    .expect(
      dcodes(
        (
          #|enum E {
          #|    A = "a" /// x
          #|    B
          #|}
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-009"])
    e
    .expect(
      dcodes(
        (
          #|string Foo
          #|apply Foo {
          #|    @deprecated
          #|    /// x
          #|}
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-009"])
  })
}

///|
test "documentation comments that Smithy reads or drops are not warnings" {
  @expect.expect_all(e => {
    // On the line before a member: Smithy reads it, the AST keeps it as a comment.
    let r = dmodel(
      (
        #|structure S {
        #|    a: String /// x
        #|    b: String
        #|}
        #|
      ),
    )
    e.expect(r.diagnostics.length()).to_equal(0)
    guard r.ast is Some(f) && f.shapes()[0].shape is Aggregate(members~, ..) else {
      fail("no members")
    }
    // Smithy documents `S$b` with `x` here (smithy-2qe.41.20). Change this
    // expectation when the AST follows it.
    e.expect(members[1].docs.length()).to_equal(0)
    // Before `:=`.
    e
    .expect(
      dcodes(
        (
          #|operation O {
          #|    /// x
          #|    input := {}
          #|}
          #|
        ),
      ),
    )
    .to_equal([])
  })
}

///|
test "a documentation comment at the end of a file without a shape is its own warning" {
  // Smithy drops it without an event, so it has a code of its own.
  let r = dmodel(
    (
      #|/// x
      #|/// y
      #|
    ),
  )
  @expect.expect(r.diagnostics.map(d => d.code)).to_equal(["SM-PARSE-016"])
  @expect.expect_all(e => {
    e.expect(r.has_errors()).to_be_false()
    e
    .expect(r.diagnostics[0].message)
    .to_equal(
      "I ignored 2 documentation comments, from `/// x`, because no shape follows them",
    )
  })
}

///|
test "a statement that fails keeps no warning for the documentation comments it read" {
  @expect.expect(
    dcodes(
      (
        #|@deprecated
        #|/// x
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-004"])
}

///|
test "a doc comment with no shape after it is a warning" {
  @expect.expect(
    dcodes(
      (
        #|string S
        #|/// trailing
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-009"])
  @expect.expect(
    dcodes(
      (
        #|structure S {
        #|  a: String
        #|  /// nothing
        #|}
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-009"])
  inspect(
    dmodel(
      (
        #|string S
        #|/// trailing
        #|
      ),
    ).has_errors(),
    content="false",
  )
}

///|
/// Pins the reference's `valid/doc-comments.smithy`: a doc comment right
/// before `apply` is read as an ordinary comment, with only a warning (not
/// an error), since `apply` cannot take documentation.
test "docs before apply are a warning, not an error" {
  @expect.expect(
    dcodes(
      (
        #|/// no
        #|apply Foo @a
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-008"])
  inspect(
    dmodel(
      (
        #|/// no
        #|apply Foo @a
        #|
      ),
    ).has_errors(),
    content="false",
  )
}

///|
test "version 1 files reject 2.0 syntax with the reference's facts" {
  fn v1(body : String) -> Array[String] {
    @parser.parse_text(
      (
        $|$version: "1.0"
        $|namespace com.foo
        $|\{body}
      ),
    ).diagnostics
    .iter()
    .map(d => d.code)
    .collect()
  }

  @expect.expect_all(e => {
    e
    .expect(
      v1(
        (
          #|string S with [M]
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-007"])
    e
    .expect(
      v1(
        (
          #|structure S { $a }
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-007"])
    e
    .expect(
      v1(
        (
          #|structure S for R {}
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-007"])
    e
    .expect(
      v1(
        (
          #|operation O { input := {} }
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-007"])
    e
    .expect(
      v1(
        (
          #|structure S { a: String = "x" }
          #|
        ),
      ),
    )
    .to_equal(["SM-PARSE-007"])
    e
    .expect(
      v1(
        (
          #|structure S { a: String }
          #|
        ),
      ),
    )
    .to_equal([])
  })
  // A missing $version means 1.0.
  @expect.expect(
    @parser.parse_text(
      (
        #|namespace com.foo
        #|string S with [M]
        #|
      ),
    ).diagnostics
    .iter()
    .map(d => d.code)
    .collect(),
  ).to_equal(["SM-PARSE-007"])
  inspect(
    @parser.parse_text(
      (
        #|namespace a
        #|string S with [M]
        #|
      ),
    ).errors()[0].message,
    content="Mixins can only be used with Smithy version 2 or later",
  )
}

///|
test "binding a structure to a resource in IDL 1.0 names the binding, not resource properties" {
  let r = @parser.parse_text(
    (
      #|namespace a
      #|structure S for R {}
      #|
    ),
  )
  @expect.expect(r.diagnostics.iter().map(d => d.code).collect()).to_equal([
    "SM-PARSE-007",
  ])
  inspect(
    r.errors()[0].message,
    content="Structures can only be bound to resources with Smithy version 2 or later",
  )
}

///|
test "a broken control statement makes the version unknown, not 1.0, so v2 gating does not fire" {
  let r = @parser.parse_text(
    (
      #|$ver""ion: "2"
      #|namespace a
      #|string S with [M]
      #|
    ),
  )
  @expect.expect(r.diagnostics.iter().map(d => d.code).collect()).to_equal([
    "SM-PARSE-001",
  ])
}

///|
test "a statement that swallows the $version line also makes the version unknown" {
  let r = @parser.parse_text(
    (
      #|"a
      #|b"$version: "2"
      #|namespace a
      #|string S with [M]
      #|
    ),
  )
  @expect.expect_all(e => {
    e
    .expect(r.diagnostics.iter().any(d => d.code == "SM-PARSE-007"))
    .to_be_false()
    e.expect(r.errors().length()).to_equal(1)
  })
}

///|
test "a 1.0 file reports its 2.0-only constructs once, at the first" {
  let r = @parser.parse_text(
    (
      #|$version: "1.0"
      #|namespace a
      #|structure S with [M] {}
      #|structure T for R { $id }
      #|operation O { input := {} }
      #|
    ),
  )
  let gated = r.diagnostics.filter(d => d.code == "SM-PARSE-007")
  @expect.expect_all(e => {
    e.expect(gated.length()).to_equal(1)
    e
    .expect(gated[0].message)
    .to_equal("Mixins can only be used with Smithy version 2 or later")
  })
}

///|
test "a 2.0 file reports its set shapes once, at the first" {
  let r = @parser.parse_text(
    (
      #|$version: "2"
      #|namespace a
      #|set A { member: String }
      #|set B { member: String }
      #|
    ),
  )
  @expect.expect(r.diagnostics.iter().map(d => d.code).collect()).to_equal([
    "SM-PARSE-015",
  ])
  @expect.expect(r.diagnostics[0].message).to_equal(
    "set shapes cannot be used in Smithy version 2.0",
  )
}

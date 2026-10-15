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
      #|    /// Inline docs.
      #|    input := {}
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
test "docs between the traits and the keyword still attach" {
  let r = dmodel(
    (
      #|@a
      #|/// late
      #|string S
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.shapes()[0].docs.length(), content="1")
  inspect(r.has_errors(), content="false")
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
test "docs before apply are an error" {
  @expect.expect(
    dcodes(
      (
        #|/// no
        #|apply Foo @a
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-008"])
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

///|
fn rmodel(body : String) -> @parser.ParseResult {
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
test "a broken structure yields one error and the next shape survives" {
  let r = rmodel(
    (
      #|structure Bad {
      #|  a String
      #|}
      #|
      #|string Foo
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  let names = f.shapes().map(s => s.shape.name().value)
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(names).to_equal(["Bad", "Foo"])
    e.expect(r.cst.skipped().length()).to_equal(0)
  })
}

///|
test "an unclosed brace still lets the next statement parse" {
  let r = rmodel(
    (
      #|structure Bad {
      #|  a: String
      #|
      #|string Foo
      #|
      #|@deprecated
      #|string Bar
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  let names = f.shapes().map(s => s.shape.name().value)
  // Recovery resumes at the column-1 `string Foo`, then keeps Bar too.
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(names).to_equal(["Foo", "Bar"])
    e.expect(r.cst.skipped().length()).to_equal(1)
    e
    .expect(r.cst.to_source().length())
    .to_equal(
      r.cst.tokens
      .iter()
      .map(t => t.to_source().length())
      .fold(init=0, (a, b) => a + b),
    )
  })
}

///|
test "every statement form appears in the CST with its name" {
  let r = @parser.parse_text(@lawkit.small_model())
  inspect(r.has_errors(), content="false")
  let kinds = r.cst.statements
    .iter()
    .map(s => "\{s.kind}=\{s.name.unwrap_or("")}")
    .collect()
  @expect.expect(kinds[0]).to_equal("Control=version")
  @expect.expect(kinds[1]).to_equal("Metadata=foo")
  @expect.expect(kinds[2]).to_equal("Namespace=smithy.example")
  @expect.expect(kinds[3]).to_equal("Use=smithy.api#String")
  @expect.expect(kinds[4]).to_equal("Shape(structure)=Foo")
  @expect.expect(kinds[kinds.length() - 1]).to_equal("Apply=Foo")
}

///|
test "the reference's error-recovery cases: resume at a doc comment, a dollar, an identifier and a trait" {
  let to_docs =
    #|structure Bad {
    #|  a:
    #|
    #|/// docs
    #|string Foo
    #|
  let to_dollar =
    #|metadata x = [1,
    #|
    #|$version: "2"
    #|string Foo
    #|
  let to_identifier =
    #|structure Bad {
    #|  a:
    #|
    #|string Foo
    #|
  let to_trait =
    #|structure Bad {
    #|  a:
    #|
    #|@deprecated
    #|string Foo
    #|
  for body in [to_docs, to_identifier, to_trait] {
    let r = rmodel(body)
    guard r.ast is Some(f) else { fail("no ast for \{body}") }
    @expect.expect(r.errors().length()).because(body).to_equal(1)
    @expect.expect(f.shapes().map(s => s.shape.name().value).contains("Foo"))
    .because(body)
    .to_be_true()
  }
  // The dollar case resumes at `$version`, which is itself a true error after
  // the namespace (a control statement out of order), so two errors at most.
  let r = rmodel(to_dollar)
  guard r.ast is Some(f) else { fail("no ast for the dollar case") }
  @expect.expect(r.errors().length() <= 2).to_be_true()
  @expect.expect(f.shapes().map(s => s.shape.name().value).contains("Foo")).to_be_true()
}

///|
test "a failed statement with leading docs and traits is reported once" {
  let missing_name =
    #|/// docs
    #|@deprecated
    #|structure {}
    #|
  let bad_mixins =
    #|@deprecated
    #|string S with
    #|
  let then_next =
    #|/// docs
    #|@deprecated
    #|structure {}
    #|
    #|string Foo
    #|
  for body in [missing_name, bad_mixins, then_next] {
    let r = rmodel(body)
    @expect.expect(r.diagnostics.length()).because(body).to_equal(1)
  }
  let r = rmodel(then_next)
  guard r.ast is Some(f) else { fail("no ast") }
  @expect.expect(f.shapes().map(s => s.shape.name().value)).to_equal(["Foo"])
}

///|
test "recovery after traits before apply resumes at the apply" {
  let r = rmodel(
    (
      #|@deprecated
      #|apply Foo @sensitive
      #|
      #|string Bar
      #|
    ),
  )
  let skipped = r.cst.statements.filter(s => s.kind is Skipped)
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(skipped.length()).to_equal(1)
    e
    .expect(skipped[0].tokens.iter().any(t => t.lexeme == "apply"))
    .to_be_false()
    e.expect(r.cst.statements.iter().any(s => s.kind is Apply)).to_be_true()
    e
    .expect(r.cst.statements.iter().any(s => s.name == Some("Bar")))
    .to_be_true()
  })
}

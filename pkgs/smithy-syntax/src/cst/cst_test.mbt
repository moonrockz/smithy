///|
fn o(n : Int32) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(x) else { fail("bad offset") }
  x
}

///|
test "statements tile the stream and print the source back" {
  let text =
    #|namespace a.b
    #|
    #|string Foo // c
    #|
  let s = @scanner.tokenize_text(text)
  let ns = @cst.StatementCst::new(
    kind=Namespace,
    name=Some("a.b"),
    tokens=s.tokens[0:4],
  )
  let foo = @cst.StatementCst::new(
    kind=Shape(Simple(String)),
    name=Some("Foo"),
    tokens=s.tokens[4:6],
  )
  let cst = @cst.IdlCst::new(s, [ns, foo])
  @expect.expect_all(e => {
    e.expect(cst.to_source()).to_equal(text)
    e
    .expect(ns.to_source())
    .to_equal(
      (
        #|namespace a.b
        #|
      ),
    )
    e
    .expect(foo.to_source())
    .to_equal(
      (
        #|
        #|string Foo // c
        #|
      ),
    )
    e.expect(ns.span).to_equal(o(0).to(o(13)))
    e.expect(foo.span).to_equal(o(15).to(o(25)))
    e.expect(cst.skipped().length()).to_equal(0)
  })
}

///|
test "an empty statement has an empty span" {
  let s = @scanner.tokenize_text("")
  let st = @cst.StatementCst::new(kind=Skipped, name=None, tokens=s.tokens[0:0])
  debug_inspect(st.span, content="{ start: Offset(0), length: Length(0) }")
  inspect(@cst.IdlCst::new(s, [st]).to_source(), content="")
}

///|
test "a text with only trivia prints back" {
  let s = @scanner.tokenize_text(
    (
      #|// only
      #|
    ),
  )
  inspect(
    @cst.IdlCst::new(s, []).to_source(),
    content=(
      #|// only
      #|
    ),
  )
}

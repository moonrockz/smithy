///|
fn tmodel(body : String) -> @parser.ParseResult {
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
fn traits_of(body : String) -> Array[@ast.Trait] raise {
  let r = tmodel(body)
  guard r.ast is Some(f) && f.shapes().length() > 0 else {
    fail(
      "no shape: " + r.diagnostics.iter().map(d => d.code).collect().join(", "),
    )
  }
  f.shapes()[0].traits.to_owned()
}

///|
test "trait forms" {
  let ts = traits_of(
    (
      #|@a
      #|@b()
      #|@c("x")
      #|@d(k: 1, "j": [true])
      #|@smithy.api#e(Foo)
      #|string S
      #|
    ),
  )
  @expect.expect_all(e => {
    e.expect(ts.length()).to_equal(5)
    e.expect(ts[0].body).to_equal(None)
    e.expect(ts[1].body is Some(Structure(kv)) && kv.length() == 0).to_be_true()
    e.expect(ts[2].body is Some(Node(String("x", _)))).to_be_true()
    e.expect(ts[3].body is Some(Structure(kv)) && kv.length() == 2).to_be_true()
    e.expect(ts[4].id.value.to_string()).to_equal("smithy.api#e")
    e.expect(ts[4].body is Some(Node(ShapeId(_, _)))).to_be_true()
  })
}

///|
test "an unclosed trait body is reported with the trait as context" {
  let r = tmodel(
    (
      #|@a(k: 1
      #|string S
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  inspect(r.errors()[0].labels[0].text, content="the trait `@a` started here")
}

///|
test "apply statements" {
  let r = tmodel(
    (
      #|apply Foo @since("1")
      #|apply Bar$baz {
      #|  @a
      #|  @b
      #|}
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(r.has_errors(), content="false")
  guard f.statements[0] is Apply(a) && f.statements[1] is Apply(b) else {
    fail("not applies")
  }
  @expect.expect_all(e => {
    e.expect(a.target.value.name).to_equal("Foo")
    e.expect(a.traits.length()).to_equal(1)
    e.expect(a.block).to_be_false()
    e.expect(b.target.value.member).to_equal(Some("baz"))
    e.expect(b.traits.length()).to_equal(2)
    e.expect(b.block).to_be_true()
  })
}

///|
test "traits with nothing after them are an error, not a crash" {
  let r = tmodel(
    (
      #|@a
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  inspect(
    r.errors()[0].message,
    content="I was expecting a shape after the traits but found the end of the file",
  )
}

///|
test "an apply block with unindented traits is not unfinished (finding 3 regression)" {
  let r = tmodel(
    (
      #|apply Foo {
      #|@a
      #|}
      #|
    ),
  )
  inspect(r.has_errors(), content="false")
}

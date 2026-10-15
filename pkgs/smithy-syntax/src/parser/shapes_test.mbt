///|
fn model(body : String) -> @parser.ParseResult {
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
fn shapes(body : String) -> Array[@ast.ShapeStatement] raise {
  let r = model(body)
  guard r.ast is Some(f) else {
    fail(
      "no ast: " + r.diagnostics.iter().map(d => d.code).collect().join(", "),
    )
  }
  f.shapes()
}

///|
fn scodes(body : String) -> Array[String] {
  model(body).diagnostics.iter().map(d => d.code).collect()
}

///|
test "simple shapes" {
  let ss = shapes(
    (
      #|string Foo
      #|blob Bar with [Mix]
      #|
    ),
  )
  @expect.expect_all(e => {
    e.expect(ss.length()).to_equal(2)
    e.expect(ss[0].shape.name().value).to_equal("Foo")
    e.expect(ss[0].shape.kind()).to_equal(Simple(String))
    e.expect(ss[1].shape is Aggregate(..)).to_be_false()
  })
  guard ss[1].shape is Simple(mixins=Some(m), ..) else { fail("no mixins") }
  inspect(m.ids[0].value, content="Mix")
}

///|
test "structures with explicit and elided members and defaults" {
  let ss = shapes(
    (
      #|structure Foo for Res with [A, B] {
      #|    @required
      #|    bar: String = "x"
      #|    $baz
      #|    $qux = 1
      #|}
      #|
    ),
  )
  guard ss[0].shape
    is Aggregate(
      kind=Structure,
      for_resource=Some(res),
      mixins=Some(m),
      members~,
      ..
    ) else {
    fail("not a structure")
  }
  @expect.expect_all(e => {
    e.expect(res.value.name).to_equal("Res")
    e.expect(m.ids.length()).to_equal(2)
    e.expect(members.length()).to_equal(3)
    e.expect(members[0].name.value).to_equal("bar")
    e.expect(members[0].traits.length()).to_equal(1)
    e.expect(members[0].target is Explicit(_)).to_be_true()
    e.expect(members[0].default.bind(d => d.as_string())).to_equal(Some("x"))
    e.expect(members[1].target is Elided).to_be_true()
    e.expect(members[2].default is Some(Number(_, _))).to_be_true()
  })
}

///|
test "list, map, union and set" {
  let ss = shapes(
    (
      #|list L { member: String }
      #|map M { key: String, value: Integer }
      #|union U { a: String }
      #|set S { member: String }
      #|
    ),
  )
  @expect.expect(ss.map(s => s.shape.kind())).to_equal([
    Aggregate(List),
    Aggregate(Map),
    Aggregate(Union),
    Aggregate(Set),
  ])
  guard ss[1].shape is Aggregate(members~, ..) else { fail("not a map") }
  inspect(members.length(), content="2")
}

///|
test "enum and intEnum members with values and traits" {
  let ss = shapes(
    (
      #|enum Color {
      #|  /// red
      #|  @deprecated
      #|  RED = "red"
      #|  BLUE
      #|}
      #|intEnum N { ONE = 1 }
      #|
    ),
  )
  guard ss[0].shape is Enum(kind=Enum, members~, ..) else {
    fail("not an enum")
  }
  @expect.expect_all(e => {
    e.expect(members.length()).to_equal(2)
    e.expect(members[0].docs[0].text).to_equal(" red")
    e.expect(members[0].traits.length()).to_equal(1)
    e.expect(members[0].value.bind(v => v.as_string())).to_equal(Some("red"))
    e.expect(members[1].value).to_equal(None)
  })
  guard ss[1].shape is Enum(kind=IntEnum, ..) else { fail("not an intEnum") }
}

///|
test "service and resource bodies are node objects" {
  let ss = shapes(
    (
      #|service S {
      #|  version: "1"
      #|  operations: [Op]
      #|}
      #|resource R { identifiers: { id: String } }
      #|
    ),
  )
  guard ss[0].shape is Entity(kind=Service, body~, ..) else {
    fail("not a service")
  }
  debug_inspect(
    body.get("version").bind(v => v.as_string()),
    content="Some(\"1\")",
  )
  guard ss[1].shape is Entity(kind=Resource, ..) else { fail("not a resource") }
}

///|
test "operations with references, inline shapes and errors" {
  let ss = shapes(
    (
      #|operation Op {
      #|    input := @sensitive for Res with [M] {
      #|        id: String
      #|    }
      #|    output: Out
      #|    errors: [E1, E2]
      #|}
      #|
    ),
  )
  guard ss[0].shape is Operation(properties~, ..) else {
    fail("not an operation")
  }
  inspect(properties.length(), content="3")
  guard properties[0] is Input(Inline(inline), _) else {
    fail("input not inline")
  }
  @expect.expect_all(e => {
    e.expect(inline.traits.length()).to_equal(1)
    e.expect(inline.for_resource.map(r => r.value.name)).to_equal(Some("Res"))
    e.expect(inline.mixins.map(m => m.ids.length())).to_equal(Some(1))
    e.expect(inline.members.length()).to_equal(1)
  })
  guard properties[1] is Output(Reference(out), _) else {
    fail("output not a reference")
  }
  inspect(out.value.name, content="Out")
  guard properties[2] is Errors(errs, _) else { fail("no errors") }
  inspect(errs.length(), content="2")
}

///|
test "an unknown operation property is SM-PARSE-011" {
  @expect.expect(
    scodes(
      (
        #|operation Op { inputs: Foo }
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-011"])
}

///|
test "a shape name must be an identifier (the reference's parse errors)" {
  let r = model(
    (
      #|string com.foo#Bam
      #|
    ),
  )
  @expect.expect(
    scodes(
      (
        #|string com.foo#Bam
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-005"])
  inspect(
    r.errors()[0].message,
    content="a shape name is a plain identifier, but `com.foo#Bam` has a namespace",
  )
  @expect.expect(
    scodes(
      (
        #|string Foo$bar
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-005"])
}

///|
test "spaces inside a shape id are not a shape id" {
  @expect.expect(
    scodes(
      (
        #|structure S { a: smithy.api # String }
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
}

///|
test "a shape keyword needs a name on the same line" {
  @expect.expect(
    scodes(
      (
        #|string
        #|Foo
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  let r = model(
    (
      #|string
      #|
    ),
  )
  inspect(
    r.errors()[0].message,
    content="I was expecting a shape name after `string` but found the end of the file",
  )
}

///|
test "members need a line break between them" {
  @expect.expect(
    scodes(
      (
        #|structure S { a: String b: String }
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-003"])
  @expect.expect(
    scodes(
      (
        #|structure S { a: String, b: String }
        #|
      ),
    ),
  ).to_equal([])
}

///|
test "an unclosed structure is reported once, with the structure as context" {
  let r = model(
    (
      #|structure S {
      #|  a: String
      #|string Foo
      #|
    ),
  )
  let errs = r.errors()
  inspect(errs.length(), content="1")
  inspect(errs[0].labels[0].text, content="the structure `S` started here")
}

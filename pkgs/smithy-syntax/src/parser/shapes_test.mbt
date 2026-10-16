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
/// `Mixins = [SP] "with" [WS] "[" ...`: `with` on the next line is not a
/// `Mixins` clause, so the shape has none and `with` starts a new
/// (invalid) statement. Pins the reference's
/// `invalid/mixins/with-on-next-line-structure.smithy`.
test "with on the next line is not a mixins clause" {
  @expect.expect(
    scodes(
      (
        #|structure Foo
        #|    with [Mix] {
        #|}
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  let ss = shapes(
    (
      #|blob Bar with [Mix]
      #|
    ),
  )
  guard ss[0].shape is Simple(mixins=Some(m), ..) else { fail("no mixins") }
  inspect(m.ids[0].value, content="Mix")
}

///|
/// An inline shape's `with` may follow a trait that ends its own line: the
/// `BR` there belongs to the trait, not to `Mixins`. Pins the reference's
/// `valid/inline-io.smithy`.
test "an inline shape's with may follow a trait on its own line" {
  let ss = shapes(
    (
      #|operation Op {
      #|    input :=
      #|        @sensitive
      #|        with [Mix] {
      #|            id: String
      #|        }
      #|}
      #|
    ),
  )
  guard ss[0].shape is Operation(properties~, ..) &&
    properties[0] is Input(Inline(inline), _) else {
    fail("no inline input")
  }
  guard inline.mixins is Some(m) else { fail("no mixins") }
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
/// Pins the reference's `invalid/operations/input-defined-twice.smithy`.
test "an operation property may be set at most once" {
  @expect.expect(
    scodes(
      (
        #|operation Op {
        #|    input: Foo
        #|    input: Foo
        #|}
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-012"])
}

///|
/// `ApplyStatementBlock = "apply" SP ShapeId WS "{" ...`: a mandatory `WS`
/// between the target and `{`, not zero. Pins the reference's
/// `invalid/apply/apply-missing-space.smithy`.
test "apply needs whitespace before its trait block" {
  @expect.expect(
    scodes(
      (
        #|apply Foo{ @sensitive }
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-001"])
  @expect.expect(
    scodes(
      (
        #|apply Foo { @sensitive }
        #|
      ),
    ),
  ).to_equal([])
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
/// Pins the reference's `invalid/parse-errors/invalid-newline-after-shape-type.smithy`:
/// the error sits at the line break itself (right after the keyword),
/// not at the shape name on the line after it.
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
      #|structure
      #|Foo {}
      #|
    ),
  )
  let source = @span.SourceText::new(r.cst.to_source())
  let p = source.position(r.errors()[0].span.start)
  // Line 1 is `$version`, line 2 `namespace`, line 3 blank, line 4
  // `structure`: the break right after it is still on line 4, not on
  // line 5 where `Foo {}` is.
  inspect(p.line.0, content="4")
  let r2 = model(
    (
      #|string
      #|
    ),
  )
  inspect(
    r2.errors()[0].message,
    content="I was expecting a shape name after `string` but found the end of the file",
  )
}

///|
/// Pins the reference's `invalid/parse-errors/expected-shape-name-but-eof.smithy`:
/// a missing shape name at the true end of a file that ends with a line
/// break is reported right after the keyword, not on the synthetic
/// empty line after the final break.
test "a shape name missing at EOF is reported right after the keyword" {
  let r = model(
    (
      #|string
      #|
    ),
  )
  let errs = r.errors()
  guard errs.length() > 0 else { fail("no error") }
  inspect(errs[0].span.start == errs[0].span.end(), content="true")
  // `string` is the last real token; the span must sit right after it,
  // not on the file's trailing blank line.
  inspect(errs[0].span.start.0 < r.cst.to_source().length(), content="true")
}

///|
/// `ShapeMembers = "{" [WS] *(ShapeMember [WS]) "}"` and `WS = 1*(SP / NL /
/// Comment / Comma)`: unlike a statement's `BR`, members need only
/// whitespace between them, not a line break, a comment or a comma
/// specifically. A plain space is enough, as the reference's
/// `valid/maps-2.0.smithy` (`map H{key:String value:String}`) and
/// `valid/enums/short-form-enum.smithy` (`enum A { FOO BAR BAZ }`) pin.
test "members need only whitespace between them, not a line break" {
  @expect.expect(
    scodes(
      (
        #|structure S { a: String b: String }
        #|
      ),
    ),
  ).to_equal([])
  @expect.expect(
    scodes(
      (
        #|structure S { a: String, b: String }
        #|
      ),
    ),
  ).to_equal([])
  @expect.expect(
    scodes(
      (
        #|structure S {a: String"b"}
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-003"])
}

///|
/// `ValueAssignment = [SP] "=" [SP] NodeValue [SP] [Comma] BR`: unlike a
/// bare member, a member with an explicit value ends with a true `BR`, so
/// two of them cannot share a line even separated by a space. Pins the
/// reference's `invalid/defaults/missing-newline-after-assignment.smithy`
/// and `invalid/enums/missing-newline-after-assignment.smithy`.
test "a member's value assignment still needs a line break before the next member" {
  @expect.expect(
    scodes(
      (
        #|structure S { bar: String = "Hi" baz: String = "Hi" }
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-003"])
  @expect.expect(
    scodes(
      (
        #|structure S {
        #|    bar: String = "Hi"
        #|    baz: String = "Hi"
        #|}
        #|
      ),
    ),
  ).to_equal([])
  @expect.expect(
    scodes(
      (
        #|intEnum Foo { BAR = 1 BAZ = 2 }
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-003"])
}

///|
/// Pins the reference's `invalid/enums/enum-with-duplicates.smithy`,
/// `intEnum-with-duplicates.smithy`, and the structure-member case the
/// same check covers.
test "a repeated member or enum member name is SM-PARSE-014" {
  @expect.expect(
    scodes(
      (
        #|structure Foo {
        #|    bar: String
        #|    bar: String
        #|}
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-014"])
  @expect.expect(
    scodes(
      (
        #|enum Foo {
        #|    BAR = "bar"
        #|    BAR = "bar"
        #|}
        #|
      ),
    ),
  ).to_equal(["SM-PARSE-014"])
  let r = model(
    (
      #|enum Foo {
      #|    BAR = "bar"
      #|    BAR = "bar"
      #|}
      #|
    ),
  )
  inspect(r.errors()[0].message, content="Found conflicting member name, `BAR`")
}

///|
test "a repeated member name keeps the shape and both members" {
  let r = model(
    (
      #|structure Foo {
      #|    bar: String
      #|    bar: Integer
      #|}
      #|
    ),
  )
  @expect.expect(r.diagnostics.iter().map(d => d.code).collect()).to_equal([
    "SM-PARSE-014",
  ])
  guard r.ast is Some(f) else { fail("no ast") }
  let shapes = f.shapes()
  inspect(shapes.length(), content="1")
  guard shapes[0].shape is Aggregate(members~, ..) else { fail("no members") }
  inspect(members.length(), content="2")
}

///|
test "a member named like a statement keyword at column 1 is a member" {
  let r = model(
    (
      #|structure S {
      #|namespace: String
      #|resource: String
      #|}
      #|
    ),
  )
  @expect.expect(r.diagnostics.iter().map(d => d.code).collect()).to_equal([])
  guard r.ast is Some(f) else { fail("no ast") }
  let shapes = f.shapes()
  inspect(shapes.length(), content="1")
  guard shapes[0].shape is Aggregate(members~, ..) else { fail("no members") }
  inspect(members.length(), content="2")
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

///|
test "a bad member recovers to the closing brace and the shape still parses (R2 regression)" {
  let r = model(
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
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(f.shapes().map(s => s.shape.name().value)).to_equal(["Bad", "Foo"])
    e.expect(r.cst.skipped().length()).to_equal(0)
  })
}

///|
test "an unclosed structure skips to the next shape, which still parses (R2 regression)" {
  let r = model(
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
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(r.cst.skipped().length()).to_equal(1)
    e
    .expect(f.shapes().iter().any(s => s.shape.name().value == "Bar"))
    .to_be_true()
  })
}

///|
test "an indented $ in an enum member fails without hanging (finding 1 regression)" {
  let r = model(
    (
      #|enum E {
      #|  $X
      #|}
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
}

///|
test "member recovery restores contexts and depth across a failed member (finding 2 regression)" {
  let r = model(
    (
      #|structure S {
      #|  @a(1 2)
      #|  b: String
      #|  c String
      #|}
      #|string com.foo#Bam
      #|
    ),
  )
  let errs = r.errors()
  let c_errs = errs
    .iter()
    .filter(e => e.message.contains("member name `c`"))
    .collect()
  guard c_errs.length() > 0 else {
    fail("no error for member `c`: " + errs.map(e => e.message).join(" | "))
  }
  let name_errs = errs
    .iter()
    .filter(e => e.message.contains("com.foo#Bam"))
    .collect()
  guard name_errs.length() > 0 else {
    fail("no error for `com.foo#Bam`: " + errs.map(e => e.message).join(" | "))
  }
  @expect.expect_all(e => {
    e.expect(c_errs[0].labels.length() > 0).to_be_true()
    e
    .expect(c_errs[0].labels[0].text)
    .to_equal("the structure `S` started here")
    e.expect(name_errs[0].labels.length()).to_equal(0)
  })
}

///|
test "an unindented structure member and trait are not an unfinished block (finding 3 regression)" {
  let r = model(
    (
      #|structure S {
      #|@required
      #|a: String
      #|}
      #|
    ),
  )
  inspect(r.has_errors(), content="false")
}

///|
test "operation properties accept a comma separator (finding 4 regression)" {
  let r = model(
    (
      #|operation O { input: A, output: B }
      #|
    ),
  )
  inspect(r.errors().length(), content="0")
  guard r.ast is Some(f) && f.shapes()[0].shape is Operation(properties~, ..) else {
    fail("not an operation")
  }
  inspect(properties.length(), content="2")
}

///|
test "recovery keeps the next member's first token when nothing was consumed (finding 2 follow-up)" {
  let r = model(
    (
      #|structure S {
      #|  a:
      #|  @required
      #|  b: String
      #|}
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  guard r.ast is Some(f) && f.shapes()[0].shape is Aggregate(members~, ..) else {
    fail("not a structure")
  }
  @expect.expect_all(e => {
    e.expect(members.length()).to_equal(1)
    e.expect(members[0].name.value).to_equal("b")
    e.expect(members[0].traits.length()).to_equal(1)
    e.expect(members[0].traits[0].id.value.name).to_equal("required")
  })
}

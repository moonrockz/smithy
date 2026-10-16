///|
fn table_fields(category : String, kind : String) -> Array[String] raise {
  for row in @traversal.kind_table() {
    if row.0 == category && row.1 == kind {
      return row.2
    }
  }
  fail("no row for \{category}/\{kind}")
}

///|
test "every kind lists its fields from the table" {
  for n in every_node(root_of(every_form)) {
    assert_eq(n.fields(), table_fields(n.category(), n.kind()), msg=tag(n))
  }
}

///|
test "the member fields of a structure" {
  let text =
    #|$version: "2"
    #|namespace a
    #|
    #|structure Foo {
    #|    bar: String = "x"
    #|    $baz
    #|}
    #|
  let shape = root_of(text).field("shapes")[0]
  let members = shape.field("members")
  assert_eq(members.length(), 2)
  let bar = members[0]
  guard bar.field("name") is [Name(n)] else { fail("no name") }
  assert_eq(n.value, "bar")
  guard bar.field("target") is [ShapeIdRef(t)] else { fail("no target") }
  assert_eq(t.value.name, "String")
  guard bar.field("default") is [d] else { fail("no default") }
  assert_eq(tag(d).has_prefix("value/string"), true)
  assert_eq(members[1].field("target").length(), 0)
  assert_eq(shape.field("no-such-field").length(), 0)
}

///|
test "docs come before traits in children" {
  let shape = root_of(documented).field("shapes")[0]
  let kinds = shape.children().map(c => "\{c.category()}/\{c.kind()}")
  assert_eq(kinds[0:3].to_owned(), ["doc/doc", "trait/trait", "name/name"])
}

///|
test "a file's children interleave comments with statements in source order" {
  let text =
    #|$version: "2"
    #|// one
    #|namespace a
    #|// two
    #|string A
    #|// three
    #|
  let kinds = root_of(text).children().map(c => "\{c.category()}/\{c.kind()}")
  assert_eq(kinds, [
    "control/control", "comment/line", "namespace/namespace", "comment/line", "shape/string",
    "comment/line",
  ])
}

///|
test "children_with_fields gives each child's field and index" {
  let text =
    #|$version: "2"
    #|namespace a
    #|
    #|structure Foo {
    #|    a: String
    #|    b: String
    #|}
    #|
  let shape = root_of(text).field("shapes")[0]
  let steps = shape
    .children_with_fields()
    .map(x => "\{x.0.field}[\{x.0.index}]")
  assert_eq(steps, ["name[0]", "members[0]", "members[1]"])
  for x in shape.children_with_fields() {
    assert_eq(shape.field_of(x.1), Some(x.0.field))
  }
  assert_eq(shape.field_of(root_of(text)), None)
}

///|
test "an operation's properties hold the inline shape and the errors" {
  let text =
    #|$version: "2"
    #|namespace a
    #|
    #|operation Op {
    #|    input := {
    #|        a: String
    #|    }
    #|    output: Out
    #|    errors: [E1, E2]
    #|}
    #|
  let props = root_of(text).field("shapes")[0].field("properties")
  assert_eq(props.map(p => p.kind()), ["input", "output", "errors"])
  assert_eq(props[0].field("target").map(t => t.kind()), ["inline"])
  assert_eq(props[1].field("target").map(t => t.kind()), ["shape_id"])
  assert_eq(props[2].field("targets").length(), 2)
}

///|
test "a trait body fills value or entries" {
  let text =
    #|$version: "2"
    #|namespace a
    #|
    #|@a
    #|@b("x")
    #|@c(k: 1)
    #|@d()
    #|string S
    #|
  let traits = root_of(text).field("shapes")[0].field("traits")
  let shape = traits.map(t => {
    "\{t.field("value").length()}/\{t.field("entries").length()}"
  })
  assert_eq(shape, ["0/0", "1/0", "0/1", "0/0"])
}

///|
test "kind_table has one row per (category, kind)" {
  let rows = @traversal.kind_table()
  let keys : Set[String] = Set([])
  for r in rows {
    keys.add("\{r.0}/\{r.1}")
  }
  assert_eq(keys.length(), rows.length())
  assert_eq(rows.length(), 51)
}

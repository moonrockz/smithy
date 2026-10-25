///|
/// Run the action and give the message of the `InvalidTemplate` error that it raises.
fn invalid_template(
  action : () -> Unit raise @codegen.CodegenError,
) -> String raise {
  try action() catch {
    @codegen.InvalidTemplate(text) => text
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an InvalidTemplate error")
  }
}

///|
/// Run the action and give the message of the `StateError` error that it raises.
fn state_error(action : () -> Unit raise @codegen.CodegenError) -> String raise {
  try action() catch {
    @codegen.StateError(text) => text
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected a StateError error")
  }
}

///|
test "literal, string and escaped dollar" {
  let w = @codegen.CodeWriter::new()
  w.write("let $L = $S; // $$5", args=[
    @codegen.Text("x"),
    @codegen.Text("a\"b"),
  ])
  assert_eq(w.to_string(), "let x = \"a\\\"b\"; // $5\n")
}

///|
test "positional and named arguments" {
  let w = @codegen.CodeWriter::new()
  w.write("$1L-$2L-$1L", args=[@codegen.Text("a"), @codegen.Text("b")])
  w.put_context("n", @codegen.Text("z"))
  w.write("$n:L ${n:L}")
  assert_eq(w.to_string(), "a-b-a\nz z\n")
}

///|
test "built-in formatters format scalar values" {
  let w = @codegen.CodeWriter::new()
  let ns = @codegen.Namespace::parse("example.orders", separator=".").unwrap()
  let sym = @codegen.Symbol::new(
    @codegen.SymbolName::parse("Order").unwrap(),
    namespace=ns,
  )
  w.write("$L|$L|$L|$L|$L", args=[
    @codegen.Int(7),
    @codegen.Bool(true),
    @codegen.Null,
    @codegen.Text("t"),
    @codegen.Sym(sym),
  ])
  assert_eq(w.to_string(), "7|true||t|example.orders.Order\n")
  let bad = invalid_template(() => w.write("$L", args=[@codegen.List([])]))
  assert_true(bad.contains("cannot format"))
  let _ = invalid_template(() => w.write("$S", args=[@codegen.Int(1)]))
  let _ = invalid_template(() => w.write("$L", args=[@codegen.Record(Map([]))]))
  let _ = invalid_template(() => w.write("$L", args=[@codegen.Call(_ => ())]))
  let _ = invalid_template(() => {
    w.write("$L", args=[@codegen.Ref(@codegen.SymbolReference::new(sym))])
  })
}

///|
test "indentation and blocks" {
  let w = @codegen.CodeWriter::new()
  w.open_block("struct A {", "}", w => w.write("x"))
  assert_eq(w.to_string(), "struct A {\n    x\n}\n")
}

///|
test "nested blocks, custom indent text and newline prefix" {
  let w = @codegen.CodeWriter::new(indent_text="\t")
  w.set_newline_prefix("// ")
  w.open_block("a {", "}", w => w.open_block("b {", "}", w => w.write("c\n\nd")))
  assert_eq(
    w.to_string(),
    "// a {\n// \tb {\n// \t\tc\n\n// \t\td\n// \t}\n// }\n",
  )
}

///|
test "write_inline continues the line and indents only at line start" {
  let w = @codegen.CodeWriter::new()
  w.indent()
  w.write_inline("a")
  w.write_inline("b")
  w.write("c")
  w.write("d")
  assert_eq(w.to_string(), "    abc\n    d\n")
}

///|
test "push and pop restore indentation and context" {
  let w = @codegen.CodeWriter::new()
  w.put_context("k", @codegen.Text("outer"))
  w.indent()
  w.push_state()
  w.indent(levels=2)
  w.put_context("k", @codegen.Text("inner"))
  w.put_formatter('Z', (_, v) => {
    match v {
      Text(t) => "Z" + t
      _ => "?"
    }
  })
  w.write("$k:L $Z", args=[@codegen.Text("!")])
  w.pop_state()
  w.write("$k:L")
  assert_eq(w.to_string(), "            inner Z!\n    outer\n")
  assert_true(w.get_context("k") is Some(Text("outer")))
  assert_true(w.get_context("missing") is None)
  let _ = invalid_template(() => w.write("$Z", args=[@codegen.Text("!")]))
}

///|
test "bad templates raise InvalidTemplate with the offset" {
  for t in ["end $", "$Q", "$1L $L", "$name", "${n:L"] {
    let w = @codegen.CodeWriter::new()
    let message = invalid_template(() => w.write(t, args=[@codegen.Text("a")]))
    assert_true(message.contains("offset"))
    assert_true(message.has_prefix("I found "))
    assert_eq(w.to_string(), "")
  }
  let w = @codegen.CodeWriter::new()
  let _ = invalid_template(() => w.write("$L"))
  let unused = invalid_template(() => w.write("x", args=[@codegen.Text("a")]))
  assert_true(unused.contains("offset 1 in template `x`"))
  let _ = invalid_template(() => {
    w.write("$2L", args=[@codegen.Text("a"), @codegen.Text("b")])
  })
  let _ = invalid_template(() => w.write("$nope:L"))
  let _ = invalid_template(() => w.write("${n"))
  let _ = invalid_template(() => w.write("$ x"))
  let _ = invalid_template(() => w.write("$0L", args=[@codegen.Text("a")]))
  let _ = invalid_template(() => w.write("$1", args=[@codegen.Text("a")]))
  let _ = invalid_template(() => w.write("${1L", args=[@codegen.Text("a")]))
  let _ = invalid_template(() => w.write("${n:", args=[@codegen.Text("a")]))
  let _ = invalid_template(() => w.write("${n:Lx}", args=[@codegen.Text("a")]))
  assert_eq(w.to_string(), "")
}

///|
test "bad templates report the offset of the bad expression" {
  let w = @codegen.CodeWriter::new()
  assert_eq(
    invalid_template(() => w.write("ab $Q", args=[@codegen.Text("a")])),
    "I found a formatter `Q` that does not exist at offset 3 in template `ab $Q`.",
  )
  assert_true(
    invalid_template(() => w.write("end $")).contains(
      "offset 4 in template `end $`",
    ),
  )
  // offsets count characters, not UTF-16 units
  assert_true(
    invalid_template(() => w.write("\u{1f600}$Q", args=[@codegen.Text("a")])).contains(
      "offset 1 in template",
    ),
  )
  // offsets count the characters of the template as written, with `\r\n`
  assert_true(
    invalid_template(() => w.write("a\r\n$Q", args=[@codegen.Text("a")])).contains(
      "offset 3 in template",
    ),
  )
}

///|
test "dedent below zero and pop without push raise StateError" {
  let w = @codegen.CodeWriter::new()
  let _ = state_error(() => w.dedent())
  w.indent()
  let _ = state_error(() => w.dedent(levels=2))
  let _ = state_error(() => w.pop_state())
  w.push_state()
  w.pop_state()
  let _ = state_error(() => w.pop_state())
}

///|
test "string literals escape hard content" {
  assert_eq(
    @codegen.json_string_literal("q\" b\\ t\t n\n r\r \u{1} é"),
    "\"q\\\" b\\\\ t\\t n\\n r\\r \\u0001 é\"",
  )
  let w = @codegen.CodeWriter::new()
  w.write("a\r\nb")
  assert_eq(w.to_string(), "a\nb\n")
  let w2 = @codegen.CodeWriter::new()
  w2.write("$S", args=[@codegen.Text("tab\there \u{1f600}")])
  assert_eq(w2.to_string(), "\"tab\\there \u{1f600}\"\n")
}

///|
test "to_string trims trailing spaces and ends with one newline" {
  let w = @codegen.CodeWriter::new()
  w.write("a  ")
  w.blank_line()
  w.blank_line()
  assert_eq(w.to_string(), "a\n")
  assert_eq(@codegen.CodeWriter::new().to_string(), "")
}

///|
test "the namespace of the writer" {
  let ns = @codegen.Namespace::parse("a.b", separator=".").unwrap()
  assert_eq(@codegen.CodeWriter::new(namespace=ns).namespace(), ns)
  assert_true(@codegen.CodeWriter::new().namespace().is_root())
}

///|
test "a custom string literal function replaces the default" {
  let w = @codegen.CodeWriter::new(string_literal=text => "'\{text}'")
  w.write("$S", args=[@codegen.Text("a")])
  assert_eq(w.to_string(), "'a'\n")
}

///|
test "a custom formatter error passes through unchanged" {
  let w = @codegen.CodeWriter::new()
  w.put_formatter('Z', (_, _) => raise @codegen.InvalidTemplate("I found x."))
  assert_eq(
    invalid_template(() => w.write("a $Z", args=[@codegen.Null])),
    "I found x.",
  )
  // an error of another kind passes through, too
  w.put_formatter('Y', (_, _) => raise @codegen.StateError("I found y."))
  assert_eq(
    state_error(() => w.write("$Y", args=[@codegen.Null])),
    "I found y.",
  )
  assert_eq(w.to_string(), "")
}

///|
test "a formatter that writes with a child writer keeps the child error" {
  let w = @codegen.CodeWriter::new()
  w.put_formatter('C', (_, _) => {
    let child = @codegen.CodeWriter::new()
    child.write("ab $Q", args=[@codegen.Null])
    child.to_string()
  })
  assert_eq(
    invalid_template(() => w.write("$C", args=[@codegen.Null])),
    "I found a formatter `Q` that does not exist at offset 3 in template `ab $Q`.",
  )
}

///|
test "a custom formatter can replace a built-in one" {
  let w = @codegen.CodeWriter::new()
  w.put_formatter('L', (_, _) => "custom")
  w.write("$L", args=[@codegen.List([])])
  assert_eq(w.to_string(), "custom\n")
}

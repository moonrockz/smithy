///|
/// Run the action and give the message of the `InvalidTemplate` error that it raises.
fn block_error(action : () -> Unit raise @codegen.CodegenError) -> String raise {
  try action() catch {
    @codegen.InvalidTemplate(text) => text
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an InvalidTemplate error")
  }
}

///|
test "conditions render on truthy and falsy values" {
  let w = @codegen.CodeWriter::new()
  w.put_context("on", @codegen.Bool(true))
  w.write("${?on}yes${/on}${^on}no${/on}")
  assert_eq(w.to_string(), "yes\n")
  let v = @codegen.CodeWriter::new()
  v.put_context("on", @codegen.Text(""))
  v.write("${?on}yes${/on}${^on}no${/on}")
  assert_eq(v.to_string(), "no\n")
  // a missing name is falsy
  let m = @codegen.CodeWriter::new()
  m.write("${?on}yes${/on}${^on}no${/on}")
  assert_eq(m.to_string(), "no\n")
}

///|
test "loops expose key, value, first and last" {
  let w = @codegen.CodeWriter::new()
  w.put_context("xs", @codegen.List([@codegen.Text("a"), @codegen.Text("b")]))
  w.write("${#xs}${value:L}${^key.last}, ${/key.last}${/xs}")
  assert_eq(w.to_string(), "a, b\n")
  let v = @codegen.CodeWriter::new()
  v.put_context("xs", @codegen.List([@codegen.Text("a"), @codegen.Text("b")]))
  v.write("${#xs as i, x}$i:L=$x:L ${/xs}")
  assert_eq(v.to_string(), "0=a 1=b\n")
}

///|
test "loops over a record use the insertion order and text keys" {
  let w = @codegen.CodeWriter::new()
  let fields : Map[String, @codegen.TemplateValue] = Map([])
  fields["z"] = @codegen.Int(1)
  fields["a"] = @codegen.Int(2)
  w.put_context("r", @codegen.Record(fields))
  w.write("${#r}${key:L}=${value:L};${/r}")
  assert_eq(w.to_string(), "z=1;a=2;\n")
}

///|
test "loops nest, and an empty loop renders nothing" {
  let w = @codegen.CodeWriter::new()
  let row = @codegen.List([@codegen.Int(1), @codegen.Int(2)])
  w.put_context("rows", @codegen.List([row, @codegen.List([]), row]))
  w.write(
    "${#rows as r, row}[${#row as c, cell}${cell:L}${^c.last},${/c.last}${/row}]${/rows}",
  )
  assert_eq(w.to_string(), "[1,2][][1,2]\n")
  // the outer variables stay visible when the inner loop renames its own
  let v = @codegen.CodeWriter::new()
  v.put_context("xs", @codegen.List([@codegen.Text("a"), @codegen.Text("b")]))
  v.put_context("key", @codegen.Text("outer"))
  v.write("${#xs}${#xs as k, y}${key:L}${y:L}${/xs}${/xs}")
  assert_eq(v.to_string(), "0a0b1a1b\n")
}

///|
test "arguments in a skipped block count as used" {
  let w = @codegen.CodeWriter::new()
  w.write("${?on}$L${/on}x", args=[@codegen.Text("a")])
  assert_eq(w.to_string(), "x\n")
}

///|
test "standalone block tags remove their line" {
  let w = @codegen.CodeWriter::new()
  w.put_context("on", @codegen.Bool(true))
  w.write("start\n${?on}\nmiddle\n${/on}\nend")
  assert_eq(w.to_string(), "start\nmiddle\nend\n")
  let v = @codegen.CodeWriter::new()
  v.put_context("on", @codegen.Bool(false))
  v.write("start\n  ${?on}  \nmiddle\n  ${/on}\r\nend")
  assert_eq(v.to_string(), "start\nend\n")
  // a tag with other text on its line is not standalone
  let m = @codegen.CodeWriter::new()
  m.put_context("on", @codegen.Bool(true))
  m.write("a ${?on}b${/on}\nc")
  assert_eq(m.to_string(), "a b\nc\n")
}

///|
test "whitespace control trims around tags" {
  let w = @codegen.CodeWriter::new()
  w.put_context("on", @codegen.Bool(true))
  w.write("a   ${-?on}b${/on-}   c")
  assert_eq(w.to_string(), "abc\n")
  let v = @codegen.CodeWriter::new()
  v.put_context("n", @codegen.Text("x"))
  v.write("a \n ${-n:L-} \n b")
  assert_eq(v.to_string(), "axb\n")
}

///|
test "nested writers with C and alignment" {
  let w = @codegen.CodeWriter::new()
  w.put_context(
    "body",
    @codegen.Call(c => {
      c.write("a")
      c.write("b")
    }),
  )
  w.write("fn f() {\n    ${body:C|}\n}")
  assert_eq(w.to_string(), "fn f() {\n    a\n    b\n}\n")
  // without `|` the later lines keep only the indentation of the writer
  let v = @codegen.CodeWriter::new()
  v.put_context(
    "body",
    @codegen.Call(c => {
      c.write("a")
      c.write("b")
    }),
  )
  v.write("{\n  ${body:C}\n}")
  assert_eq(v.to_string(), "{\n  a\nb\n}\n")
}

///|
test "a child shares the context copy and the formatters" {
  let w = @codegen.CodeWriter::new()
  w.put_context("n", @codegen.Text("x"))
  w.put_formatter('Z', (_, _) => "zed")
  let c = w.child()
  c.write("$n:L $Z", args=[@codegen.Null])
  assert_eq(c.to_string(), "x zed\n")
  // the context of the child is a copy
  c.put_context("m", @codegen.Null)
  assert_true(w.get_context("m") is None)
  // indentation starts at zero
  w.indent()
  assert_eq(w.child().to_string(), "")
}

///|
test "errors inside a C function pass through unchanged" {
  let w = @codegen.CodeWriter::new()
  w.put_context("body", @codegen.Call(c => c.write("$")))
  let message = block_error(() => w.write("x ${body:C}"))
  assert_eq(
    message, "I found a `$` at the end of the template at offset 0 in template `$`.",
  )
  let v = @codegen.CodeWriter::new()
  v.put_context("body", @codegen.Text("t"))
  let bad = block_error(() => v.write("ab ${body:C}"))
  assert_true(bad.contains("offset 3 in template `ab ${body:C}`"))
}

///|
test "bad blocks raise InvalidTemplate" {
  for t in ["${?x}a", "${?x}a${/y}", "${/x}", "${-x:C|}"] {
    let w = @codegen.CodeWriter::new()
    let message = block_error(() => w.write(t))
    assert_true(message.contains("offset"))
    assert_true(message.contains("in template `\{t}`"))
    assert_eq(w.to_string(), "")
  }
  let w = @codegen.CodeWriter::new()
  w.put_context("n", @codegen.Text("s"))
  let message = block_error(() => w.write("${#n}${/n}"))
  assert_true(message.contains("offset 0"))
  assert_eq(w.to_string(), "")
}

///|
test "bad blocks report the offset of the tag" {
  let w = @codegen.CodeWriter::new()
  assert_eq(
    block_error(() => w.write("ab ${?x}a")),
    "I found a `${?x}` that is not closed at offset 3 in template `ab ${?x}a`.",
  )
  assert_eq(
    block_error(() => w.write("${?x}${#y}${/x}")),
    "I found a closing tag `${/x}` where I expected `${/y}` at offset 10 in template `${?x}${#y}${/x}`.",
  )
  assert_eq(
    block_error(() => w.write("ab${/x}")),
    "I found a closing tag `${/x}` without an open tag at offset 2 in template `ab${/x}`.",
  )
  assert_eq(
    block_error(() => w.write("${-x:C|}")),
    "I found an alignment `|` in a tag that starts with `-` at offset 0 in template `${-x:C|}`.",
  )
  w.put_context("n", @codegen.Int(3))
  assert_eq(
    block_error(() => w.write("a${#n}${/n}")),
    "I found a loop over `n`, which is a number and not a list or a record at offset 1 in template `a${#n}${/n}`.",
  )
  for
    t in [
      "${#x as i}${/x}", "${#x as i,}${/x}", "${#x as 1, v}${/x}", "${?}", "${?x",
    ] {
    let message = block_error(() => w.write(t))
    assert_true(message.contains("offset 0"))
  }
}

///|
test "a loop over a missing name raises InvalidTemplate" {
  let w = @codegen.CodeWriter::new()
  assert_eq(
    block_error(() => w.write("${#x}${/x}")),
    "I found a loop over `x`, which has no value in the context at offset 0 in template `${#x}${/x}`.",
  )
  assert_eq(w.to_string(), "")
}

///|
test "a loop over Null raises InvalidTemplate" {
  let w = @codegen.CodeWriter::new()
  w.put_context("x", @codegen.Null)
  assert_eq(
    block_error(() => w.write("${#x}${/x}")),
    "I found a loop over `x`, which is a null value and not a list or a record at offset 0 in template `${#x}${/x}`.",
  )
  assert_eq(w.to_string(), "")
}

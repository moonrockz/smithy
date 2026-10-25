///|
/// Run the action and give the message of the `StateError` error that it raises.
fn section_state_error(
  action : () -> Unit raise @codegen.CodegenError,
) -> String raise {
  try action() catch {
    @codegen.StateError(text) => text
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected a StateError error")
  }
}

///|
test "an injected section is empty by default" {
  let w = @codegen.CodeWriter::new()
  w.write("before")
  w.inject_section(@codegen.Section::new("body"))
  w.write("after")
  assert_eq(w.to_string(), "before\nafter\n")
}

///|
test "appenders and prependers run in registration order" {
  let w = @codegen.CodeWriter::new()
  w.on_section(
    @codegen.Interceptor::prepender("body", (child, _) => child.write("a")),
  )
  w.on_section(
    @codegen.Interceptor::appender("body", (child, _) => child.write("c")),
  )
  w.on_section(
    @codegen.Interceptor::appender("body", (child, _) => child.write("d")),
  )
  w.push_section(@codegen.Section::new("body"))
  w.write("b")
  w.pop_section()
  assert_eq(w.to_string(), "a\nb\nc\nd\n")
}

///|
test "a replacer sees the previous text" {
  let w = @codegen.CodeWriter::new()
  let seen : Ref[String] = { val: "", }
  w.on_section(
    @codegen.Interceptor::new("body", (child, _, previous) => {
      seen.val = previous
      child.write("B")
    }),
  )
  w.push_section(@codegen.Section::new("body"))
  w.write("b")
  w.pop_section()
  assert_eq(seen.val, "b")
  assert_eq(w.to_string(), "B\n")
}

///|
test "an interceptor for another section does not run" {
  let w = @codegen.CodeWriter::new()
  w.on_section(
    @codegen.Interceptor::appender("other", (child, _) => child.write("x")),
  )
  w.push_section(@codegen.Section::new("body"))
  w.write("b")
  w.pop_section()
  assert_eq(w.to_string(), "b\n")
}

///|
test "section text keeps the enclosing indentation" {
  let w = @codegen.CodeWriter::new()
  w.on_section(
    @codegen.Interceptor::appender("body", (child, _) => child.write("extra")),
  )
  w.open_block("fn f() {", "}", w => {
    w.push_section(@codegen.Section::new("body"))
    w.write("one")
    w.indent()
    w.write("two")
    w.pop_section()
  })
  assert_eq(w.to_string(), "fn f() {\n    one\n        two\n    extra\n}\n")
}

///|
test "interceptors read section data" {
  let w = @codegen.CodeWriter::new()
  w.on_section(
    @codegen.Interceptor::appender("header", (child, section) => {
      match section.data.get("name") {
        Some(name) => child.write("// $L", args=[name])
        None => child.write("// no name")
      }
    }),
  )
  w.inject_section(
    @codegen.Section::new(
      "header",
      data=Map([("name", @codegen.Text("Order"))]),
    ),
  )
  assert_eq(w.to_string(), "// Order\n")
}

///|
test "pop_section without push raises StateError" {
  let w = @codegen.CodeWriter::new()
  let message = section_state_error(() => w.pop_section())
  assert_eq(message, "I found pop_section with no open section.")
}

///|
test "pop_state cannot pop the state of a section" {
  let w = @codegen.CodeWriter::new()
  w.push_section(@codegen.Section::new("body"))
  let message = section_state_error(() => w.pop_state())
  assert_true(message.contains("section `body`"))
  w.pop_section()
}

///|
test "pop_section raises StateError when a push_state is still open" {
  let w = @codegen.CodeWriter::new()
  w.push_section(@codegen.Section::new("body"))
  w.push_state()
  let message = section_state_error(() => w.pop_section())
  assert_true(message.contains("push_state"))
  w.pop_state()
  w.pop_section()
}

///|
test "interceptors of a writer apply in its child writers" {
  let w = @codegen.CodeWriter::new()
  w.on_section(
    @codegen.Interceptor::appender("body", (child, _) => child.write("tail")),
  )
  let child = w.child()
  child.push_section(@codegen.Section::new("body"))
  child.write("head")
  child.pop_section()
  assert_eq(child.to_string(), "head\ntail\n")
}

///|
test "an interceptor error propagates" {
  let w = @codegen.CodeWriter::new()
  w.on_section(
    @codegen.Interceptor::appender("body", (child, _) => child.write("$Z")),
  )
  w.push_section(@codegen.Section::new("body"))
  w.write("b")
  try w.pop_section() catch {
    @codegen.InvalidTemplate(_) => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an InvalidTemplate error")
  }
}

///|
test "a section keeps the line state of the outer text" {
  let w = @codegen.CodeWriter::new()
  w.indent()
  w.write_inline("a ")
  w.push_section(@codegen.Section::new("body"))
  w.write("x")
  w.write("y")
  w.pop_section()
  w.write("z")
  assert_eq(w.to_string(), "    a x\n    y\n    z\n")
}

///|
test "an empty section keeps the outer line open" {
  let w = @codegen.CodeWriter::new()
  w.indent()
  w.write_inline("a ")
  w.push_section(@codegen.Section::new("body"))
  w.blank_line()
  w.pop_section()
  w.write("b")
  assert_eq(w.to_string(), "    a b\n")
}

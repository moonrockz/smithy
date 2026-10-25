///|
fn imp_name(text : String) -> @codegen.SymbolName {
  @codegen.SymbolName::parse(text).unwrap()
}

///|
fn imp_ns(text : String) -> @codegen.Namespace {
  @codegen.Namespace::parse(text, separator=".").unwrap()
}

///|
fn imp_symbol(ns : String, name : String) -> @codegen.Symbol {
  @codegen.Symbol::new(imp_name(name), ns=imp_ns(ns))
}

///|
fn imp_entry(
  ns : String,
  name : String,
  local_name? : String,
) -> @codegen.ImportEntry {
  {
    ns: imp_ns(ns),
    name: imp_name(name),
    local_name: local_name.map(imp_name),
  }
}

///|
fn imp_dep(
  package_name : String,
  version : String,
) -> @codegen.SymbolDependency {
  {
    package_name: @codegen.PackageName::parse(package_name).unwrap(),
    version,
    kind: Runtime,
  }
}

///|
test "symbols in other namespaces are imported" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.write("use $T", args=[@codegen.Sym(imp_symbol("b", "Item"))])
  assert_eq(w.to_string(), "use Item\n")
  assert_eq(w.imports(), [imp_entry("b", "Item")])
}

///|
test "same and root namespace symbols are not imported" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  let root = @codegen.Symbol::new(imp_name("String"))
  w.write("$T $T", args=[
    @codegen.Sym(imp_symbol("a", "Local")),
    @codegen.Sym(root),
  ])
  assert_eq(w.to_string(), "Local String\n")
  assert_eq(w.imports(), [])
  try w.write("$T", args=[@codegen.Text("x")]) catch {
    @codegen.InvalidTemplate(text) =>
      inspect(text.contains("`T` cannot format"), content="true")
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected an InvalidTemplate error")
  }
}

///|
test "aliases are written and imported with the alias" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  let reference = @codegen.SymbolReference::new(
    imp_symbol("b", "Item"),
    local_name=Some(imp_name("BItem")),
  )
  w.write("$T $T", args=[@codegen.Ref(reference), @codegen.Ref(reference)])
  assert_eq(w.to_string(), "BItem BItem\n")
  assert_eq(w.imports(), [imp_entry("b", "Item", local_name="BItem")])
  let v = @codegen.CodeWriter::new(ns=imp_ns("a"))
  v.add_import(imp_symbol("c", "Other"), local_name=Some(imp_name("O")))
  v.add_import(imp_symbol("c", "Other"), local_name=Some(imp_name("O")))
  assert_eq(v.to_string(), "")
  assert_eq(v.imports(), [imp_entry("c", "Other", local_name="O")])
}

///|
test "a second symbol with a used name is written by full name" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.write("$T", args=[@codegen.Sym(imp_symbol("b", "Item"))])
  w.write("$T", args=[@codegen.Sym(imp_symbol("c", "Item"))])
  w.write("$T", args=[@codegen.Sym(imp_symbol("b", "Item"))])
  assert_eq(w.to_string(), "Item\nc.Item\nItem\n")
  assert_eq(w.imports(), [imp_entry("b", "Item")])
}

///|
test "dependencies of written symbols and their references are collected" {
  let d1 = imp_dep("pkg-a", "1.0.0")
  let d2 = imp_dep("pkg-b", "2.0.0")
  let d3 = imp_dep("pkg-c", "3.0.0")
  let inner = imp_symbol("c", "Inner").with_dependency(d2)
  let outer = imp_symbol("b", "Outer")
    .with_dependency(d1)
    .with_dependency(d2)
    .with_reference(@codegen.SymbolReference::new(inner))
    .with_reference(@codegen.SymbolReference::new(inner))
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.add_dependency(d3)
  w.write("$T", args=[@codegen.Sym(outer)])
  assert_eq(w.to_string(), "Outer\n")
  assert_eq(w.dependencies(), [d1, d2, d3])
  assert_eq(w.imports(), [imp_entry("b", "Outer"), imp_entry("c", "Inner")])
}

///|
test "child writers share imports" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.write("$C", args=[
    @codegen.Call(child => {
      child.write("$T", args=[@codegen.Sym(imp_symbol("b", "Item"))])
    }),
  ])
  assert_eq(w.to_string(), "Item\n")
  assert_eq(w.imports(), [imp_entry("b", "Item")])
}

///|
test "a cycle of references does not loop" {
  let first = imp_symbol("b", "First")
  let second = imp_symbol("c", "Second")
  first.references.push(@codegen.SymbolReference::new(second))
  second.references.push(@codegen.SymbolReference::new(first))
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.write("$T", args=[@codegen.Sym(first)])
  assert_eq(w.to_string(), "First\n")
  assert_eq(w.imports(), [imp_entry("b", "First"), imp_entry("c", "Second")])
}

///|
test "a failed template leaves the imports and dependencies unchanged" {
  let dep = imp_dep("pkg-a", "1.0.0")
  let item = @codegen.Sym(imp_symbol("b", "Item").with_dependency(dep))
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  // The first template fails when I parse it. The second one fails while I
  // render it, after the `$T` recorded the import.
  for template in ["$T $", "$T $missing:L"] {
    try w.write(template, args=[item]) catch {
      @codegen.InvalidTemplate(_) => ()
      e => fail("unexpected error: \{e.message()}")
    } noraise {
      _ => fail("expected an InvalidTemplate error")
    }
    assert_eq(w.imports(), [])
    assert_eq(w.dependencies(), [])
  }
  w.write("$T", args=[@codegen.Sym(imp_symbol("c", "Item"))])
  assert_eq(w.to_string(), "Item\n")
  assert_eq(w.imports(), [imp_entry("c", "Item")])
}

///|
test "a failed nested body leaves the parent tracker unchanged" {
  let dep = imp_dep("pkg-a", "1.0.0")
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.write("$T", args=[@codegen.Sym(imp_symbol("d", "Kept"))])
  try
    w.write("$C", args=[
      @codegen.Call(child => {
        child.write("$T", args=[
          @codegen.Sym(imp_symbol("b", "Item").with_dependency(dep)),
        ])
        raise @codegen.StateError("stop")
      }),
    ])
  catch {
    @codegen.StateError(_) => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected a StateError error")
  }
  assert_eq(w.to_string(), "Kept\n")
  assert_eq(w.imports(), [imp_entry("d", "Kept")])
  assert_eq(w.dependencies(), [])
}

///|
test "a name of the writer namespace blocks a foreign import of that name" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.write("$T $T", args=[
    @codegen.Sym(imp_symbol("a", "Item")),
    @codegen.Sym(imp_symbol("b", "Item")),
  ])
  assert_eq(w.to_string(), "Item b.Item\n")
  assert_eq(w.imports(), [])
}

///|
test "a reserved name blocks a foreign import of that name" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  w.reserve_name(imp_name("Item"))
  w.write("$T $T", args=[
    @codegen.Sym(imp_symbol("b", "Item")),
    @codegen.Sym(imp_symbol("c", "Other")),
  ])
  assert_eq(w.to_string(), "b.Item Other\n")
  assert_eq(w.imports(), [imp_entry("c", "Other")])
}

///|
test "a failed template also removes the local names it recorded" {
  let w = @codegen.CodeWriter::new(ns=imp_ns("a"))
  try
    w.write("$T $missing:L", args=[@codegen.Sym(imp_symbol("a", "Item"))])
  catch {
    @codegen.InvalidTemplate(_) => ()
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected InvalidTemplate")
  }
  w.write("$T", args=[@codegen.Sym(imp_symbol("b", "Item"))])
  assert_eq(w.to_string(), "Item\n")
  assert_eq(w.imports(), [imp_entry("b", "Item")])
}

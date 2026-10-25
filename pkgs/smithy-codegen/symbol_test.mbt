///|
test "output paths accept relative paths and reject escapes" {
  assert_true(@codegen.OutputPath::parse("example/orders/Order.txt") is Some(_))
  for
    bad in [
      "", "/abs.txt", "../up.txt", "a/../b", "./a", "a\\b", "C:/x", "a//b",
    ] {
    assert_true(@codegen.OutputPath::parse(bad) is None)
  }
}

///|
test "names and namespaces reject empty and spaced text" {
  assert_true(@codegen.SymbolName::parse("Order") is Some(_))
  for bad in ["", "a b", "a\tb"] {
    assert_true(@codegen.SymbolName::parse(bad) is None)
    assert_true(@codegen.PackageName::parse(bad) is None)
  }
  assert_true(@codegen.Namespace::parse("", separator=".") is None)
  assert_true(@codegen.Namespace::root().is_root())
  let ns = @codegen.Namespace::parse("a.b", separator=".").unwrap()
  assert_false(ns.is_root())
}

///|
test "full names use the namespace separator" {
  let ns = @codegen.Namespace::parse("example.orders", separator=".").unwrap()
  let s = @codegen.Symbol::new(
    @codegen.SymbolName::parse("Order").unwrap(),
    ns~,
  )
  assert_eq(s.full_name(), "example.orders.Order")
  assert_eq(
    @codegen.Symbol::new(@codegen.SymbolName::parse("String").unwrap()).full_name(),
    "String",
  )
}

///|
fn dependency(name : String) -> @codegen.SymbolDependency {
  {
    package_name: @codegen.PackageName::parse(name).unwrap(),
    version: "1",
    kind: Runtime,
  }
}

///|
fn named(text : String) -> @codegen.Symbol {
  @codegen.Symbol::new(@codegen.SymbolName::parse(text).unwrap())
}

///|
test "all dependencies include references, sorted and deduplicated" {
  let reference = @codegen.SymbolReference::new(
    named("Ref")
    .with_dependency(dependency("a"))
    .with_dependency(dependency("b")),
  )
  let s = named("Main")
    .with_dependency(dependency("b"))
    .with_reference(reference)
  let names = s.all_dependencies().map(d => d.package_name.to_string())
  assert_eq(names, ["a", "b"])
}

///|
test "symbols are values: with_* returns a copy" {
  let original = named("Main")
  let changed = original
    .with_dependency(dependency("a"))
    .with_property("k", Json::string("v"))
    .with_reference(@codegen.SymbolReference::new(named("Other")))
  assert_eq(original.dependencies.length(), 0)
  assert_eq(original.references.length(), 0)
  assert_true(original.property("k") is None)
  assert_eq(changed.dependencies.length(), 1)
  assert_eq(changed.references.length(), 1)
  assert_true(changed.property("k") is Some(_))
}

///|
test "codegen error messages name the construct" {
  let id = @smithy.ShapeId::parse("example#Missing").unwrap()
  assert_eq(
    @codegen.MissingService(id).message(),
    "I could not find service shape `example#Missing` in the model.",
  )
  assert_eq(
    @codegen.NotAService(id).message(),
    "I expected `example#Missing` to be a service shape.",
  )
  assert_eq(
    @codegen.MissingDefinition(id).message(),
    "I could not write shape `example#Missing`: its symbol has no definition file.",
  )
  assert_eq(
    @codegen.DuplicateIntegration("x").message(),
    "I found two integrations with the name `x`.",
  )
  assert_eq(
    @codegen.IntegrationCycle(["a", "b"]).message(),
    "I found a cycle in the order of integrations: a, b.",
  )
  assert_eq(@codegen.InvalidSettings("m").message(), "m")
  assert_eq(@codegen.InvalidTemplate("m").message(), "m")
  assert_eq(@codegen.WriterConflict("m").message(), "m")
  assert_eq(@codegen.StateError("m").message(), "m")
}

///|
test "with_name copies the symbol under a new name" {
  let ns = @codegen.Namespace::parse("a.b", separator=".").unwrap()
  let s = @codegen.Symbol::new(
    @codegen.SymbolName::parse("Order").unwrap(),
    ns~,
  ).with_property("k", Json::number(1.0))
  let renamed = s.with_name(@codegen.SymbolName::parse("Order_").unwrap())
  assert_eq(renamed.name.to_string(), "Order_")
  assert_eq(renamed.ns, ns)
  assert_eq(renamed.property("k"), Some(Json::number(1.0)))
  assert_eq(s.name.to_string(), "Order")
}

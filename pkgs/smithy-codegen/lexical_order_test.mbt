///|
fn lex_dep(package : String) -> @codegen.SymbolDependency {
  {
    package: @codegen.PackageName::parse(package).unwrap(),
    version: "1",
    kind: Runtime,
  }
}

///|
fn lex_ns(text : String) -> @codegen.Namespace {
  @codegen.Namespace::parse(text, separator=".").unwrap()
}

///|
test "names, paths and packages compare in lexical order" {
  assert_true(
    @codegen.SymbolName::parse("alpha").unwrap() <
    @codegen.SymbolName::parse("name").unwrap(),
  )
  assert_true(
    @codegen.OutputPath::parse("alpha.txt").unwrap() <
    @codegen.OutputPath::parse("b.txt").unwrap(),
  )
  assert_true(
    @codegen.PackageName::parse("abc").unwrap() <
    @codegen.PackageName::parse("bb").unwrap(),
  )
  assert_true(lex_ns("abc") < lex_ns("zz"))
  let dot = @codegen.Namespace::parse("a", separator=".").unwrap()
  let colons = @codegen.Namespace::parse("a", separator="::").unwrap()
  assert_true(dot < colons)
}

///|
test "dependency kinds keep their declaration order" {
  assert_true(
    (
      {
        package: @codegen.PackageName::parse("p").unwrap(),
        version: "1",
        kind: Runtime,
      } : @codegen.SymbolDependency) <
    {
      package: @codegen.PackageName::parse("p").unwrap(),
      version: "1",
      kind: Test,
    },
  )
  assert_true(
    (
      {
        package: @codegen.PackageName::parse("p").unwrap(),
        version: "1",
        kind: Test,
      } : @codegen.SymbolDependency) <
    {
      package: @codegen.PackageName::parse("p").unwrap(),
      version: "1",
      kind: Build,
    },
  )
}

///|
test "all dependencies are in lexical order" {
  let symbol = @codegen.Symbol::new(@codegen.SymbolName::parse("Main").unwrap())
    .with_dependency(lex_dep("bb"))
    .with_dependency(lex_dep("abc"))
  assert_eq(symbol.all_dependencies().map(d => d.package.to_string()), [
    "abc", "bb",
  ])
}

///|
test "writer imports are in lexical order" {
  let w = @codegen.CodeWriter::new(namespace=lex_ns("a"))
  let make = (namespace : String, name : String) => {
    @codegen.Symbol::new(
      @codegen.SymbolName::parse(name).unwrap(),
      namespace=lex_ns(namespace),
    )
  }
  w.write("$T $T", args=[
    @codegen.Sym(make("zz", "Item")),
    @codegen.Sym(make("abc", "Other")),
  ])
  assert_eq(w.imports().map(entry => entry.namespace.text), ["abc", "zz"])
  w.add_dependency(lex_dep("bb"))
  w.add_dependency(lex_dep("abc"))
  assert_eq(w.dependencies().map(d => d.package.to_string()), ["abc", "bb"])
}

///|
test "delegator flush and dependencies are in lexical order" {
  let provider = @codegen.SymbolProvider::new(shape => {
    @codegen.Symbol::new(@codegen.SymbolName::parse(shape.id.name()).unwrap())
  })
  let delegator = @codegen.WriterDelegator::new(provider)
  for name in ["b.txt", "aa.txt"] {
    delegator.use_file_writer(
      @codegen.OutputPath::parse(name).unwrap(),
      lex_ns("a"),
      w => w.write("x"),
    )
  }
  delegator.add_dependency(lex_dep("bb"))
  delegator.add_dependency(lex_dep("abc"))
  assert_eq(delegator.dependencies().map(d => d.package.to_string()), [
    "abc", "bb",
  ])
  assert_eq(delegator.flush().keys().collect(), ["aa.txt", "b.txt"])
}

///|
test "check_settings reports the first unknown key in lexical order" {
  let model = @smithy.Loader::new()
  .add_idl(
    "a.smithy", "$version: \"2\"\nnamespace example\nservice Weather {\n  version: \"1\"\n}\n",
  )
  .assemble().model.unwrap()
  let context = @codegen.PluginContext::from_build(
    model,
    @json.parse("{\"service\":\"example#Weather\",\"zz\":1,\"abc\":2}"),
  )
  let message = try context.check_settings([]) catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(message, "I found unknown setting `abc`.")
}

///|
test "integrations with equal priority are ordered by name lexically" {
  let items : Array[@codegen.Integration[Unit]] = [
    @codegen.Integration::new("bb"),
    @codegen.Integration::new("abc"),
  ]
  assert_eq(@codegen.sort_integrations(items).map(item => item.name), [
    "abc", "bb",
  ])
}

///|
test "an integration cycle lists its names in lexical order" {
  let items : Array[@codegen.Integration[Unit]] = [
    @codegen.Integration::new("bb", run_before=["abc"]),
    @codegen.Integration::new("abc", run_before=["bb"]),
  ]
  let message = try @codegen.sort_integrations(items) catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(message, "I found a cycle in the order of integrations: abc, bb.")
}

///|
test "closure and topological order break ties in lexical order" {
  let model = @smithy.Loader::new()
  .add_idl(
    "a.smithy", "$version: \"2\"\nnamespace example\nservice Svc {\n  version: \"1\"\n  operations: [Bb, Abc]\n}\noperation Bb {}\noperation Abc {}\n",
  )
  .assemble().model.unwrap()
  let svc = @smithy.ShapeId::parse("example#Svc").unwrap()
  assert_eq(@codegen.service_closure(model, svc).map(id => id.to_string()), [
    "example#Abc", "example#Bb", "example#Svc", "smithy.api#Unit",
  ])
  let bb = @smithy.ShapeId::parse("example#Bb").unwrap()
  let abc = @smithy.ShapeId::parse("example#Abc").unwrap()
  assert_eq(
    @codegen.topological_order(model, [bb, abc]).map(id => id.to_string()),
    ["example#Abc", "example#Bb"],
  )
}

///|
test "dependency versions compare in lexical order" {
  let make = (version : String) => {
    (
      {
        package: @codegen.PackageName::parse("p").unwrap(),
        version,
        kind: Runtime,
      } : @codegen.SymbolDependency)
  }
  assert_true(make("10") < make("9"))
  assert_true(make("1.10.0") < make("1.2"))
}

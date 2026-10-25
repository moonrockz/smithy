///|
fn delegator_model() -> @smithy.Model {
  @smithy.Loader::new()
  .add_idl(
    "a.smithy", "$version: \"2\"\nnamespace example\nstructure Order {}\nstructure Loose {}\n",
  )
  .assemble().model.unwrap()
}

///|
fn delegator_path(text : String) -> @codegen.OutputPath {
  @codegen.OutputPath::parse(text).unwrap()
}

///|
fn delegator_ns(text : String) -> @codegen.Namespace {
  @codegen.Namespace::parse(text, separator=".").unwrap()
}

///|
fn delegator_provider() -> @codegen.SymbolProvider {
  @codegen.SymbolProvider::new(shape => {
    let name = shape.id.name()
    let definition = if name == "Loose" {
      None
    } else {
      @codegen.OutputPath::parse("gen/\{name}.txt")
    }
    @codegen.Symbol::new(
      @codegen.SymbolName::parse(name).unwrap(),
      namespace=delegator_ns("example"),
      definition~,
    )
  })
}

///|
test "one writer per path, reused with a blank line" {
  let delegator = @codegen.WriterDelegator::new(delegator_provider())
  let path = delegator_path("a/one.txt")
  let ns = delegator_ns("example")
  delegator.use_file_writer(path, ns, w => w.write("first"))
  delegator.use_file_writer(path, ns, w => w.write("second"))
  let files = delegator.flush()
  assert_eq(files.length(), 1)
  assert_eq(files["a/one.txt"], "first\n\nsecond\n")
}

///|
test "a path with two namespaces raises WriterConflict" {
  let delegator = @codegen.WriterDelegator::new(delegator_provider())
  let path = delegator_path("a/one.txt")
  delegator.use_file_writer(path, delegator_ns("a"), w => w.write("x"))
  try
    delegator.use_file_writer(path, delegator_ns("b"), w => w.write("y"))
  catch {
    WriterConflict(text) =>
      assert_eq(
        text, "I found two namespaces, `a` and `b`, for output file `a/one.txt`.",
      )
    _ => fail("expected WriterConflict")
  } noraise {
    _ => fail("expected WriterConflict")
  }
  assert_eq(delegator.flush()["a/one.txt"], "x\n")
}

///|
test "shape writers use the symbol definition and namespace" {
  let model = delegator_model()
  let delegator = @codegen.WriterDelegator::new(delegator_provider())
  let order = model.get("example#Order").unwrap()
  let seen : Ref[String] = Ref("")
  delegator.use_shape_writer(order, w => {
    seen.val = w.namespace().text
    w.write("order")
  })
  assert_eq(seen.val, "example")
  assert_eq(delegator.flush()["gen/Order.txt"], "order\n")
  // The same path with the same namespace reuses the writer.
  delegator.use_file_writer(
    delegator_path("gen/Order.txt"),
    delegator_ns("example"),
    w => w.write("a"),
  )
  delegator.use_shape_writer(order, w => w.write("b"))
  assert_eq(delegator.flush()["gen/Order.txt"], "a\n\nb\n")
}

///|
test "a symbol with no definition raises MissingDefinition" {
  let model = delegator_model()
  let delegator = @codegen.WriterDelegator::new(delegator_provider())
  let loose = model.get("example#Loose").unwrap()
  try delegator.use_shape_writer(loose, w => w.write("x")) catch {
    MissingDefinition(id) => assert_eq(id.to_string(), "example#Loose")
    _ => fail("expected MissingDefinition")
  } noraise {
    _ => fail("expected MissingDefinition")
  }
  assert_eq(delegator.flush().length(), 0)
}

///|
test "interceptors reach every writer" {
  let delegator = @codegen.WriterDelegator::new(delegator_provider())
  let ns = delegator_ns("example")
  let body = (w : @codegen.CodeWriter) => {
    w.push_section(@codegen.Section::new("tail"))
    w.write("body")
    w.pop_section()
  }
  // The first writer exists before the interceptors.
  delegator.use_file_writer(delegator_path("early.txt"), ns, w => w.write("top"))
  delegator.add_interceptors([
    @codegen.Interceptor::appender("tail", (w, _) => w.write("one")),
  ])
  delegator.add_interceptors([
    @codegen.Interceptor::appender("tail", (w, _) => w.write("two")),
  ])
  delegator.use_file_writer(delegator_path("early.txt"), ns, body)
  delegator.use_file_writer(delegator_path("late.txt"), ns, body)
  let files = delegator.flush()
  assert_eq(files["early.txt"], "top\n\nbody\none\ntwo\n")
  assert_eq(files["late.txt"], "body\none\ntwo\n")
}

///|
test "flush renders sorted paths and clears the writers" {
  let delegator = @codegen.WriterDelegator::new(delegator_provider(), render=w => {
    "[" + w.to_string() + "]"
  })
  let ns = delegator_ns("example")
  delegator.use_file_writer(delegator_path("b.txt"), ns, w => w.write("b"))
  delegator.use_file_writer(delegator_path("a.txt"), ns, w => w.write("a"))
  let dependency : @codegen.SymbolDependency = {
    package: @codegen.PackageName::parse("pkg/a").unwrap(),
    version: "1.0.0",
    kind: Runtime,
  }
  delegator.add_dependency(dependency)
  delegator.add_dependency(dependency)
  let files = delegator.flush()
  assert_eq(files.keys().collect(), ["a.txt", "b.txt"])
  assert_eq(files["a.txt"], "[a\n]")
  assert_eq(delegator.flush().length(), 0)
  assert_eq(delegator.dependencies(), [dependency])
}

///|
test "the conflict check compares the requested namespaces" {
  // The factory ignores the namespace, so the writers have the root namespace.
  let delegator = @codegen.WriterDelegator::new(delegator_provider(), factory=(
    _,
    _,
  ) => @codegen.CodeWriter::new())
  let path = delegator_path("a/one.txt")
  delegator.use_file_writer(path, delegator_ns("a"), w => w.write("x"))
  delegator.use_file_writer(path, delegator_ns("a"), w => w.write("y"))
  try
    delegator.use_file_writer(path, delegator_ns("b"), w => w.write("z"))
  catch {
    WriterConflict(text) =>
      assert_eq(
        text, "I found two namespaces, `a` and `b`, for output file `a/one.txt`.",
      )
    _ => fail("expected WriterConflict")
  } noraise {
    _ => fail("expected WriterConflict")
  }
  assert_eq(delegator.flush()["a/one.txt"], "x\n\ny\n")
}

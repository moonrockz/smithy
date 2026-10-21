///|
fn model(source : String) -> @smithy.Model raise {
  let loader = @smithy.Loader::new()
  ignore(
    loader.add_idl(
      "model.smithy",
      "$version: \"2\"\nnamespace example\n" + source,
    ),
  )
  let result = loader.assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
fn target(name : String) -> @smithy.ShapeId {
  @smithy.ShapeId::parse("example#" + name).unwrap()
}

///|
test "prepare rejects nondata and missing targets" {
  let m = model(
    "structure Input {}\noperation Op { input: Input }\nservice Api {version: \"1\", operations: [Op]}\nresource Item {}",
  )
  for name in ["Missing", "Op", "Api", "Item"] {
    let mut rejected = false
    ignore(@validation.PreparedValidator::prepare(m, target(name))) catch {
      @validation.InvalidTarget(id, _) => {
        assert_eq(id, target(name))
        rejected = true
      }
      _ => fail("Expected InvalidTarget")
    }
    assert_true(rejected)
  }
}

///|
test "prepare handles recursive shapes and directly selected members" {
  let m = model("structure Node { next: Node, value: String }")
  ignore(@validation.PreparedValidator::prepare(m, target("Node")))
  ignore(@validation.PreparedValidator::prepare(m, target("Node$value")))
}

///|
test "prepare rejects dangling members in caller constructed graphs" {
  let m = model("structure Input { value: String }")
  let id = target("Input$value")
  let member_ = m.shapes.get(id).unwrap()
  m.shapes[id] = { ..member_, body: @smithy.Member(target=target("Missing")), }
  let mut rejected = false
  ignore(@validation.PreparedValidator::prepare(m, target("Input"))) catch {
    @validation.InvalidModel(_, _) => rejected = true
    _ => fail("Expected InvalidModel")
  }
  assert_true(rejected)
}

///|
test "prepare rejects unsupported constraints instead of accepting them" {
  for
    source in [
      "@timestampFormat(\"http-date\")\ntimestamp Value", "@pattern(\"(?=abc)abc\")\nstring Value",
    ] {
    let m = model(source)
    let mut rejected = false
    ignore(@validation.PreparedValidator::prepare(m, target("Value"))) catch {
      @validation.UnsupportedConstraint(_, _) => rejected = true
      _ => fail("Expected UnsupportedConstraint")
    }
    assert_true(rejected)
  }
}

///|
test "prepare checks JSON naming collisions even on programmatic models" {
  let m = model("structure Input { a: String, b: String }")
  let trait_id = @smithy.ShapeId::parse("smithy.api#jsonName").unwrap()
  for name in ["a", "b"] {
    m.shapes.get(target("Input$" + name)).unwrap().traits[trait_id] = @smithy.String(
      "wire",
    )
  }
  let mut rejected = false
  ignore(
    @validation.PreparedValidator::prepare(
      m,
      target("Input"),
      config=@validation.Config::new(member_names=JsonName),
    ),
  ) catch {
    @validation.InvalidModel(_, _) => rejected = true
    _ => fail("Expected InvalidModel")
  }
  assert_true(rejected)
}

///|
test "prepare rejects mixin values malformed bounds and runtime conditions" {
  let mixed_model = model("@mixin\nstructure Mix {}")
  let mut mixin_rejected = false
  ignore(@validation.PreparedValidator::prepare(mixed_model, target("Mix"))) catch {
    @validation.InvalidTarget(_, _) => mixin_rejected = true
    _ => fail("Expected invalid mixin target")
  }
  assert_true(mixin_rejected)
  let m = model("integer Value")
  let shape = m.shapes.get(target("Value")).unwrap()
  let range = @smithy.ShapeId::parse("smithy.api#range").unwrap()
  shape.traits[range] = @smithy.Object({ "min": @smithy.String("0") })
  let mut malformed = false
  ignore(@validation.PreparedValidator::prepare(m, target("Value"))) catch {
    @validation.InvalidModel(_, _) => malformed = true
    _ => fail("Expected malformed bound rejection")
  }
  assert_true(malformed)
  ignore(shape.traits.remove(range))
  shape.traits[@smithy.ShapeId::parse("smithy.contracts#conditions").unwrap()] = @smithy.Object(
    Map([]),
  )
  let mut unsupported = false
  ignore(@validation.PreparedValidator::prepare(m, target("Value"))) catch {
    @validation.UnsupportedConstraint(_, _) => unsupported = true
    _ => fail("Expected unsupported runtime condition")
  }
  assert_true(unsupported)
}

///|
test "prepare rejects empty enums and collection references that are not members" {
  let enum_model = model("enum Value {\n A\n}")
  let shape = enum_model.shapes.get(target("Value")).unwrap()
  enum_model.shapes[target("Value")] = { ..shape, body: @smithy.Enum([]), }
  let mut rejected = false
  ignore(@validation.PreparedValidator::prepare(enum_model, target("Value"))) catch {
    @validation.InvalidModel(_, _) => rejected = true
    _ => fail("Expected invalid enum rejection")
  }
  assert_true(rejected)
  let list_model = model("list Value { member: String }")
  let shape = list_model.shapes.get(target("Value")).unwrap()
  list_model.shapes[target("Value")] = {
    ..shape,
    body: @smithy.List(@smithy.ShapeId::parse("smithy.api#String").unwrap()),
  }
  rejected = false
  ignore(@validation.PreparedValidator::prepare(list_model, target("Value"))) catch {
    @validation.InvalidModel(_, _) => rejected = true
    _ => fail("Expected invalid collection member rejection")
  }
  assert_true(rejected)
}

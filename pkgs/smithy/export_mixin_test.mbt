///|
fn mixin_model(source : String) -> @smithy.Model raise {
  let result = @smithy.Loader::new().add_idl("mixins.smithy", source).assemble()
  guard result.model is Some(model) else { fail("model did not assemble") }
  model
}

///|
test "preserved mixin export emits introduced traits members and member apply entries" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@mixin @documentation("inherited")
    #|structure Base { @required inherited: String }
    #|@documentation("inherited")
    #|structure Derived with [Base] { @documentation("local") inherited: String, own: String }
  let model = mixin_model(source)
  let actual = @syntax.encode_json_ast(model.to_json_ast(preserve_mixins=true))
  let expected : Json = {
    "smithy": "2.0",
    "shapes": {
      "example#Base": {
        "type": "structure",
        "traits": {
          "smithy.api#mixin": {},
          "smithy.api#documentation": "inherited",
        },
        "members": {
          "inherited": {
            "target": "smithy.api#String",
            "traits": { "smithy.api#required": {} },
          },
        },
      },
      "example#Derived": {
        "type": "structure",
        "mixins": [{ "target": "example#Base" }],
        "traits": { "smithy.api#documentation": "inherited" },
        "members": { "own": { "target": "smithy.api#String" } },
      },
      "example#Derived$inherited": {
        "type": "apply",
        "traits": { "smithy.api#documentation": "local" },
      },
    },
  }
  assert_eq(actual, expected)
  assert_eq(
    model.get("example#Derived$inherited").unwrap().mixins.map(id => {
      id.to_string()
    }),
    ["example#Base$inherited"],
  )
}

///|
test "preserved service mixins omit inherited version and bindings" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@mixin
    #|service Base { version: "1", operations: [Get] }
    #|service Derived with [Base] {}
    #|operation Get {}
  let model = mixin_model(source)
  let document = model.to_json_ast(preserve_mixins=true)
  let encoded = @syntax.encode_json_ast(document)
  guard encoded is Object(fields) &&
    fields.get("shapes") is Some(Object(shapes)) else {
    fail("missing shapes")
  }
  assert_eq(
    shapes.get("example#Derived"),
    Some(
      Json::object({
        "type": "service",
        "mixins": [{ "target": "example#Base" }],
      }),
    ),
  )
  let roundtrip = @smithy.Loader::new()
  .add_ast("roundtrip.json", document)
  .assemble().model.unwrap()
  assert_eq(
    roundtrip.get("example#Derived").unwrap().body,
    model.get("example#Derived").unwrap().body,
  )
}

///|
test "removing mixin relationships discards inherited content and keeps introduced shape overrides" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@mixin @documentation("base") @sensitive
    #|structure Base { @required inherited: String }
    #|@documentation("local")
    #|structure Derived with [Base] { own: String }
  let model = mixin_model(source)
  let updated = model.remove_mixin_relationships([
    @smithy.ShapeId::parse("example#Base").unwrap(),
  ])
  let derived = updated.get("example#Derived").unwrap()
  assert_true(derived.mixins.is_empty())
  assert_eq(
    derived.trait_value("smithy.api#documentation"),
    Some(@smithy.String("local")),
  )
  assert_true(derived.trait_value("smithy.api#sensitive") is None)
  assert_true(updated.get("example#Derived$inherited") is None)
  assert_true(updated.get("example#Derived$own") is Some(_))
}

///|
test "preserved mixins retain inheritance order and external member overrides" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@mixin @documentation("first")
    #|structure ZFirst { value: String }
    #|@mixin @documentation("last")
    #|structure ALast { value: String }
    #|structure Derived with [ZFirst, ALast] {}
    #|apply Derived$value @required
  let model = mixin_model(source)
  let exported = model.to_json_ast(preserve_mixins=true)
  let roundtrip = @smithy.Loader::new()
  .add_ast("roundtrip.json", exported)
  .assemble().model.unwrap()
  assert_eq(
    roundtrip.get("example#Derived").unwrap().mixins.map(id => id.to_string()),
    ["example#ZFirst", "example#ALast"],
  )
  assert_eq(
    roundtrip.get("example#Derived").unwrap().traits,
    model.get("example#Derived").unwrap().traits,
  )
  assert_eq(
    roundtrip.get("example#Derived$value").unwrap().traits,
    model.get("example#Derived$value").unwrap().traits,
  )
}

///|
test "preserved source fragments do not require their mixin definitions" {
  let source = "$version: \"2\"\nnamespace example\n@mixin\nstructure Base { inherited: String }\nstructure Derived with [Base] { own: String }\napply Derived$inherited @required\n"
  let model = mixin_model(source)
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  for id, shape in model.shapes {
    if id.root().to_string() == "example#Derived" {
      shapes[id] = shape
    }
  }
  let fragment : @smithy.Model = { shapes, metadata: Map([]), }
  let exported = fragment.to_json_ast(preserve_mixins=true)
  assert_true(exported.shapes.unwrap().contains("example#Derived"))
  assert_true(exported.shapes.unwrap().contains("example#Derived$inherited"))
  assert_false(exported.shapes.unwrap().contains("example#Base"))
}

///|
test "removing a transitive mixin updates the descendants without losing local members" {
  let source = "$version: \"2\"\nnamespace example\n@mixin\nstructure Base { inherited: String }\n@mixin\nstructure Middle with [Base] { middle: String }\nstructure Derived with [Middle] { own: String }\n"
  let model = mixin_model(source)
  let updated = model.remove_mixin_relationships([
    @smithy.ShapeId::parse("example#Base").unwrap(),
  ])
  assert_true(updated.get("example#Middle$inherited") is None)
  assert_true(updated.get("example#Derived$inherited") is None)
  assert_true(updated.get("example#Derived$middle") is Some(_))
  assert_true(updated.get("example#Derived$own") is Some(_))
}

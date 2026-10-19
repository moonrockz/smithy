///|
fn shape_projection(source : String, transform : String) -> String raise {
  let loaded = @smithy.Loader::new().add_idl("model.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"filtered\":{\"transforms\":[" +
    transform +
    "]}}}",
  )
  let output = @build.BuildRunner::new(config).run(model)
  output.get("filtered/model/model.json").unwrap()
}

///|
test "trait filters retain valid prelude target graph" {
  let model = @smithy.Loader::new()
  .add_idl(
    "input.smithy", "$version: \"2\"\nnamespace example\n@trait\nstructure marker {}\n@marker\nstring Value\n",
  )
  .assemble().model.unwrap()
  let model = @build.apply_transform(model, {
    name: "includeTraits",
    args: Json::object({ "traits": ["example#"] }),
  })
  let errors = model
    .validation_events()
    .filter(e => e.severity == "ERROR" || e.severity == "DANGER")
  assert_true(
    errors.is_empty(),
    msg=errors.map(e => e.id + ": " + e.message).join("\n"),
  )
}

///|
test "upstream mixed shape fixture assembles before trait filtering" {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "mixin-cycle-test.smithy",
      @fs.read_file_to_string(
        "../../tests/tck/build/transforms/mixin-cycle-test.smithy",
      ),
    )
    .assemble()
  assert_true(
    loaded.model is Some(_),
    msg=loaded.diagnostics.map(d => d.message).join("\n"),
  )
}

///|
test "filtering mixins removes inherited members and preserves local shape trait overrides" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@mixin @documentation("base") @sensitive
    #|structure Base { inherited: String }
    #|@documentation("local")
    #|structure Derived with [Base] { own: String }
  let model = @smithy.Loader::new().add_idl("mixins.smithy", source).assemble().model.unwrap()
  let updated = @build.apply_transform(model, {
    name: "excludeShapesBySelector",
    args: { "selector": "[trait|mixin]" },
  })
  let derived = updated.get("example#Derived").unwrap()
  assert_true(updated.get("example#Base") is None)
  assert_true(updated.get("example#Derived$inherited") is None)
  assert_true(updated.get("example#Derived$own") is Some(_))
  assert_true(derived.mixins.is_empty())
  assert_eq(
    derived.trait_value("smithy.api#documentation"),
    Some(@smithy.String("local")),
  )
  assert_true(derived.trait_value("smithy.api#sensitive") is None)
}

///|
test "flatten mixins clears inherited member provenance and keeps effective contents" {
  let source = "$version: \"2\"\nnamespace example\n@mixin\nstructure Base { @required value: String }\nstructure Derived with [Base] {}"
  let model = @smithy.Loader::new().add_idl("mixins.smithy", source).assemble().model.unwrap()
  let updated = @build.apply_transform(model, {
    name: "flattenAndRemoveMixins",
    args: {},
  })
  assert_true(updated.get("example#Derived$value").unwrap().mixins.is_empty())
  assert_true(
    updated
    .get("example#Derived$value")
    .unwrap()
    .trait_value("smithy.api#required")
    is Some(_),
  )
  assert_eq(updated.to_json_ast(preserve_mixins=true), updated.to_json_ast())
}

///|
test "selector filtering removes members and service operation bindings" {
  let source = @fs.read_file_to_string(
    "../../tests/tck/build/transforms/transform-by-selector.smithy",
  )
  let output = shape_projection(
    source, "{\"name\":\"excludeShapesBySelector\",\"args\":{\"selector\":\":is(operation[id|name=GetFoo], member[trait|tags|(values)=beta])\"}}",
  )
  assert_false(output.contains("smithy.example#GetFoo"))
  assert_false(output.contains("\"BAR\""))
  assert_true(output.contains("smithy.example#GetBar"))
}

///|
test "include closures follows cyclic targets and keeps unrelated namespaces only when reached" {
  let source =
    #|$version: "2"
    #|metadata shapeClosures = [{id: "example#Closure", includeBySelector: "[id=example#Root]"}]
    #|namespace example
    #|structure Root { next: Child }
    #|structure Child { next: Root }
    #|structure Unrelated {}
  let output = shape_projection(
    source, "{\"name\":\"includeClosures\",\"args\":{\"closures\":[\"example#Closure\"]}}",
  )
  assert_true(output.contains("example#Root"))
  assert_true(output.contains("example#Child"))
  assert_false(output.contains("example#Unrelated"))
}

///|
test "remove deprecated uses strict date and version boundaries from reference fixture" {
  let source = @fs.read_file_to_string(
    "../../tests/tck/build/transforms/remove-deprecated.smithy",
  )
  let output = shape_projection(
    source, "{\"name\":\"removeDeprecatedShapes\",\"args\":{\"relativeDate\":\"2024-10-10\",\"relativeVersion\":\"1.1.0\"}}",
  )
  assert_false(output.contains("smithy.example#FilteredDateBefore"))
  assert_false(output.contains("smithy.example#FilteredVersionBefore"))
  assert_true(output.contains("smithy.example#NotFilteredDateEquals"))
  assert_true(output.contains("smithy.example#NotFilteredVersionEquals"))
}

///|
test "remove unused shapes retains service closure and removes detached cycles" {
  let source =
    #|$version: "2"
    #|namespace example
    #|service Api { version: "1", operations: [Get] }
    #|operation Get { output: Result }
    #|structure Result { value: String }
    #|structure Detached { next: Detached }
  let output = shape_projection(source, "{\"name\":\"removeUnusedShapes\"}")
  assert_true(output.contains("example#Result"))
  assert_false(output.contains("example#Detached"))
}

///|
test "flatten mixins retains inherited members and removes mixin shapes" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@mixin
    #|structure Common { value: String }
    #|structure Concrete with [Common] {}
  let output = shape_projection(source, "{\"name\":\"flattenAndRemoveMixins\"}")
  assert_false(output.contains("example#Common"))
  assert_true(output.contains("\"value\""))
}

///|
test "tag filters clean member targets and trait applications" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@tags(["hidden"])
    #|string Hidden
    #|@tags(["hidden"])
    #|@trait
    #|structure marker {}
    #|@marker
    #|structure Visible { hidden: Hidden, visible: String }
  let output = shape_projection(
    source, "{\"name\":\"excludeShapesByTag\",\"args\":{\"tags\":[\"hidden\"]}}",
  )
  assert_false(output.contains("example#Hidden"))
  assert_false(output.contains("example#marker"))
  assert_false(output.contains("\"hidden\""))
  assert_true(output.contains("\"visible\""))
}

///|
test "namespace and service inclusion have distinct scopes" {
  let source =
    #|$version: "2"
    #|namespace example
    #|service Api { version: "1", operations: [Get] }
    #|service Other { version: "1" }
    #|operation Get {}
    #|string Name
  let output = shape_projection(
    source, "{\"name\":\"includeServices\",\"args\":{\"services\":[\"example#Api\"]}}",
  )
  assert_true(output.contains("example#Api"))
  assert_true(output.contains("example#Name"))
  assert_false(output.contains("example#Other"))
  let output = shape_projection(
    source, "{\"name\":\"includeNamespaces\",\"args\":{\"namespaces\":[]}}",
  )
  assert_false(output.contains("example#"))
}

///|
test "trait exclusion and selector inclusion retain consistent member containers" {
  let source =
    #|$version: "2"
    #|namespace example
    #|structure Result { @deprecated secret: String, public: String }
    #|list Names { member: String }
  let output = shape_projection(
    source, "{\"name\":\"excludeShapesByTrait\",\"args\":{\"traits\":[\"deprecated\"]}}",
  )
  assert_false(output.contains("\"secret\""))
  assert_true(output.contains("\"public\""))
  let output = shape_projection(
    source, "{\"name\":\"includeShapesBySelector\",\"args\":{\"selector\":\":is(list, structure, member[id|member=public])\"}}",
  )
  assert_true(output.contains("example#Names"))
  assert_false(output.contains("\"secret\""))
}

///|
test "remove unused shapes retains shapes referenced by idRef trait values" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@trait
    #|structure reference { @idRef target: String }
    #|@reference(target: "example#Referenced")
    #|service Api { version: "1" }
    #|structure Referenced {}
    #|structure Unused {}
  let output = shape_projection(source, "{\"name\":\"removeUnusedShapes\"}")
  assert_true(output.contains("\"example#Referenced\": {"))
  assert_false(output.contains("example#Unused"))
}

///|
test "remove trait definitions preserves applications and removes support shapes" {
  let loaded = @smithy.Loader::new()
    .add_json(
      "traits.json",
      @fs.read_file_to_string(
        "../../tests/tck/build/transforms/remove-trait-definitions.json",
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"filtered\":{\"transforms\":[{\"name\":\"removeTraitDefinitions\"}]}}}",
  )
  let output = @build.BuildRunner::new(config)
    .run(model)
    .get("filtered/model/model.json")
    .unwrap()
  assert_false(output.contains("ns.foo#BarTraitShapeMember"))
  assert_true(output.contains("ns.foo#bar"))
  assert_true(output.contains("ns.foo#baz"))
  assert_false(output.contains("\"members\""))
}

///|
test "invalid closure selector and deprecation arguments fail" {
  let source = "$version: \"2\"\nnamespace example\nstring Name\n"
  for
    transform in [
      "{\"name\":\"includeClosures\",\"args\":{\"closures\":[]}}", "{\"name\":\"includeClosures\",\"args\":{\"closures\":[\"missing\"]}}",
      "{\"name\":\"includeShapesBySelector\",\"args\":{\"selector\":\"[\"}}", "{\"name\":\"removeDeprecatedShapes\",\"args\":{\"relativeDate\":\"2024-13-01\"}}",
      "{\"name\":\"removeDeprecatedShapes\",\"args\":{\"relativeVersion\":\"1.0\"}}",
    ] {
    assert_true(
      try shape_projection(source, transform) catch {
        @build.InvalidBuildConfig(_) => true
        _ => false
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "legacy tag arguments select the same shapes as named arguments" {
  let source = "$version: \"2\"\nnamespace example\n@tags([\"export\"])\nstring Included\nstring Excluded\n"
  for args in ["[\"export\"]", "{\"__args\":[\"export\"]}"] {
    let output = shape_projection(
      source,
      "{\"name\":\"includeShapesByTag\",\"args\":" + args + "}",
    )
    assert_true(output.contains("\"example#Included\": {"))
    assert_false(output.contains("\"example#Excluded\": {"))
  }
}

///|
test "remove unused shapes retains the container of an idRef member target" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@trait
    #|@idRef
    #|string reference
    #|@reference("example#Referenced$value")
    #|service Api { version: "1" }
    #|structure Referenced { value: String }
  let output = shape_projection(source, "{\"name\":\"removeUnusedShapes\"}")
  assert_true(output.contains("\"example#Referenced\": {"))
}

///|
test "remove unused shapes matches vendored trait tree shaking fixture" {
  let loaded = @smithy.Loader::new()
    .add_json(
      "tree.json",
      @fs.read_file_to_string(
        "../../tests/tck/build/transforms/tree-shaking-traits.json",
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"filtered\":{\"transforms\":[{\"name\":\"removeUnusedShapes\"}]}}}",
  )
  let output = @build.BuildRunner::new(config)
    .run(model)
    .get("filtered/model/model.json")
    .unwrap()
  assert_true(output.contains("\"ns.foo#bar\": {"))
  assert_true(output.contains("\"ns.foo#BarTraitShapeMember\": {"))
  assert_false(output.contains("\"ns.foo#quux\": {"))
  assert_false(output.contains("\"ns.foo#QuuxTraitShapeMember\": {"))
}

///|
test "remove trait definitions preserves tagged definitions and shared support shapes" {
  let loaded = @smithy.Loader::new()
    .add_json(
      "traits.json",
      @fs.read_file_to_string(
        "../../tests/tck/build/transforms/retain-tagged-trait-definitions.json",
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"filtered\":{\"transforms\":[{\"name\":\"removeTraitDefinitions\",\"args\":{\"exportTagged\":[\"export\"]}}]}}}",
  )
  let output = @build.BuildRunner::new(config)
    .run(model)
    .get("filtered/model/model.json")
    .unwrap()
  assert_true(output.contains("\"ns.foo#bar\": {"))
  assert_true(output.contains("\"ns.foo#BarTraitShapeMember\": {"))
  assert_false(output.contains("\"ns.foo#qux\": {\n            \"type\""))
  assert_true(output.contains("\"ns.foo#qux\": {"))
}

///|
test "filtering resource shapes cleans reference trait values on structures" {
  let source =
    #|$version: "2"
    #|namespace example
    #|resource Thing {}
    #|@references([{resource: "example#Thing"}])
    #|structure Data {}
  let output = shape_projection(
    source, "{\"name\":\"excludeShapesBySelector\",\"args\":{\"selector\":\"resource\"}}",
  )
  assert_false(output.contains("example#Thing"))
  assert_true(output.contains("smithy.api#references"))
}

///|
test "filtering traits cleans protocol definition trait requirements" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@trait
    #|structure marker {}
    #|@trait(selector: "service")
    #|@protocolDefinition(traits: ["example#marker"])
    #|structure protocol {}
  let output = shape_projection(
    source, "{\"name\":\"excludeShapesBySelector\",\"args\":{\"selector\":\"[id=example#marker]\"}}",
  )
  assert_false(output.contains("example#marker"))
  assert_true(output.contains("example#protocol"))
}

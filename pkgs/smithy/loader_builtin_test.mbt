///|
fn tag_definitions() -> String {
  (
    #|$version: "2"
    #|namespace example.tags
    #|@trait(selector: "structure")
    #|structure tag { label: String }
  )
}

///|
fn tagged_source() -> String {
  (
    #|$version: "2"
    #|namespace example
    #|use example.tags#tag
    #|@tag(label: "first")
    #|structure Tagged {}
  )
}

///|
fn tag_loader() -> @smithy.Loader {
  @smithy.Loader::new().add_builtin_idl("<example-tags>", tag_definitions())
}

///|
fn errors(result : @smithy.LoadResult) -> Array[String] {
  result.diagnostics
  .filter(d => d.severity == @syntax.Severity::Error)
  .map(d => "\{d.code}: \{d.message}")
}

///|
fn exported_shapes(
  model : @smithy.Model,
  include_prelude~ : Bool = false,
) -> Map[String, Json] raise {
  guard @syntax.encode_json_ast(model.to_json_ast(include_prelude~))
    is { "shapes": Object(shapes), .. } else {
    fail("Expected shapes in the JSON AST")
  }
  shapes
}

///|
test "a built-in IDL source resolves its traits and stays out of exports" {
  let result = tag_loader().add_idl("model.smithy", tagged_source()).assemble()
  assert_eq(errors(result), [])
  let model = result.model.unwrap()
  assert_eq(
    model.get("example.tags#tag").unwrap().source.file,
    "<example-tags>",
  )
  let shapes = exported_shapes(model)
  assert_false(shapes.contains("example.tags#tag"))
  guard shapes.get("example#Tagged") is Some({ "traits": Object(traits), .. }) else {
    fail("Expected the trait application on example#Tagged")
  }
  assert_true(traits.contains("example.tags#tag"))
  assert_true(
    exported_shapes(model, include_prelude=true).contains("example.tags#tag"),
  )
  assert_eq(model.to_idl().keys().to_array(), ["example"])
}

///|
test "an exported model loads again with the same built-in source" {
  let model = tag_loader().add_idl("model.smithy", tagged_source()).assemble().model.unwrap()
  let again = tag_loader().add_ast("model.json", model.to_json_ast()).assemble()
  assert_eq(errors(again), [])
  let shape = again.model.unwrap().get("example#Tagged").unwrap()
  assert_true(shape.trait_value("example.tags#tag") is Some(_))
  let full = tag_loader()
    .add_ast("full.json", model.to_json_ast(include_prelude=true))
    .assemble()
  assert_eq(errors(full), [])
}

///|
test "a user source cannot redefine or extend a built-in IDL shape" {
  let same = tag_loader().add_idl("copy.smithy", tag_definitions()).assemble()
  assert_eq(errors(same), [])
  let changed = tag_loader()
    .add_idl(
      "changed.smithy", "$version: \"2\"\nnamespace example.tags\n@trait(selector: \"structure\")\nstructure tag { other: Integer }\n",
    )
    .assemble()
  assert_true(
    changed.diagnostics
    .iter()
    .any(d => {
      d.code == "SM-MODEL-014" &&
      d.message == "I cannot redefine the built-in shape example.tags#tag."
    }),
  )
  let applied = tag_loader()
    .add_idl(
      "apply.smithy", "$version: \"2\"\nnamespace example\napply example.tags#tag @documentation(\"x\")\n",
    )
    .assemble()
  assert_true(applied.diagnostics.iter().any(d => d.code == "SM-MODEL-014"))
}

///|
test "a built-in source name is reserved for built-in definitions" {
  let result = tag_loader()
    .add_idl(
      "<example-tags>", "$version: \"2\"\nnamespace example\nstructure Other {}\n",
    )
    .assemble()
  assert_true(
    result.diagnostics
    .iter()
    .any(d => {
      d.code == "SM-MODEL-001" &&
      d.message ==
      "I reserve the source name <example-tags> for built-in definitions."
    }),
  )
  let prelude = @smithy.Loader::new()
    .add_builtin_idl(
      "<prelude>", "$version: \"2\"\nnamespace example\nstructure Other {}\n",
    )
    .assemble()
  assert_true(prelude.diagnostics.iter().any(d => d.code == "SM-MODEL-001"))
}

///|
test "each loader has its own built-in sources" {
  let builtin = tag_loader().add_idl("model.smithy", tagged_source()).assemble()
  // The same name and text are a user source in a loader without the builtin.
  let user = @smithy.Loader::new()
    .add_idl("<example-tags>", tag_definitions())
    .add_idl("model.smithy", tagged_source())
    .assemble()
  assert_eq(errors(builtin), [])
  assert_eq(errors(user), [])
  let builtin = builtin.model.unwrap()
  let user = user.model.unwrap()
  assert_true(builtin.get("example.tags#tag").unwrap().source.is_builtin())
  assert_false(user.get("example.tags#tag").unwrap().source.is_builtin())
  assert_eq(
    user.get("example.tags#tag").unwrap().source.kind,
    @smithy.SourceKind::User,
  )
  assert_false(exported_shapes(builtin).contains("example.tags#tag"))
  assert_true(exported_shapes(user).contains("example.tags#tag"))
  assert_eq(builtin.to_idl().keys().to_array(), ["example"])
  let namespaces = user.to_idl().keys().to_array()
  namespaces.sort()
  assert_eq(namespaces, ["example", "example.tags"])
}

///|
test "the prelude has the built-in kind and user sources have the user kind" {
  let model = @smithy.Loader::new()
  .add_idl("model.smithy", tagged_source())
  .add_idl("tags.smithy", tag_definitions())
  .assemble().model.unwrap()
  assert_true(model.get("smithy.api#String").unwrap().source.is_builtin())
  assert_false(model.get("example#Tagged").unwrap().source.is_builtin())
  assert_eq(@smithy.SourceLocation::new("a.smithy"), {
    file: "a.smithy",
    path: "",
    span: None,
    kind: User,
  })
}

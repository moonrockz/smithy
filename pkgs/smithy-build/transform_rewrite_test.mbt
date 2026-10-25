///|
fn rewrite_projection(
  model : @smithy.Model,
  transform : String,
) -> @smithy.Model raise {
  let captured : Map[String, @smithy.Model] = Map([])
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"rewritten\":{\"transforms\":[" +
    transform +
    "],\"plugins\":{\"capture\":{}}}}}",
  )
  let runner = @build.BuildRunner::new(config).register_plugin("capture", (
    model,
    _,
  ) => {
    captured["model"] = model
    Map([])
  })
  let _ = runner.run(model)
  captured.get("model").unwrap()
}

///|
fn rewrite_fixture(name : String) -> @smithy.Model raise {
  let loaded = @smithy.Loader::new()
    .add_json(
      name,
      @fs.read_file_to_string("../../tests/tck/build/transforms/" + name),
    )
    .assemble()
  guard loaded.model is Some(model) else { fail("fixture did not assemble") }
  model
}

///|
fn rewrite_idl(source : String) -> @smithy.Model raise {
  let loaded = @smithy.Loader::new().add_idl("model.smithy", source).assemble()
  guard loaded.model is Some(model) else { fail("model did not assemble") }
  model
}

///|
test "renaming mixins retains declarations and remaps inherited member provenance" {
  let original = rewrite_idl(
    "$version: \"2\"\nnamespace example\n@mixin\nstructure Base { value: String }\nstructure Derived with [Base] { @required value: String }\n",
  )
  let model = @build.apply_transform(original, {
    name: "renameShapes",
    args: {
      "renamed": {
        "example#Base": "renamed#Common",
        "example#Derived": "renamed#Concrete",
      },
    },
  })
  assert_eq(
    model.get("renamed#Concrete").unwrap().mixins.map(id => id.to_string()),
    ["renamed#Common"],
  )
  assert_eq(
    model.get("renamed#Concrete$value").unwrap().mixins.map(id => id.to_string()),
    ["renamed#Common$value"],
  )
  let exported = model.to_json_ast(preserve_mixins=true)
  let roundtrip = @smithy.Loader::new()
  .add_ast("preserved.json", exported)
  .assemble().model.unwrap()
  assert_eq(roundtrip.to_json_ast(), model.to_json_ast())
}

///|
test "change types preserves legacy set identity across renaming and explicit list conversion" {
  let model = rewrite_idl(
    "$version: \"2\"\nnamespace example\nlist Values { member: String }\n",
  )
  let model = @build.apply_transform(model, {
    name: "changeTypes",
    args: { "shapeTypes": { "example#Values": "set" } },
  })
  assert_true(model.get("example#Values").unwrap().is_legacy_set())
  let model = @build.apply_transform(model, {
    name: "renameShapes",
    args: { "renamed": { "example#Values": "example#Renamed" } },
  })
  assert_true(model.get("example#Renamed").unwrap().is_legacy_set())
  let model = @build.apply_transform(model, {
    name: "changeTypes",
    args: { "shapeTypes": { "example#Renamed": "list" } },
  })
  assert_false(model.get("example#Renamed").unwrap().is_legacy_set())
  assert_true(
    model.get("example#Renamed").unwrap().trait_value("smithy.api#uniqueItems")
    is Some(_),
  )
}

///|
test "rename shapes updates fixture references and member identifiers" {
  let model = rewrite_projection(
    rewrite_fixture("rename-shapes.json"),
    "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"ns.foo#Bar\":\"ns.foo#Baz\",\"ns.foo#Qux\":\"ns.foo#Corge\"}}}",
  )
  assert_true(model.get("ns.foo#Bar") is None)
  assert_true(model.get("ns.foo#Baz") is Some(_))
  assert_true(model.get("ns.foo#Corge$foo") is Some(_))
  guard model.get("ns.foo#Baz") is Some(shape) &&
    shape.body is @smithy.Operation(output~, ..) else {
    fail("missing renamed operation")
  }
  assert_eq(output.to_string(), "ns.foo#Corge")
}

///|
test "flatten namespaces honors tags and skips conflicting tagged shapes" {
  let model = rewrite_projection(
    rewrite_fixture("flatten-namespaces.json"),
    "{\"name\":\"flattenNamespaces\",\"args\":{\"namespace\":\"ns.qux\",\"service\":\"ns.foo#MyService\",\"includeTagged\":[\"included\",\"conflicting\"]}}",
  )
  for
    id in [
      "ns.qux#MyService", "ns.qux#MyOperation", "ns.qux#MyOperationOutput$foo", "ns.qux#UnconnectedFromService",
      "ns.grault#MyOperationOutput",
    ] {
    assert_true(model.get(id) is Some(_))
  }
  assert_true(model.get("ns.corge#UnconnectedFromService") is None)
}

///|
test "flatten namespaces applies service renames then clears the rename map" {
  let model = rewrite_projection(
    rewrite_fixture("flatten-namespaces-with-renames.json"),
    "{\"name\":\"flattenNamespaces\",\"args\":{\"namespace\":\"ns.qux\",\"service\":\"ns.foo#MyService\"}}",
  )
  assert_true(model.get("ns.qux#FooWidget") is Some(_))
  assert_true(model.get("ns.qux#Widget") is Some(_))
  guard model.get("ns.qux#MyService") is Some(shape) &&
    shape.body is @smithy.Service(rename~, ..) else {
    fail("missing service")
  }
  assert_eq(rename.length(), 0)
}

///|
test "rename shapes rewrites metadata and arbitrary trait keys and strings simultaneously" {
  let source =
    #|$version: "2"
    #|metadata references = {"example#A": ["example#B", "example#A"]}
    #|namespace example
    #|@documentation("example#A")
    #|string A
    #|string B
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"example#A\":\"example#B\",\"example#B\":\"example#C\"}}}",
  )
  assert_true(model.get("example#A") is None)
  assert_eq(
    model.get("example#B").unwrap().trait_value("smithy.api#documentation"),
    Some(@smithy.String("example#B")),
  )
  guard model.metadata.get("references") is Some(@smithy.Object(fields)) else {
    fail("missing metadata")
  }
  assert_eq(
    fields.get("example#B"),
    Some(
      @smithy.Array([@smithy.String("example#C"), @smithy.String("example#B")]),
    ),
  )
}

///|
test "change types converts simple types structures unions and collection uniqueness" {
  let source =
    #|$version: "2"
    #|namespace example
    #|string Flag
    #|structure Choice { value: String }
    #|list Values { member: String }
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"changeTypes\",\"args\":{\"shapeTypes\":{\"example#Flag\":\"boolean\",\"example#Choice\":\"union\",\"example#Values\":\"set\"}}}",
  )
  assert_eq(model.get("example#Flag").unwrap().body.keyword(), "boolean")
  assert_eq(model.get("example#Choice").unwrap().body.keyword(), "union")
  assert_true(model.get("example#Choice$value") is Some(_))
  assert_true(
    model.get("example#Values").unwrap().trait_value("smithy.api#uniqueItems")
    is Some(_),
  )
}

///|
test "string enum upgrade synthesizes names and preserves definition traits" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@enum([{value: "foo:bar", documentation: "docs", tags: ["internal"], deprecated: true}])
    #|string Choice
    #|@enum([{value: "1invalid"}])
    #|string Incompatible
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"changeStringEnumsToEnumShapes\",\"args\":{\"synthesizeNames\":true}}",
  )
  assert_eq(model.get("example#Choice").unwrap().body.keyword(), "enum")
  assert_eq(model.get("example#Incompatible").unwrap().body.keyword(), "string")
  let member_ = model.get("example#Choice$foo_bar").unwrap()
  assert_eq(
    member_.trait_value("smithy.api#enumValue"),
    Some(@smithy.String("foo:bar")),
  )
  for name in ["documentation", "deprecated", "internal", "tags"] {
    assert_true(member_.trait_value("smithy.api#" + name) is Some(_))
  }
}

///|
test "change types downgrades enum shapes to legacy string enum traits" {
  let source =
    #|$version: "2"
    #|namespace example
    #|enum Choice {
    #|    @documentation("docs") @internal @deprecated A = "alpha"
    #|}
    #|intEnum Number {
    #|    A = 1
    #|}
  let model = rewrite_projection(
    rewrite_idl(source),
    "{\"name\":\"changeTypes\",\"args\":{\"shapeTypes\":{\"example#Choice\":\"string\",\"example#Number\":\"integer\"}}}",
  )
  assert_true(model.get("example#Choice$A") is None)
  assert_true(model.get("example#Number$A") is None)
  let shape = model.get("example#Choice").unwrap()
  assert_eq(shape.body.keyword(), "string")
  guard shape.trait_value("smithy.api#enum")
    is Some(@smithy.Array([@smithy.Object(definition)])) else {
    fail("missing legacy enum")
  }
  assert_eq(definition.get("name"), Some(@smithy.String("A")))
  assert_eq(definition.get("value"), Some(@smithy.String("alpha")))
  assert_eq(
    definition.get("tags"),
    Some(@smithy.Array([@smithy.String("internal")])),
  )
  assert_eq(definition.get("deprecated"), Some(@smithy.Boolean(true)))
}

///|
test "enum conversion skips unnamed definitions unless requested and supports explicit synthesis" {
  let source =
    #|$version: "2"
    #|namespace example
    #|@enum([{name: "A", value: "alpha"}])
    #|string Named
    #|@enum([{value: "foo/bar"}])
    #|string Unnamed
  let original = rewrite_idl(source)
  let model = rewrite_projection(
    original, "{\"name\":\"changeStringEnumsToEnumShapes\"}",
  )
  assert_eq(model.get("example#Named").unwrap().body.keyword(), "enum")
  assert_eq(model.get("example#Unnamed").unwrap().body.keyword(), "string")
  let model = rewrite_projection(
    original, "{\"name\":\"changeTypes\",\"args\":{\"shapeTypes\":{\"example#Unnamed\":\"enum\"},\"synthesizeEnumNames\":true}}",
  )
  assert_true(model.get("example#Unnamed$foo_bar") is Some(_))
}

///|
test "rewrite transforms reject missing invalid conflicting and unsupported configuration" {
  let model = rewrite_idl(
    "$version: \"2\"\nnamespace example\nstring A\nstring B\nstructure C { value: String }\n",
  )
  for
    transform in [
      "{\"name\":\"renameShapes\"}", "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"example#Missing\":\"example#Other\"}}}",
      "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"example#A\":\"relative\"}}}",
      "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"example#A\":\"example#B\"}}}",
      "{\"name\":\"flattenNamespaces\"}", "{\"name\":\"flattenNamespaces\",\"args\":{\"service\":\"example#A\",\"namespace\":\"new\"}}",
      "{\"name\":\"changeTypes\"}", "{\"name\":\"changeTypes\",\"args\":{\"shapeTypes\":{\"example#C\":\"string\"}}}",
      "{\"name\":\"changeTypes\",\"args\":{\"shapeTypes\":{\"example#A\":\"nonsense\"}}}",
      "{\"name\":\"changeTypes\",\"args\":{\"shapeTypes\":{\"example#A\":\"enum\"}}}",
      "{\"name\":\"changeStringEnumsToEnumShapes\",\"args\":{\"synthesizeNames\":\"yes\"}}",
      "{\"name\":\"convertStringEnumsToEnumShapes\"}", "{\"name\":\"convertEnumShapesToString\"}",
    ] {
    assert_true(
      try rewrite_projection(model, transform) catch {
        @build.InvalidBuildConfig(_) => true
        _ => false
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "renaming rewrites service version strings like the reference JSON visitor" {
  let model = rewrite_idl(
    "$version: \"2\"\nnamespace example\nservice Api { version: \"example#A\" }\nstring A\n",
  )
  let updated = rewrite_projection(
    model, "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"example#A\":\"example#B\"}}}",
  )
  guard updated.get("example#Api") is Some(shape) &&
    shape.body is @smithy.Service(version~, ..) else {
    fail("missing service")
  }
  assert_eq(version, "example#B")
}

///|
test "rename shapes rejects duplicate keys within metadata objects" {
  let source =
    #|$version: "2"
    #|metadata references = {"example#A": "first", "example#D": "second"}
    #|namespace example
    #|string A
    #|string B
  let model = rewrite_idl(source)
  assert_true(
    try
      rewrite_projection(
        model, "{\"name\":\"renameShapes\",\"args\":{\"renamed\":{\"example#A\":\"example#D\"}}}",
      )
    catch {
      @build.InvalidBuildConfig(_) => true
      _ => false
    } noraise {
      _ => false
    },
  )
}

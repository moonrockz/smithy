///|
test "contract traits load from their own namespace and survive IDL and JSON conversion" {
  let model = loaded(
    @smithy.Loader::new().add_idl(
      "contracts.smithy",
      (
        #|$version: "2"
        #|namespace example.contracts
        #|use smithy.contracts#conditions
        #|@conditions({
        #|    StartBeforeEnd: {
        #|        expression: "start < end"
        #|        documentation: "The start time must be **strictly less** than the end time."
        #|    }
        #|})
        #|structure FetchLogsInput {
        #|    @required
        #|    start: Timestamp
        #|    @required
        #|    end: Timestamp
        #|}
        #|@conditions({
        #|    NoKeywords: {
        #|        expression: "!contains(@, 'id') && !contains(@, 'name')"
        #|        documentation: "The name cannot contain reserved keywords."
        #|    }
        #|})
        #|string Name
        #|structure Request { name: Name }
        #|apply Request$name @smithy.contracts#conditions({
        #|    NoPrefix: { expression: "!starts_with(@, '_')", documentation: "No underscore prefix." }
        #|})
      ),
    ),
  )
  for
    (id, name, expression, documentation) in [
      (
        "example.contracts#FetchLogsInput", "StartBeforeEnd", "start < end", "The start time must be **strictly less** than the end time.",
      ),
      (
        "example.contracts#Name", "NoKeywords", "!contains(@, 'id') && !contains(@, 'name')",
        "The name cannot contain reserved keywords.",
      ),
      (
        "example.contracts#Request$name", "NoPrefix", "!starts_with(@, '_')", "No underscore prefix.",
      ),
    ] {
    assert_eq(
      model.get(id).unwrap().trait_value("smithy.contracts#conditions"),
      Some(
        Object(
          Map([
            (
              name,
              Object(
                Map([
                  ("expression", String(expression)),
                  ("documentation", String(documentation)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    )
  }
  let json = @syntax.encode_json_ast(model.to_json_ast())
  let restored = loaded(
    @smithy.Loader::new().add_json("export.json", json.stringify()),
  )
  assert_eq(@syntax.encode_json_ast(restored.to_json_ast()), json)
  let files = model.to_idl()
  assert_eq(files.length(), 1)
  assert_true(!files.contains("smithy.contracts"))
  let loader = @smithy.Loader::new()
  for ns, text in files {
    loader.add_idl(ns + ".smithy", text) |> ignore
  }
  assert_eq(@syntax.encode_json_ast(loaded(loader).to_json_ast()), json)
}

///|
test "conditions are accepted on every data shape kind and on members" {
  for
    declaration in [
      "blob S", "boolean S", "string S", "byte S", "short S", "integer S", "long S",
      "float S", "double S", "bigInteger S", "bigDecimal S", "timestamp S", "document S",
      "list S { member: String }", "map S { key: String, value: String }", "structure S {}",
      "union S { value: String }", "enum S { A }", "intEnum S { A = 1 }",
    ] {
    loaded(
      @smithy.Loader::new().add_idl(
        "valid.smithy",
        "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions(Check1: {expression: \"`true`\", documentation: \"Valid.\"})\n" +
        declaration,
      ),
    )
    |> ignore
  }
  loaded(
    @smithy.Loader::new().add_idl(
      "members.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|use smithy.contracts#conditions
        #|structure S { @conditions value: String }
        #|union U { @conditions value: String }
        #|list L { @conditions member: String }
        #|map M { @conditions key: String, @conditions value: String }
        #|enum E { @conditions A }
        #|intEnum I { @conditions A = 1 }
      ),
    ),
  )
  |> ignore
}

///|
test "conditions reject service operation and resource targets in IDL and JSON" {
  for
    (kind, declaration) in [
      ("service", "service S { version: \"1\" }"),
      ("operation", "operation S {}"),
      ("resource", "resource S {}"),
    ] {
    for
      input in [
        @smithy.ModelInput::Idl(
          name="invalid.smithy",
          text="$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions\n" +
            declaration,
        ),
        @smithy.ModelInput::Json(
          name="invalid.json",
          text="{\"smithy\":\"2\",\"shapes\":{\"example#S\":{\"type\":\"" +
            kind +
            "\",\"traits\":{\"smithy.contracts#conditions\":{}}" +
            (if kind == "service" { ",\"version\":\"1\"" } else { "" }) +
            "}}}",
        ),
      ] {
      let result = @smithy.Loader::new().add(input).assemble()
      assert_true(result.model is None)
      assert_true(
        result.diagnostics
        .iter()
        .any(d => {
          d.code == "SM-MODEL-011" &&
          d.shape.map(id => id.to_string()) == Some("example#S") &&
          d.message.contains("conditions") &&
          d.message.contains(kind)
        }),
      )
    }
  }
}

///|
test "conditions validate map entries required fields and string field types" {
  for
    value in [
      "[]", "true", "\"condition\"", "{\"Check\":null}", "{\"Check\":[]}", "{\"Check\":{}}",
      "{\"Check\":{\"expression\":\"@\"}}", "{\"Check\":{\"documentation\":\"description\"}}",
      "{\"Check\":{\"expression\":null,\"documentation\":\"description\"}}", "{\"Check\":{\"expression\":1,\"documentation\":\"description\"}}",
      "{\"Check\":{\"expression\":\"@\",\"documentation\":false}}", "{\"Check\":{\"expression\":\"@\",\"documentation\":\"description\",\"extra\":true}}",
    ] {
    let result = @smithy.Loader::new()
      .add_json(
        "invalid.json",
        "{\"smithy\":\"2\",\"shapes\":{\"example#S\":{\"type\":\"string\",\"traits\":{\"smithy.contracts#conditions\":" +
        value +
        "}}}}",
      )
      .assemble()
    assert_true(result.model is None)
    assert_true(
      result.diagnostics
      .iter()
      .any(d => {
        d.code == "SM-MODEL-011" &&
        d.source.file == "invalid.json" &&
        d.shape.map(id => id.to_string()) == Some("example#S")
      }),
    )
  }
}

///|
test "empty conditions use the existing map trait shorthand rules" {
  for value in ["null", "{}"] {
    let model = loaded(
      @smithy.Loader::new().add_json(
        "empty.json",
        "{\"smithy\":\"2\",\"shapes\":{\"example#S\":{\"type\":\"string\",\"traits\":{\"smithy.contracts#conditions\":" +
        value +
        "}}}}",
      ),
    )
    assert_eq(
      model.get("example#S").unwrap().trait_value("smithy.contracts#conditions"),
      Some(Object(Map([]))),
    )
  }
  for value in ["@conditions", "@conditions()", "@conditions({})"] {
    loaded(
      @smithy.Loader::new().add_idl(
        "empty.smithy",
        "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n" +
        value +
        "\nstring S",
      ),
    )
    |> ignore
  }
}

///|
test "condition names follow the upstream ASCII pattern" {
  for
    name in [
      "", "lowercase", "1Name", "_Name", "Has_space", "Has-dash", "ÄName", "Nameé",
      "Name\\n",
    ] {
    let result = @smithy.Loader::new()
      .add_idl(
        "names.smithy",
        "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({\"" +
        name +
        "\": {expression: \"@\", documentation: \"description\"}})\nstring S",
      )
      .assemble()
    assert_true(result.model is None)
    assert_true(
      result.diagnostics
      .iter()
      .any(d => d.code == "SM-MODEL-011" && d.message.contains("condition name")),
    )
  }
  loaded(
    @smithy.Loader::new().add_idl(
      "names.smithy", "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n@conditions({A: {expression: \"`true`\", documentation: \"\"}, ABC123def: {expression: \"`true`\", documentation: \"\"}})\nstring S",
    ),
  )
  |> ignore
}

///|
test "contract names require imports and local conditions traits remain local" {
  let result = @smithy.Loader::new()
    .add_idl(
      "unimported.smithy", "$version: \"2\"\nnamespace example\n@conditions\nstring S",
    )
    .assemble()
  assert_true(
    result.diagnostics
    .iter()
    .any(d => {
      d.code == "SM-MODEL-004" && d.message.contains("example#conditions")
    }),
  )
  let model = loaded(
    @smithy.Loader::new().add_idl(
      "local.smithy", "$version: \"2\"\nnamespace example\n@trait\nstructure conditions {}\n@conditions\noperation S {}",
    ),
  )
  assert_true(
    model.get("example#S").unwrap().trait_value("example#conditions") is Some(_),
  )
}

///|
test "conditions inherit through mixins and preserve expressions without evaluation" {
  let model = loaded(
    @smithy.Loader::new().add_idl(
      "mixin.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|use smithy.contracts#conditions
        #|@mixin
        #|@conditions(Positive: {expression: "value > `0`", documentation: "Positive value."})
        #|structure Base {
        #|    @conditions(Positive: {expression: "@ > `0`", documentation: "Positive value."})
        #|    value: Integer
        #|}
        #|structure S with [Base] {}
        #|@conditions(Never: {expression: "`false`", documentation: "Preserved without evaluation."})
        #|integer N
        #|structure WithDefault { n: N = 1 }
      ),
    ),
  )
  for
    (base, inherited) in [
      ("example#Base", "example#S"),
      ("example#Base$value", "example#S$value"),
    ] {
    assert_eq(
      model.get(base).unwrap().trait_value("smithy.contracts#conditions"),
      model.get(inherited).unwrap().trait_value("smithy.contracts#conditions"),
    )
  }
  let restored = loaded(
    @smithy.Loader::new().add_ast("export.json", model.to_json_ast()),
  )
  assert_eq(
    @syntax.encode_json_ast(restored.to_json_ast()),
    @syntax.encode_json_ast(model.to_json_ast()),
  )
}

///|
test "built-in contract definitions cannot be changed or impersonated" {
  let result = @smithy.Loader::new()
    .add_idl("<contracts>", "$version: \"2\"\nnamespace example\nstring S")
    .assemble()
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-001"))
  for
    text in [
      "namespace smithy.contracts\nstring conditions", "namespace example\napply smithy.contracts#conditions @documentation(\"changed\")",
      "namespace example\napply smithy.contracts#Condition$expression @default(\"changed\")",
    ] {
    let result = @smithy.Loader::new()
      .add_idl("override.smithy", "$version: \"2\"\n" + text)
      .assemble()
    assert_true(result.model is None)
    assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-014"))
  }
  let model = loaded(@smithy.Loader::new())
  assert_true(model.get("smithy.contracts#conditions") is Some(_))
  assert_true(model.get("smithy.contracts#Condition") is Some(_))
  assert_eq(model.to_json_ast().shapes, Some(Map([])))
  let document = model.to_json_ast(include_prelude=true)
  assert_true(document.shapes.unwrap().contains("smithy.contracts#conditions"))
  loaded(@smithy.Loader::new().add_ast("builtins.json", document)) |> ignore
}

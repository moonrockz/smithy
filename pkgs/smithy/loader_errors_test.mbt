///|
test "assembly diagnostics distinguish conflicts, cycles, and invalid targets" {
  for
    (body, code) in [
      (
        "@mixin\nstructure A with [B] {}\n@mixin\nstructure B with [A] {}", "SM-MODEL-009",
      ),
      (
        "resource A { resources: [B] }\nresource B { resources: [A] }", "SM-MODEL-009",
      ),
      ("structure A {}\nstructure B with [A] {}", "SM-MODEL-008"),
      ("@mixin\nstring A\nstructure B with [A] {}", "SM-MODEL-008"),
      ("@length(min: 1)\n@length(min: 2)\nstring A", "SM-MODEL-007"),
      ("string A\n@A\nstring B", "SM-MODEL-011"),
      ("@documentation(123)\nstring A", "SM-MODEL-011"),
      ("string A\noperation B { input: A }", "SM-MODEL-005"),
      ("map A { key: String }", "SM-MODEL-010"),
      ("structure A { a: String\n A: String }", "SM-MODEL-010"),
      ("apply Missing$name @documentation(\"missing\")", "SM-MODEL-013"),
      (
        "structure A {}\napply A$missing @documentation(\"missing\")", "SM-MODEL-013",
      ),
    ] {
    let result = @smithy.Loader::new()
      .add_idl(
        "invalid.smithy",
        "$version: \"2\"\nnamespace example.test\n" + body + "\n",
      )
      .assemble()
    assert_eq(result.model, None)
    if !result.diagnostics.iter().any(d => d.code == code) {
      fail(
        "expected " +
        code +
        " for " +
        body +
        ": " +
        result.diagnostics.map(d => d.code + " " + d.message).join("\n"),
      )
    }
    assert_true(
      result.diagnostics.iter().all(d => d.source.file == "invalid.smithy"),
    )
  }
}

///|
test "duplicate documents merge traits and reject conflicting structure" {
  let document = "$version: \"2\"\nnamespace example.test\nstructure S { name: String }\n"
  let model = loaded(
    @smithy.Loader::new()
    .add_idl("a.smithy", document)
    .add_idl(
      "b.smithy",
      document.replace_all(
        old="structure S",
        new="@tags([\"tag\"])\nstructure S",
      ),
    ),
  )
  assert_true(
    model.get("example.test#S").unwrap().trait_value("smithy.api#tags")
    is Some(_),
  )
  let result = @smithy.Loader::new()
    .add_idl("a.smithy", document)
    .add_idl(
      "b.smithy",
      document.replace_all(old="name: String", new="name: Integer"),
    )
    .assemble()
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-003"))
  assert_eq(result.model, None)
}

///|
test "metadata conflicts use exact numbers rather than Double equality" {
  let a = "{\"smithy\":\"2\",\"metadata\":{\"number\":9007199254740992}}"
  let b = "{\"smithy\":\"2\",\"metadata\":{\"number\":9007199254740993}}"
  let result = @smithy.Loader::new()
    .add_json("a.json", a)
    .add_json("b.json", b)
    .assemble()
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-006"))
  loaded(
    @smithy.Loader::new()
    .add_json("a.json", a)
    .add_json(
      "b.json",
      a.replace_all(old="9007199254740992", new="9007199254740992.0"),
    ),
  )
  |> ignore
}

///|
test "malformed JSON has a field path and does not mutate caller ASTs" {
  let result = @smithy.Loader::new()
    .add_json("bad.json", "{\"smithy\":\"2\",\"metadata\":null}")
    .assemble()
  assert_eq(result.model, None)
  assert_true(
    result.diagnostics
    .iter()
    .any(d => d.source.path == "/metadata" && d.source.file == "bad.json"),
  )
  let ast = @syntax.parse_json_ast(
    "{\"smithy\":\"2\",\"shapes\":{\"example.test#S\":{\"type\":\"structure\"}}}",
  )
  let before = @syntax.encode_json_ast(ast).stringify()
  let loader = @smithy.Loader::new().add_ast("s.json", ast)
  loaded(loader) |> ignore
  loaded(loader) |> ignore
  assert_eq(@syntax.encode_json_ast(ast).stringify(), before)
}

///|
test "the prelude is protected and private prelude names are not implicitly imported" {
  let result = @smithy.Loader::new()
    .add_idl(
      "override.smithy", "$version: \"2\"\nnamespace smithy.api\ninteger String\n",
    )
    .assemble()
  assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-014"))
  let result = @smithy.Loader::new()
    .add_idl(
      "private.smithy", "$version: \"2\"\nnamespace example.test\nstructure S { value: TraitDiffRules }\n",
    )
    .assemble()
  assert_true(
    result.diagnostics
    .iter()
    .any(d => {
      d.code == "SM-MODEL-004" &&
      d.message.contains("example.test#TraitDiffRules")
    }),
  )
}

///|
test "law: arbitrary IDL and JSON inputs never panic during assembly" {
  @quickcheck.check(
    (text : String) => {
      let idl = @smithy.Loader::new().add_idl("random.smithy", text).assemble()
      let json = @smithy.Loader::new().add_json("random.json", text).assemble()
      (idl.model is None) == idl.has_errors() &&
      (json.model is None) == json.has_errors()
    },
    count=100,
    max_size=30,
    seed=6032,
  )
}

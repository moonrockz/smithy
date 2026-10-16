///|
fn assembled(loader : @smithy.Loader, path : String) -> @smithy.Model raise {
  let result = loader.assemble()
  guard result.model is Some(model) else {
    fail(
      path +
      ": " +
      result.diagnostics.map(d => d.code + " " + d.message).join("\n"),
    )
  }
  model
}

///|
test "reference IDL and JSON AST representations assemble to the same model" {
  let idls : Map[String, String] = Map([])
  for case in @tck.cases() {
    if case.kind == Valid {
      idls[case.path] = case.text
    }
  }
  let mut shared = ""
  for case in @tck.json_cases() {
    if case.path == "valid/__shared.json" {
      shared = case.text
    }
  }
  let failures : Array[String] = []
  let mut compared = 0
  for case in @tck.json_cases() {
    if !case.path.has_prefix("valid/") {
      continue
    }
    if case.path == "valid/__shared.json" {
      continue
    }
    let idl_path = case.path.replace_all(old=".json", new=".smithy")
    guard idls.get(idl_path) is Some(text) else {
      fail("missing IDL counterpart for " + case.path)
    }
    try {
      let idl = @smithy.Loader::new().add_idl(idl_path, text)
      let json = @smithy.Loader::new().add_json(case.path, case.text)
      if idl_path != "valid/__shared.smithy" {
        idl.add_json("valid/__shared.json", shared) |> ignore
        json.add_json("valid/__shared.json", shared) |> ignore
      }
      let a = assembled(idl, idl_path).to_json_ast()
      let b = assembled(json, case.path).to_json_ast()
      if @syntax.encode_json_ast(a) != @syntax.encode_json_ast(b) {
        failures.push(
          case.path +
          ": models differ\nIDL: " +
          @syntax.encode_json_ast(a).stringify() +
          "\nJSON: " +
          @syntax.encode_json_ast(b).stringify(),
        )
      }
      compared += 1
    } catch {
      error => failures.push(error.to_string())
    }
  }
  assert_eq(
    compared,
    @tck.json_cases()
    .filter(c => c.path.has_prefix("valid/") && c.path != "valid/__shared.json")
    .length(),
  )
  if !failures.is_empty() {
    fail(failures.join("\n\n"))
  }
}

///|
test "unflattened reference JSON mixins assemble and export reloadable models" {
  for case in @tck.json_cases() {
    if !case.path.has_prefix("mixins/") {
      continue
    }
    let model = assembled(
      @smithy.Loader::new().add_json(case.path, case.text),
      case.path,
    )
    assembled(
      @smithy.Loader::new().add_ast("flattened.json", model.to_json_ast()),
      case.path,
    )
    |> ignore
  }
}

///|
test "the semantic loader rejects every invalid reference IDL case" {
  let failures = []
  for case in @tck.cases() {
    guard case.kind is Invalid(..) else { continue }
    let result = @smithy.Loader::new().add_idl(case.path, case.text).assemble()
    if !result.has_errors() || result.model is Some(_) {
      failures.push(case.path)
    }
  }
  if !failures.is_empty() {
    fail("accepted invalid models: " + failures.join(", "))
  }
}

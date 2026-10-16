///|
test "reference flattened IDL models match inherited members and traits" {
  let idls : Map[String, String] = Map([])
  for case in @tck.cases() {
    if case.kind == Valid {
      idls[case.path] = case.text
    }
  }
  let mut compared = 0
  for path, text in idls {
    if !path.has_suffix(".flattened.smithy") {
      continue
    }
    let base = path.replace_all(old=".flattened.smithy", new=".smithy")
    guard idls.get(base) is Some(original) else {
      fail("missing mixin source " + base)
    }
    let model = assembled(@smithy.Loader::new().add_idl(base, original), base).to_json_ast()
    let expected = assembled(@smithy.Loader::new().add_idl(path, text), path).to_json_ast()
    for id, shape in expected.shapes.unwrap() {
      if model.shapes.unwrap().get(id) != Some(shape) {
        fail("inherited shape differs: " + path + " " + id)
      }
    }
    compared += 1
  }
  assert_true(compared > 0)
}

///|
fn contract_case(
  expression : String,
  declaration : String,
  extra~ : String = "",
) -> @smithy.LoadResult {
  @smithy.Loader::new()
  .add_idl(
    "analysis.smithy",
    "$version: \"2\"\nnamespace example\nuse smithy.contracts#conditions\n" +
    extra +
    "\n@conditions(Check: {expression: " +
    Json::string(expression).stringify() +
    ", documentation: \"A contract.\"})\n" +
    declaration,
  )
  .assemble()
}

///|
fn contract_ok(result : @smithy.LoadResult) -> Unit raise {
  if result.model is None {
    fail(result.diagnostics.map(d => d.code + ": " + d.message).join("\n"))
  }
}

///|
test "conditions preserve null aggregates and constructed object truthiness" {
  for
    (expression, boolean_result) in [
      ("avg(`[]`) > `0`", false),
      ("avg(`[]`) == `null`", true),
      ("avg(`[1, 2]`) > `0`", true),
      ("{x: @} && `true`", true),
      ("{x: @} || `false`", false),
      ("{x: `null`} && `false`", true),
      ("merge({x: @}, `{}`) && `true`", true),
      ("`null` | ([@] || `true`)", true),
      ("`null` | ({x: @} || `true`)", true),
    ] {
    let evaluated = @jmespath.search(expression, Json::string("value"))
    assert_eq(evaluated is (True | False), boolean_result)
    let result = contract_case(expression, "string S")
    if boolean_result {
      contract_ok(result)
    } else {
      assert_true(result.model is None)
      assert_true(result.diagnostics.iter().any(d => d.code == "SM-MODEL-017"))
    }
  }
  let empty_avg = contract_case("avg(`[]`) > `0`", "string S")
  assert_true(
    empty_avg.diagnostics
    .iter()
    .any(d => d.code == "SM-MODEL-016" && d.severity == Warning),
  )
}

///|
test "conditions use the Smithy JMESPath data model for all shape kinds" {
  for
    (declaration, expression) in [
      ("blob S", "starts_with(@, 'a')"),
      ("boolean S", "@"),
      ("string S", "ends_with(@, 'a')"),
      ("enum S { A }", "contains(@, 'A')"),
      ("intEnum S { A = 1 }", "@ >= `0`"),
      ("timestamp S", "@ > `0`"),
      ("byte S", "@ > `0`"),
      ("short S", "@ > `0`"),
      ("integer S", "@ > `0`"),
      ("long S", "@ > `0`"),
      ("float S", "@ > `0`"),
      ("double S", "@ > `0`"),
      ("bigInteger S", "@ > `0`"),
      ("bigDecimal S", "@ > `0`"),
      ("document S", "foo.bar == `true`"),
      ("list S { member: Boolean }", "[0] || `false`"),
      ("map S { key: String, value: Boolean }", "arbitraryKey || `false`"),
      ("structure S { flag: Boolean }", "flag"),
      ("union S { flag: Boolean }", "flag"),
    ] {
    contract_ok(contract_case(expression, declaration))
  }
}

///|
test "conditions analyze all standard functions and typed expression references" {
  let extra =
    #|list Numbers { member: Integer }
    #|list Words { member: String }
    #|list Items { member: Item }
    #|list Matrix { member: Items }
    #|map Data { key: String, value: Integer }
    #|structure Item { name: String, count: Integer, active: Boolean }
  let declaration = "structure S { word: String, n: Integer, nums: Numbers, words: Words, items: Items, matrix: Matrix, data: Data, active: Boolean, doc: Document }"
  for
    expression in [
      "abs(n) > `0`", "avg(nums) >= `0`", "ceil(n) > `0`", "contains(words, word)",
      "ends_with(word, 'a')", "floor(n) > `0`", "join(',', words) == word", "length(keys(data)) > `0`",
      "length(word) > `0`", "sum(map(&count, items)) >= `0`", "max(nums) > `0`",
      "max_by(items, &count).active", "merge(data, `{}`).anyKey > `0`", "min(nums) > `0`",
      "min_by(items, &name).active", "not_null(`null`, active)", "reverse(word) == word",
      "sort(words)[0] == word", "sort_by(items, &name)[0].active", "starts_with(word, 'a')",
      "sum(nums) > `0`", "to_array(n)[0] > `0`", "to_string(n) == word", "to_number(word) > `0`",
      "type(doc) == 'object'", "sum(values(data)) > `0`", "length(items[?active].name) > `0`",
      "length(matrix[].name) > `0`", "length(items[:2].name) > `0`", "items | [0].active",
      "map(&{x: count}, items)[0].x > `0`", "{x: active}.x", "[active, word][0]",
      "reverse([word, active])[0]", "[word, active][-1]", "length(data.*) > `0`",
      "length({a: word, b: n}.*) > `0`", "contains(map(&length(name), items), `1`)",
      "length(map(&map(&count, @), matrix)) > `0`",
    ] {
    contract_ok(contract_case(expression, declaration, extra~))
  }
}

///|
test "conditions reject unknown members wrong operations and function arguments" {
  let extra = "list Items { member: Item }\nstructure Item { name: String, count: Integer, active: Boolean }"
  let declaration = "structure S { word: String, n: Integer, items: Items, doc: Document }"
  for
    (expression, detail) in [
      ("missing == `null`", "missing"),
      ("word.missing == `null`", "object"),
      ("items[0].missing == `null`", "missing"),
      ("length(items[*].missing) == `0`", "missing"),
      ("length(items[?missing].name) == `0`", "missing"),
      ("length(items[:2].missing) == `0`", "missing"),
      ("length(n[]) == `0`", "array"),
      ("length(word.*) == `0`", "object"),
      ("length(items[::0]) == `0`", "non-zero"),
      ("unknown(n) == `0`", "resolve JMESPath function unknown"),
      ("length() == `0`", "arguments"),
      ("length(word, n) == `0`", "arguments"),
      ("merge() == `{}`", "at least 1"),
      ("not_null() == `null`", "at least 1"),
      ("length(n) == `0`", "argument 1"),
      ("starts_with(n, word)", "argument 1"),
      ("ends_with(word, n)", "argument 2"),
      ("contains(word, n)", "string search value"),
      ("sum(items) == `0`", "array of numbers"),
      ("join(',', items) == word", "array of strings"),
      ("sort(`[1, \"s\"]`) == `[]`", "uniformly"),
      ("map(&missing, items) == `[]`", "missing"),
      ("sort_by(items, &missing) == `[]`", "missing"),
      ("sort_by(items, &active) == `[]`", "number or string"),
      ("max_by(items, &active).active", "number or string"),
      ("min_by(items, &active).active", "number or string"),
      ("map(word, items) == `[]`", "expression reference"),
      ("map(doc, items) == `[]`", "expression reference"),
      ("length(&word) == `0`", "expression reference"),
      ("`true` || missing", "missing"),
      ("`false` && missing", "missing"),
    ] {
    let result = contract_case(expression, declaration, extra~)
    assert_true(result.model is None)
    if !result.diagnostics
      .iter()
      .any(d => d.code == "SM-MODEL-016" && d.message.contains(detail)) {
      fail(
        expression +
        ": " +
        result.diagnostics.map(d => d.code + ": " + d.message).join("\n"),
      )
    }
    assert_true(
      result.diagnostics.iter().all(d => d.source.file == "analysis.smithy"),
    )
  }
}

///|
test "conditions require a statically boolean result without evaluating truth" {
  for
    expression in [
      "'yes'", "`0`", "`null`", "`[]`", "`{}`", "word", "n", "items", "doc", "doc.unknown",
      "reverse([`true`, 'nonboolean'])[0]", "'a' < 'b'",
    ] {
    let result = contract_case(
      expression,
      "structure S { word: String, n: Integer, items: Items, doc: Document }",
      extra="list Items {member: String}",
    )
    assert_true(result.model is None)
    assert_true(
      result.diagnostics
      .iter()
      .any(d => d.code == "SM-MODEL-017" && d.message.contains("boolean")),
    )
  }
  for
    expression in [
      "`false`", "`1` > `2`", "!`true`", "ends_with('a', 'b')", "`null` || `false`",
      "`true` || 'unused'", "`false` && 'unused'", "`[]` || `true`", "'nonempty' && `true`",
      "not_null(`false`, 'unused')",
    ] {
    contract_ok(contract_case(expression, "string S"))
  }
  let warned = contract_case("!('a' < 'b')", "string S")
  contract_ok(warned)
  assert_true(
    warned.diagnostics
    .iter()
    .any(d => d.code == "SM-MODEL-016" && d.severity == Warning),
  )
}

///|
test "condition syntax diagnostics keep model sources and expression relative locations" {
  let result = contract_case("'😀' ==\n)", "string S")
  assert_true(result.model is None)
  let errors = result.diagnostics.filter(d => d.code == "SM-MODEL-015")
  assert_eq(errors.length(), 1)
  let d = errors[0]
  assert_eq(d.shape.map(id => id.to_string()), Some("example#S"))
  assert_eq(d.source.file, "analysis.smithy")
  assert_eq(
    d.source.path,
    "/traits/smithy.contracts#conditions/Check/expression",
  )
  assert_true(d.source.span is Some(_))
  assert_true(d.message.contains("Check"))
  assert_true(d.message.contains("expression 2:1"))
  assert_true(d.message.contains("UTF-16 offsets 8..9"))
  assert_false(result.diagnostics.iter().any(d => d.code == "SM-MODEL-017"))
}

///|
test "conditions analyze recursive shapes lazy references and very long chains" {
  let declaration = "structure S { flag: Boolean, next: S, siblings: Siblings }"
  let extra = "list Siblings { member: S }"
  for
    expression in [
      "next.next.flag",
      "siblings[0].next.flag",
      "next" + ".next".repeat(1000) + ".flag",
      "length(map(&next.flag, siblings)) > `0`",
    ] {
    contract_ok(contract_case(expression, declaration, extra~))
  }
  let broken = contract_case(
    "next" + ".next".repeat(1000) + ".missing == `null`",
    declaration,
    extra~,
  )
  assert_true(
    broken.diagnostics
    .iter()
    .any(d => d.code == "SM-MODEL-016" && d.message.contains("missing")),
  )
}

///|
test "JSON contract analysis uses member names and reports condition JSON pointers" {
  let result = @smithy.Loader::new()
    .add_json(
      "analysis.json",
      (
        #|{"smithy":"2","shapes":{"example#S":{"type":"structure","members":{"name":{"target":"smithy.api#String","traits":{"smithy.api#jsonName":"wireName"}}},"traits":{"smithy.contracts#conditions":{"Check":{"expression":"length(name) > `0`","documentation":"Names use Smithy spelling."}}}}}}
      ),
    )
    .assemble()
  contract_ok(result)
  let json = @syntax.encode_json_ast(result.model.unwrap().to_json_ast()).stringify()
  let broken = @smithy.Loader::new()
    .add_json(
      "analysis.json",
      json.replace_all(old="length(name)", new="length(wireName)"),
    )
    .assemble()
  assert_true(broken.model is None)
  let errors = broken.diagnostics.filter(d => d.code == "SM-MODEL-016")
  assert_true(errors.iter().any(d => d.message.contains("wireName")))
  assert_true(
    errors
    .iter()
    .all(d => {
      d.source.path ==
      "/shapes/example#S/traits/smithy.contracts#conditions/Check/expression"
    }),
  )
}

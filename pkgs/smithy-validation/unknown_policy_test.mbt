///|
fn policy_model(source : String) -> @smithy.Model raise {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "policy.smithy", "$version: \"2\"\nnamespace smithy.rpc\n@trait(selector: \":is(service, structure)\") enum unknownMembers { REJECT = \"reject\"\n IGNORE = \"ignore\" }\n@trait(selector: \"structure > member\") structure criticalPaths { @required separator: String }",
    )
    .add_idl(
      "value.smithy",
      "$version: \"2\"\nnamespace example\nuse smithy.rpc#unknownMembers\nuse smithy.rpc#criticalPaths\n" +
      source,
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
test "structure unknown member policy overrides the config" {
  let m = policy_model(
    "@unknownMembers(\"ignore\") structure Value { nested: Strict }\n@unknownMembers(\"reject\") structure Strict { known: String }",
  )
  let v = @validation.PreparedValidator::prepare(
    m,
    target("Value"),
    config=@validation.Config::new(unknown_members=Ignore),
  )
  assert_true(v.validate_json(@json.parse("{\"extra\":1}")).is_valid())
  let result = v.validate_json(
    @json.parse("{\"extra\":1,\"nested\":{\"extra\":2}}"),
  )
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].code.to_string(), "UnknownMember")
  assert_eq(result.findings[0].path.pointer(), "/nested/extra")
}

///|
test "critical paths name declared nested members even when absent" {
  let m = policy_model(
    "@unknownMembers(\"ignore\") structure Value { nested: Nested, @criticalPaths(separator: \".\") critical: Paths }\nstructure Nested { value: String }\nlist Paths { member: String }",
  )
  let v = @validation.PreparedValidator::prepare(m, target("Value"))
  let result = v.validate_json(
    @json.parse(
      "{\"extra\":1,\"critical\":[\"nested.value\",\"nested.missing\",\"extra\",\"\",\"nested..value\"]}",
    ),
  )
  assert_eq(result.findings.map(f => f.code.to_string()), [
    "UnknownCriticalPath", "UnknownCriticalPath", "UnknownCriticalPath", "UnknownCriticalPath",
  ])
  assert_eq(result.findings.map(f => f.path.pointer()), [
    "/critical/1", "/critical/2", "/critical/3", "/critical/4",
  ])
}

///|
test "critical path preparation rejects invalid targets and separators" {
  for
    source in [
      "structure Value { @criticalPaths(separator: \".\") critical: String }", "structure Value { @criticalPaths(separator: \".\") critical: Paths }\nlist Paths { member: Integer }",
      "structure Value { @criticalPaths(separator: \"\") critical: Paths }\nlist Paths { member: String }",
      "union Value { @criticalPaths(separator: \".\") critical: Paths }\nlist Paths { member: String }",
    ] {
    let mut rejected = false
    ignore(
      @validation.PreparedValidator::prepare(
        policy_model(source),
        target("Value"),
      ),
    ) catch {
      @validation.InvalidModel(_, message) => {
        assert_true(message.contains("criticalPaths"))
        rejected = true
      }
      _ => fail("I expected an InvalidModel error for criticalPaths.")
    }
    assert_true(rejected)
  }
}

///|
test "critical paths use selected member names and direct member targets" {
  let m = policy_model(
    "structure Value { @jsonName(\"wire\") original: Nested, @criticalPaths(separator: \"/\") critical: Paths }\nstructure Nested { leaf: String }\nlist Paths { member: String }",
  )
  let v = @validation.PreparedValidator::prepare(
    m,
    target("Value$critical"),
    config=@validation.Config::new(member_names=JsonName),
  )
  assert_true(v.validate_json(@json.parse("[\"wire/leaf\"]")).is_valid())
  let result = v.validate_json(
    @json.parse("[\"original/leaf\",\"wire/leaf/missing\"]"),
  )
  assert_eq(result.findings.map(f => f.path.pointer()), ["/0", "/1"])
}

///|
test "critical path checks obey work limits on recursive models" {
  let m = policy_model(
    "structure Value { child: Value, @criticalPaths(separator: \".\") critical: Paths }\nlist Paths { member: String }",
  )
  let v = @validation.PreparedValidator::prepare(
    m,
    target("Value"),
    config=@validation.Config::new(limits=@validation.Limits::new(work=50)),
  )
  let result = v.validate_json(
    Json::object({
      "critical": Json::array([Json::string("child.".repeat(1000) + "critical")]),
    }),
  )
  assert_false(result.complete)
  assert_eq(result.findings.last().unwrap().code.to_string(), "LimitExceeded")
}

///|
test "critical paths stop at containers and reject empty path segments" {
  let m = policy_model(
    "structure Value { list: Paths, map: Values, choice: Choice, nested: Nested, @criticalPaths(separator: \".\") critical: Paths }\nstructure Nested { leaf: String }\nlist Paths { member: String }\nmap Values { key: String, value: Nested }\nunion Choice { item: Nested }",
  )
  let v = @validation.PreparedValidator::prepare(m, target("Value"))
  let result = v.validate_json(
    @json.parse(
      "{\"critical\":[\"list\",\"map\",\"choice\",\"list.member\",\"map.key\",\"choice.item\",\"nested.\",\".nested\"]}",
    ),
  )
  assert_eq(result.findings.map(f => f.path.pointer()), [
    "/critical/3", "/critical/4", "/critical/5", "/critical/6", "/critical/7",
  ])
}

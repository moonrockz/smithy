///|
let shapes_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|use smithy.serialization#untagged
  #|
  #|@jsonProfiles([
  #|  {id: "external"}
  #|  {id: "internal", defaults: {union: {style: "internal", tag: "kind"}}}
  #|  {id: "adjacent", defaults: {union: {style: "adjacent", tag: "kind", content: "value"}}}
  #|  {id: "mixed", defaults: {union: {style: "external"}}}
  #|])
  #|structure Doc {
  #|  @required
  #|  op: Op
  #|  id: Id
  #|}
  #|
  #|@jsonEncoding(profiles: {mixed: {union: {style: "adjacent", tag: "t", content: "c"}}})
  #|union Op {
  #|  Add: Pair
  #|  @jsonName("neg")
  #|  Neg: Single
  #|  Stop: Unit
  #|}
  #|
  #|structure Pair {
  #|  @required
  #|  left: Integer
  #|  @required
  #|  right: Integer
  #|}
  #|
  #|structure Single {
  #|  @required
  #|  @jsonName("v")
  #|  value: Integer
  #|}
  #|
  #|/// Profile defaults take precedence over base traits, so the internal and adjacent profiles
  #|/// select untagged again for this union.
  #|@untagged
  #|@jsonEncoding(profiles: {
  #|  internal: {union: {style: "untagged"}}
  #|  adjacent: {union: {style: "untagged"}}
  #|})
  #|union Id {
  #|  number: BigInteger
  #|  text: String
  #|}

///|
fn prepare_doc(name : String) -> @codec.PreparedCodec raise {
  @codec.PreparedCodec::prepare(
    load(shapes_model),
    id("example#Doc"),
    profile=Some(profile(name)),
  )
}

///|
test "each object representation round-trips" {
  let cases = [
    ("external", "{\"op\":{\"Add\":{\"left\":1,\"right\":2}}}"),
    ("internal", "{\"op\":{\"kind\":\"Add\",\"left\":1,\"right\":2}}"),
    (
      "adjacent", "{\"op\":{\"kind\":\"Add\",\"value\":{\"left\":1,\"right\":2}}}",
    ),
  ]
  let values = []
  for entry in cases {
    let codec = prepare_doc(entry.0)
    let value = codec.decode(entry.1)
    assert_eq(codec.encode(value), entry.1)
    assert_eq(value.logical().get("op").unwrap().selected().unwrap().0, "Add")
    values.push(value)
  }
  assert_true(values[0] == values[1])
  assert_true(values[1] == values[2])
}

///|
test "effective jsonName applies to tags and payload fields" {
  let internal = prepare_doc("internal")
  let value = internal.decode("{\"op\":{\"kind\":\"neg\",\"v\":4}}")
  assert_eq(
    prepare_doc("external").encode(value),
    "{\"op\":{\"neg\":{\"v\":4}}}",
  )
  assert_eq(
    prepare_doc("adjacent").encode(value),
    "{\"op\":{\"kind\":\"neg\",\"value\":{\"v\":4}}}",
  )
}

///|
test "unit members in each layout" {
  assert_eq(
    prepare_doc("external").canonicalize("{\"op\":{\"Stop\":{}}}"),
    "{\"op\":{\"Stop\":{}}}",
  )
  assert_eq(
    prepare_doc("internal").canonicalize("{\"op\":{\"kind\":\"Stop\"}}"),
    "{\"op\":{\"kind\":\"Stop\"}}",
  )
  assert_eq(
    prepare_doc("adjacent").canonicalize("{\"op\":{\"kind\":\"Stop\"}}"),
    "{\"op\":{\"kind\":\"Stop\"}}",
  )
}

///|
test "a profile default and a shape-specific override" {
  let mixed = prepare_doc("mixed")
  assert_eq(
    mixed.canonicalize(
      "{\"op\":{\"t\":\"Add\",\"c\":{\"left\":1,\"right\":2}}}",
    ),
    "{\"op\":{\"t\":\"Add\",\"c\":{\"left\":1,\"right\":2}}}",
  )
  assert_false(
    mixed.check("{\"op\":{\"Add\":{\"left\":1,\"right\":2}}}").is_valid(),
  )
}

///|
test "adjacent and internal failures" {
  let adjacent = prepare_doc("adjacent")
  let missing = adjacent.check("{\"op\":{\"kind\":\"Add\"}}")
  assert_eq(missing.findings[0].code, MissingMember)
  assert_eq(missing.findings[0].path.pointer(), "/op/value")
  let extra = adjacent.check(
    "{\"op\":{\"kind\":\"Add\",\"value\":{\"left\":1,\"right\":2},\"x\":1}}",
  )
  assert_eq(extra.findings[0].code, UnknownMember)
  assert_eq(extra.findings[0].path.pointer(), "/op/x")
  let internal = prepare_doc("internal")
  let tag = internal.check("{\"op\":{\"kind\":\"Mul\",\"left\":1,\"right\":2}}")
  assert_eq(tag.findings[0].code, UnknownTag)
  assert_eq(tag.findings[0].path.pointer(), "/op/kind")
  let nested = internal.check(
    "{\"op\":{\"kind\":\"Add\",\"left\":1,\"right\":\"2\"}}",
  )
  assert_eq(nested.findings[0].code, Constraint(TypeMismatch))
  assert_eq(nested.findings[0].path.pointer(), "/op/right")
}

///|
test "untagged scalar union selects by JSON kind" {
  let codec = prepare_doc("external")
  let number = codec.decode(
    "{\"op\":{\"Stop\":{}},\"id\":12345678901234567890}",
  )
  assert_eq(number.logical().get("id").unwrap().selected().unwrap().0, "number")
  let text = codec.decode("{\"op\":{\"Stop\":{}},\"id\":\"abc\"}")
  assert_eq(text.logical().get("id").unwrap().selected().unwrap().0, "text")
  let boolean = codec.check("{\"op\":{\"Stop\":{}},\"id\":true}")
  assert_eq(boolean.findings[0].code, KindMismatch)
  assert_eq(boolean.findings[0].path.pointer(), "/id")
  assert_false(codec.check("{\"op\":{\"Stop\":{}},\"id\":{}}").is_valid())
  // The selected member keeps its Smithy constraints.
  let range = codec.check("{\"op\":{\"Stop\":{}},\"id\":1.5}")
  assert_eq(range.findings[0].code, Constraint(NumericBounds))
  assert_eq(
    codec.encode(number),
    "{\"op\":{\"Stop\":{}},\"id\":12345678901234567890}",
  )
  assert_eq(codec.encode(text), "{\"op\":{\"Stop\":{}},\"id\":\"abc\"}")
}

///|
fn refusal(model : String, root : String, profile_name : String?) -> String {
  let result = try {
    let p = match profile_name {
      Some(name) => Some(profile(name))
      None => None
    }
    ignore(@codec.PreparedCodec::prepare(load(model), id(root), profile=p))
    "prepared"
  } catch {
    @contract.UnknownProfile(_) as e => "UnknownProfile: " + e.message()
    @contract.InvalidDeclaration(_, _) as e =>
      "InvalidDeclaration: " + e.message()
    @contract.UnsupportedDeclaration(_, _) as e =>
      "UnsupportedDeclaration: " + e.message()
    @contract.ConflictingDeclaration(_, _) as e =>
      "ConflictingDeclaration: " + e.message()
    @contract.MissingAdapter(_, _) as e => "MissingAdapter: " + e.message()
    @contract.InvalidTarget(_, _) as e => "InvalidTarget: " + e.message()
    e => "other: " + e.to_string()
  }
  result
}

///|
let header : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|use smithy.serialization#untagged
  #|

///|
test "preparation refusals" {
  inspect(
    refusal(
      header +
      "union U { a: Integer, b: Long }\n@untagged union V { a: Integer, b: Long }\nstructure R { v: V }",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#V: Untagged members a and b both accept JSON number values.",
  )
  inspect(
    refusal(
      header +
      "@untagged union V { a: String, b: Timestamp }\nstructure R { v: V }\n",
      "example#R",
      None,
    ),
    content="prepared",
  )
  inspect(
    refusal(
      header +
      "@untagged union V { a: String, @timestampFormat(\"date-time\") b: Timestamp }\nstructure R { v: V }\n",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#V: Untagged members a and b both accept JSON string values.",
  )
  inspect(
    refusal(
      header + "@jsonProfiles([{id: \"p\"}])\nstructure R { v: Integer }",
      "example#R",
      Some("q"),
    ),
    content="UnknownProfile: I expected a declared serialization profile, but found no profile q.",
  )
  inspect(
    refusal(
      header +
      "@jsonProfiles([{id: \"p\"}])\nstructure R { v: Integer }\n@jsonProfiles([{id: \"p\"}])\nstructure S { v: Integer }",
      "example#R",
      Some("p"),
    ),
    content="ConflictingDeclaration: example#S: Profile p is already declared on example#R.",
  )
  inspect(
    refusal(
      header +
      "@jsonProfiles([{id: \"p\", defaults: {union: {style: \"internal\", tag: \"kind\"}}}])\nstructure R { u: U }\nunion U { a: A, b: Integer }\nstructure A { x: Integer }",
      "example#R",
      Some("p"),
    ),
    content="InvalidDeclaration: example#U: Internally tagged member b needs an object structure payload.",
  )
  inspect(
    refusal(
      header +
      "@jsonProfiles([{id: \"p\", defaults: {union: {style: \"internal\", tag: \"kind\"}}}])\nstructure R { u: U }\nunion U { a: A }\nstructure A { kind: Integer }",
      "example#R",
      Some("p"),
    ),
    content="InvalidDeclaration: example#U: The discriminator kind collides with field kind of member a.",
  )
  inspect(
    refusal(
      header +
      "@jsonProfiles([{id: \"p\", defaults: {union: {style: \"spliced\"}}}])\nstructure R { u: U }\nunion U { a: Integer }",
      "example#R",
      Some("p"),
    ),
    content="UnsupportedDeclaration: example#U: I do not implement the union style \"spliced\".",
  )
  inspect(
    refusal(
      header +
      "@jsonProfiles([{id: \"p\", requires: [\"yamlAnchors\"]}])\nstructure R { u: Integer }",
      "example#R",
      Some("p"),
    ),
    content="UnsupportedDeclaration: example#R: Profile p requires the capability \"yamlAnchors\", which I do not implement.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {union: {style: \"external\"}})\n@untagged\nunion U { a: Integer, b: String }\nstructure R { u: U }",
      "example#R",
      None,
    ),
    content="ConflictingDeclaration: example#U: I found conflicting base union styles external and untagged.",
  )
  inspect(
    refusal(
      header +
      "structure R { @jsonEncoding(base: {adapter: \"x.name\"}) v: String }",
      "example#R",
      None,
    ),
    content="MissingAdapter: example#R$v: I expected the host to register scalar adapter x.name, but it is not registered.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {union: {style: \"tagArray\"}})\nstructure R { v: String }",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#R: A union rule needs a union shape.",
  )
}

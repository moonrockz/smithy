///|
let fqname_pattern = "^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$"

///|
fn validator(
  source : String,
  config~ : @validation.Config = @validation.Config::new(),
) -> @validation.PreparedValidator raise {
  @validation.PreparedValidator::prepare(
    model(source),
    target("Value"),
    config~,
  )
}

///|
fn codes(result : @validation.ValidationResult) -> Array[String] {
  result.findings.map(f => f.code.to_string())
}

///|
test "string enums retain constraints and member overrides" {
  let m = model(
    "@length(min: 2)\n@pattern(\"^a\")\nenum Value {\n A = \"ab\"\n B = \"b\"\n}\nstructure Input {\n @length(min: 1)\n @pattern(\"^b\")\n value: Value\n}",
  )
  let direct = @validation.PreparedValidator::prepare(m, target("Value"))
  assert_true(direct.validate_json(Json::string("ab")).is_valid())
  assert_eq(codes(direct.validate_json(Json::string("b"))), [
    "Length", "Pattern",
  ])
  let member_ = @validation.PreparedValidator::prepare(m, target("Input"))
  assert_true(
    member_.validate_json(@json.parse("{\"value\":\"b\"}")).is_valid(),
  )
  assert_eq(codes(member_.validate_json(@json.parse("{\"value\":\"ab\"}"))), [
    "Pattern",
  ])
}

///|
test "pattern matching consumes work proportional to pattern and input" {
  let v = validator(
    "@pattern(\"^a+$\")\nstring Value",
    config=@validation.Config::new(limits=@validation.Limits::new(work=20)),
  )
  let result = v.validate_json(Json::string("a".repeat(100)))
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
}

///|
test "scalar values enforce exact types numeric bounds and constraints" {
  for
    (source, good, bad, code) in [
      ("boolean Value", "true", "0", "TypeMismatch"),
      ("string Value", "\"x\"", "1", "TypeMismatch"),
      ("byte Value", "127", "128", "NumericBounds"),
      ("short Value", "-32768", "-32769", "NumericBounds"),
      ("integer Value", "2147483647", "2147483647.1", "NumericBounds"),
      (
        "long Value", "9223372036854775807", "9223372036854775808", "NumericBounds",
      ),
      ("bigInteger Value", "1e1000000", "1.1", "NumericBounds"),
      ("bigDecimal Value", "0.10000000000000000001", "\"0.1\"", "TypeMismatch"),
      ("float Value", "3e38", "4e38", "NumericBounds"),
      ("double Value", "1e308", "2e308", "NumericBounds"),
      (
        "@range(min: 9007199254740993, max: 9007199254740994)\nlong Value", "9007199254740993",
        "9007199254740992", "Range",
      ),
      (
        "@length(min: 1, max: 1)\nstring Value", "\"🐟\"", "\"🐟x\"", "Length",
      ),
      ("@pattern(\"^[a-z]+$\")\nstring Value", "\"abc\"", "\"a1\"", "Pattern"),
      ("blob Value", "\"YQ==\"", "\"YR==\"", "InvalidEncoding"),
      ("@length(min: 1, max: 1)\nblob Value", "\"YQ==\"", "\"YWI=\"", "Length"),
      ("timestamp Value", "123.456", "\"123\"", "TypeMismatch"),
      (
        "@timestampFormat(\"date-time\")\ntimestamp Value", "\"2024-02-29T12:00:00Z\"",
        "\"2023-02-29T12:00:00Z\"", "InvalidTimestamp",
      ),
      ("enum Value {\n A = \"a\"\n B = \"b\"\n}", "\"a\"", "\"c\"", "EnumValue"),
      ("intEnum Value {\n A = 1\n B = 2\n}", "1.0", "3", "EnumValue"),
    ] {
    let v = validator(source)
    assert_true(v.validate_json(@json.parse(good)).is_valid(), msg=source)
    let result = v.validate_json(@json.parse(bad))
    assert_eq(codes(result), [code], msg=source)
    assert_true(result.complete)
    assert_eq(result.findings[0].shape, target("Value"))
  }
}

///|
test "structures distinguish missing null unknown and serialized member names" {
  let v = validator(
    "structure Value { @required count: Integer, optional: String }",
  )
  assert_true(v.validate_json(@json.parse("{\"count\":1}")).is_valid())
  for
    (text, code, pointer, shape) in [
      ("{}", "RequiredMember", "/count", "Value$count"),
      ("{\"count\":null}", "TypeMismatch", "/count", "Value$count"),
      (
        "{\"count\":1,\"optional\":null}", "TypeMismatch", "/optional", "Value$optional",
      ),
      ("{\"count\":1,\"extra\":2}", "UnknownMember", "/extra", "Value"),
    ] {
    let result = v.validate_json(@json.parse(text))
    assert_eq(codes(result), [code])
    assert_eq(result.findings[0].path.pointer(), pointer)
    assert_eq(result.findings[0].shape, target(shape))
  }
  let named = validator(
    "structure Value { @jsonName(\"wire\") original: String }",
    config=@validation.Config::new(member_names=JsonName),
  )
  assert_true(named.validate_json(@json.parse("{\"wire\":\"x\"}")).is_valid())
  assert_eq(codes(named.validate_json(@json.parse("{\"original\":\"x\"}"))), [
    "UnknownMember",
  ])
}

///|
test "unions sparse collections map keys and uniqueness retain precise paths" {
  let union_ = validator("union Value { text: String, flag: Unit }")
  assert_true(union_.validate_json(@json.parse("{\"flag\":{}}")).is_valid())
  assert_eq(codes(union_.validate_json(@json.parse("{}"))), ["UnionMember"])
  assert_eq(
    codes(union_.validate_json(@json.parse("{\"text\":\"x\",\"flag\":{}}"))),
    ["UnionMember"],
  )
  assert_eq(codes(union_.validate_json(@json.parse("{\"other\":1}"))), [
    "UnknownMember",
  ])
  for
    (source, text, expected) in [
      ("list Value { member: String }", "[null]", false),
      ("@sparse\nlist Value { member: String }", "[null]", true),
      ("map Value { key: String, value: Integer }", "{\"x\":null}", false),
      (
        "@sparse\nmap Value { key: String, value: Integer }", "{\"x\":null}", true,
      ),
    ] {
    assert_eq(
      validator(source).validate_json(@json.parse(text)).is_valid(),
      expected,
    )
  }
  let keys = validator(
    "@pattern(\"^[a-z]+$\")\nstring Key\nmap Value { key: Key, value: Integer }",
  )
  let result = keys.validate_json(@json.parse("{\"X\":1}"))
  assert_eq(codes(result), ["Pattern"])
  assert_eq(result.findings[0].path.steps(), [@validation.MapKey("X", 0)])
  let unique = validator("@uniqueItems\nlist Value { member: Document }")
  assert_true(unique.validate_json(@json.parse("[1,2]")).is_valid())
  assert_eq(codes(unique.validate_json(@json.parse("[1,1.0]"))), ["UniqueItems"])
  assert_eq(
    codes(
      unique.validate_json(
        @json.parse("[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1.0}]"),
      ),
    ),
    ["UniqueItems"],
  )
}

///|
test "prepared contracts snapshot effective overrides and repeated calls are isolated" {
  let m = model(
    "@range(min: 10, max: 20)\ninteger Count\nstructure Value { a: Count, b: Count }",
  )
  let member_ = m.shapes.get(target("Value$a")).unwrap()
  let range = @smithy.ShapeId::parse("smithy.api#range").unwrap()
  member_.traits[range] = @smithy.NodeValue::from_json(
    @json.parse("{\"min\":0}"),
  )
  let prepared = @validation.PreparedValidator::prepare(m, target("Value"))
  member_.traits[range] = @smithy.NodeValue::from_json(
    @json.parse("{\"min\":100}"),
  )
  let value = @json.parse("{\"a\":30,\"b\":15}")
  let before = value.stringify()
  assert_true(prepared.validate_json(value).is_valid())
  assert_eq(codes(prepared.validate_json(@json.parse("{\"b\":30}"))), ["Range"])
  assert_true(prepared.validate_json(value).is_valid())
  assert_eq(value.stringify(), before)
}

///|
test "validation limits also apply to documents ignored fields and comparisons" {
  let depth = @validation.Config::new(limits=@validation.Limits::new(depth=2))
  let doc = validator("document Value", config=depth)
  let result = doc.validate_json(@json.parse("[[[0]]]"))
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
  let ignored = validator(
    "structure Value {}",
    config=@validation.Config::new(
      limits=@validation.Limits::new(depth=2),
      unknown_members=Ignore,
    ),
  )
  assert_false(
    ignored.validate_json(@json.parse("{\"extra\":[[[0]]]}")).is_valid(),
  )
  let work = validator(
    "document Value",
    config=@validation.Config::new(limits=@validation.Limits::new(work=3)),
  )
  assert_false(work.validate_json(@json.parse("[1,2,3,4]")).complete)
  let findings = validator(
    "list Value { member: Integer }",
    config=@validation.Config::new(limits=@validation.Limits::new(findings=2)),
  )
  let result = findings.validate_json(@json.parse("[\"a\",\"b\",\"c\"]"))
  assert_eq(codes(result), ["TypeMismatch", "LimitExceeded"])
  assert_false(result.complete)
}

///|
enum ForeignValue {
  Text(String)
  Fields(Array[(String, ForeignValue)])
  Projected(Array[@validation.LocatedField[ForeignValue]])
  List(Array[ForeignValue])
  Scalar(@validation.NativeScalar)
}

///|
impl @validation.ValueView for ForeignValue with fn inspect(self) {
  match self {
    Text(text) => String(text)
    Fields(fields) => Object(fields)
    Projected(fields) => LocatedObject(fields)
    List(values) => Array(values)
    Scalar(value) => Native(value)
  }
}

///|
test "external adapters retain duplicate occurrence and projected array paths" {
  let v = validator("structure Value { a: String }")
  let input = ForeignValue::Fields([("a", Text("one")), ("a", Text("two"))])
  let result = v.validate(input)
  assert_eq(codes(result), ["DuplicateMember"])
  assert_eq(result.findings[0].path.steps(), [@validation.Field("a", 1)])
  let v = validator("structure Value { @required count: Integer }")
  let source = @validation.InstancePath::root().index(0)
  let input = ForeignValue::Projected([
    @validation.LocatedField::new("count", ForeignValue::Text("3"), source),
  ])
  let result = v.validate(
    input,
    base_path=@validation.InstancePath::root().field("params"),
  )
  assert_eq(codes(result), ["TypeMismatch"])
  assert_eq(result.findings[0].path.pointer(), "/params/0")
  assert_eq(result.findings[0].shape, target("Value$count"))
  let native = ForeignValue::Scalar(
    Decimal(@smithy.NodeNumber::parse("-0.00").unwrap()),
  )
  assert_eq(codes(v.validate(native)), ["UnsupportedValue"])
  match native {
    Scalar(Decimal(n)) => assert_eq(n.to_string(), "-0.00")
    _ => fail("Expected unchanged native decimal")
  }
}

///|
test "recursive caller values and structural comparisons terminate at limits" {
  let values : Array[ForeignValue] = []
  let cycle = ForeignValue::List(values)
  values.push(cycle)
  let v = validator(
    "document Value",
    config=@validation.Config::new(limits=@validation.Limits::new(depth=8)),
  )
  let result = v.validate(cycle)
  assert_eq(codes(result), ["LimitExceeded"])
  assert_false(result.is_valid())
  let unique = validator(
    "@uniqueItems\nlist Value { member: Document }",
    config=@validation.Config::new(limits=@validation.Limits::new(depth=8)),
  )
  let result = unique.validate(ForeignValue::List([cycle, cycle]))
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
}

///|
test "defaults never change input or excuse a missing required member" {
  let m = model("structure Value { count: Integer = 2\n}")
  m.shapes.get(target("Value$count")).unwrap().traits[@smithy.ShapeId::parse(
    "smithy.api#required",
  ).unwrap()] = @smithy.Object(Map([]))
  let prepared = @validation.PreparedValidator::prepare(m, target("Value"))
  let input = Json::object(Map([]))
  assert_eq(codes(prepared.validate_json(input)), ["RequiredMember"])
  assert_eq(input, Json::object(Map([])))
}

///|
test "the Morphir FQName pattern validates within the default work limit" {
  let v = validator("@pattern(\"" + fqname_pattern + "\")\nstring Value")
  let ok = v.validate_json(Json::string("morphir/SDK:basics#int"))
  assert_true(ok.complete)
  assert_eq(codes(ok), [])
  let mixed = v.validate_json(Json::string("morphir/SdK:basics#int"))
  assert_eq(codes(mixed), ["Pattern"])
  // Each code unit costs one step, so the default limit stops a value of
  // 100,000 units before the matcher reads it.
  let long = v.validate_json(Json::string("a:b#c" + "-c".repeat(5000)))
  assert_eq(codes(long), [])
  let over = v.validate_json(Json::string("a:b#c" + "-c".repeat(50000)))
  assert_eq(codes(over), ["LimitExceeded"])
}

///|
test "the FQName pattern matches long values in linear work" {
  // 6005 units cost about one work unit each, far below the default limit.
  let v = validator("@pattern(\"" + fqname_pattern + "\")\nstring Value")
  let long = "a:b#c" + "-c".repeat(3000)
  let ok = v.validate_json(Json::string(long))
  assert_true(ok.complete)
  assert_eq(codes(ok), [])
  assert_eq(codes(v.validate_json(Json::string(long + "-"))), ["Pattern"])
}

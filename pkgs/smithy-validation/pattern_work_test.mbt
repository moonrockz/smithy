///|
/// The Morphir IR v4 type model of the tour case study (lessons 34-39).
let morphir_type_model : String = "@pattern(\"^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$\")\nstring Name\n@pattern(\"" +
  fqname_pattern +
  "\")\nstring FQName\nunion Type {\n Variable: VariableType\n Reference: ReferenceType\n Record: RecordType\n Unit: UnitType\n}\nlist TypeList { member: Type }\nmap FieldMap { key: Name, value: Type }\nstructure VariableType { @required name: Name }\nstructure ReferenceType { @required fqname: FQName, args: TypeList }\nstructure RecordType { @required fields: FieldMap }\nstructure UnitType {}"

///|
fn morphir_type() -> @validation.PreparedValidator raise {
  @validation.PreparedValidator::prepare(
    model(morphir_type_model),
    target("Type"),
  )
}

///|
fn reference(fqname : String) -> Json {
  Json::object(
    Map([("Reference", Json::object(Map([("fqname", Json::string(fqname))])))]),
  )
}

///|
fn record(fields : Array[(String, Json)]) -> Json {
  Json::object(
    Map([("Record", Json::object(Map([("fields", Json::object(Map(fields)))])))]),
  )
}

///|
test "a 97-unit FQName validates within the default work limit" {
  let long = "my-org/finance-and-risk/regulatory-reporting:liquidity/coverage-ratio#calculate-net-cash-outflows"
  assert_eq(long.length(), 97)
  let v = validator("@pattern(\"" + fqname_pattern + "\")\nstring Value")
  let result = v.validate_json(Json::string(long))
  assert_true(result.complete)
  assert_eq(codes(result), [])
  let reference = morphir_type().validate_json(reference(long))
  assert_true(reference.complete)
  assert_eq(codes(reference), [])
}

///|
test "a record of 16 FQName references validates within the default work limit" {
  let fields = (0)
    .until(16)
    .map(i => ("f\{i}", reference("morphir/SDK:basics#int")))
    .to_array()
  let result = morphir_type().validate_json(record(fields))
  assert_true(result.complete)
  assert_eq(codes(result), [])
}

///|
test "the books-and-records deal record validates within the default work limit" {
  let deal = record([
    (
      "product",
      reference("morphir/reference/model:books-and-records#product-ID"),
    ),
    ("price", reference("morphir/reference/model:books-and-records#price")),
    (
      "quantity",
      reference("morphir/reference/model:books-and-records#quantity"),
    ),
  ])
  let result = morphir_type().validate_json(deal)
  assert_true(result.complete)
  assert_eq(codes(result), [])
  let wrong = record([("product", reference("morphir/reference/model:Books#x"))])
  assert_eq(codes(morphir_type().validate_json(wrong)), ["Pattern"])
}

///|
test "a chain of optional items stops at the work limit on a short input" {
  // One automaton step of this pattern visits about 50,000 expression nodes.
  let v = validator("@pattern(\"^(a?){150}a{150}$\")\nstring Value")
  let result = v.validate_json(Json::string("a".repeat(10)))
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
}

///|
test "a pattern with many automaton states stops at the work limit on a long input" {
  let text = StringBuilder()
  let mut x = 12345
  for _ in 0..<10000 {
    x = (x * 1103515245 + 12345) & 0x7fffffff
    text.write_char(if (x >> 16) % 2 == 0 { 'a' } else { 'b' })
  }
  let v = validator("@pattern(\"a(a|b){10}c\")\nstring Value")
  let result = v.validate_json(Json::string(text.to_string()))
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
}

///|
test "a chain of 200 optional items exceeds the preparation caps" {
  let m = model("@pattern(\"^(a?){200}a{200}$\")\nstring Value")
  let mut rejected = false
  ignore(@validation.PreparedValidator::prepare(m, target("Value"))) catch {
    @validation.UnsupportedConstraint(_, _) => rejected = true
    _ => fail("Expected UnsupportedConstraint")
  }
  assert_true(rejected)
}

///|
/// `count` pseudo-random letters `a` and `b`, from `seed`.
fn random_ab(count : Int32, seed : Int32) -> String {
  let text = StringBuilder()
  let mut x = seed
  for _ in 0..<count {
    x = (x * 1103515245 + 12345) & 0x7fffffff
    text.write_char(if (x >> 16) % 2 == 0 { 'a' } else { 'b' })
  }
  text.to_string()
}

///|
test "a validator that has seen many values gives the results of a fresh one" {
  let source = "@pattern(\"a(a|b){10}c\")\nstring Value"
  let warm = validator(source)
  for i in 0..<400 {
    ignore(warm.validate_json(Json::string(random_ab(2000, i + 1))))
  }
  for i in 0..<50 {
    let value = Json::string(random_ab(60, 1000 + i))
    assert_eq(
      codes(warm.validate_json(value)),
      codes(validator(source).validate_json(value)),
      msg="value \{i}",
    )
  }
}

///|
test "the same value gives the same result on every call" {
  let v = validator("@pattern(\"^(a?){60}a{60}$\")\nstring Value")
  let value = Json::string("a".repeat(60))
  let first = codes(v.validate_json(value))
  for i in 0..<12 {
    assert_eq(codes(v.validate_json(value)), first, msg="call \{i}")
  }
}

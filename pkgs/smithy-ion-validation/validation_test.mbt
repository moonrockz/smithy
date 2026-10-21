///|
fn validator(
  source : String,
  config~ : @validation.Config = @validation.Config::new(),
) -> @adapter.PreparedValidator raise {
  let loaded = @smithy.Loader::new()
    .add_idl("value.smithy", "$version: \"2\"\nnamespace example\n" + source)
    .assemble()
  @adapter.PreparedValidator::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Value").unwrap(),
    config~,
  )
}

///|
test "validates original Ion strings against nested Smithy constraints" {
  let v = validator(
    "@length(min: 2)\nstring Name\nstructure Value { @required name: Name }",
  )
  let value = @text.read_ion("{name: \"a\"}")
  let result = v.validate(value)
  assert_false(result.is_valid())
  assert_eq(result.findings[0].code, @validation.Length)
  assert_eq(result.findings[0].path.pointer(), "/name")
  assert_eq(result.findings[0].native_kind, Some(@ion.IonType::String))
  assert_true(v.validate(@text.read_ion("{name: \"ab\"}")).is_valid())
}

///|
test "native scalar mappings preserve exact integer decimal and float semantics" {
  for
    (source, text, valid, code) in [
      ("boolean Value", "true", true, @validation.TypeMismatch),
      ("long Value", "9223372036854775807", true, @validation.NumericBounds),
      ("long Value", "9223372036854775808", false, @validation.NumericBounds),
      (
        "@range(min: 9007199254740993)\nlong Value",
        "9007199254740992",
        false,
        @validation.Range,
      ),
      (
        "bigDecimal Value",
        "123456789012345678901234567890d-20",
        true,
        @validation.TypeMismatch,
      ),
      ("bigDecimal Value", "1d2147483647", true, @validation.TypeMismatch),
      ("bigDecimal Value", "-0d-2147483648", true, @validation.TypeMismatch),
      ("integer Value", "1.0", false, @validation.TypeMismatch),
      ("double Value", "1.25e0", true, @validation.TypeMismatch),
      ("integer Value", "1e0", false, @validation.TypeMismatch),
      ("double Value", "nan", false, @validation.UnsupportedValue),
      (
        "@length(min: 2, max: 2)\nblob Value",
        "{{YWI=}}",
        true,
        @validation.Length,
      ),
      ("@length(min: 2)\nblob Value", "{{YQ==}}", false, @validation.Length),
      ("blob Value", "\"YQ==\"", false, @validation.TypeMismatch),
      (
        "timestamp Value",
        "2024-02-29T12:34:56.123-05:00",
        true,
        @validation.UnsupportedValue,
      ),
      ("timestamp Value", "2024T", false, @validation.UnsupportedValue),
      (
        "timestamp Value",
        "2024-02-29T12:34:56-00:00",
        false,
        @validation.UnsupportedValue,
      ),
      ("timestamp Value", "0", false, @validation.TypeMismatch),
      (
        "timestamp Value",
        "\"2024-02-29T12:34:56Z\"",
        false,
        @validation.TypeMismatch,
      ),
    ] {
    let result = validator(source).validate(@text.read_ion(text))
    assert_eq(result.is_valid(), valid, msg=text + " against " + source)
    if !valid {
      assert_eq(result.findings[0].code, code, msg=text)
    }
  }
}

///|
test "every Ion kind survives diagnostics including typed nulls" {
  let v = validator("string Value")
  for kind in @ion.IonType::all() {
    let value = @ion.Ion::typed_null(kind)
    let result = v.validate(value)
    assert_false(result.is_valid())
    assert_eq(result.findings[0].native_kind, Some(kind))
  }
  for
    (text, kind) in [
      ("false", @ion.IonType::Bool),
      ("1", @ion.IonType::Int),
      ("1e0", @ion.IonType::Float),
      ("1d0", @ion.IonType::Decimal),
      ("2024T", @ion.IonType::Timestamp),
      ("symbol", @ion.IonType::Symbol),
      ("{{\"clob\"}}", @ion.IonType::Clob),
      ("{{YQ==}}", @ion.IonType::Blob),
      ("[]", @ion.IonType::List),
      ("()", @ion.IonType::Sexp),
      ("{}", @ion.IonType::Struct),
    ] {
    let result = v.validate(@text.read_ion(text))
    assert_false(result.is_valid())
    assert_eq(result.findings[0].native_kind, Some(kind))
  }
}

///|
test "Document accepts native finite JSON kinds and rejects unsupported open content" {
  let v = validator("document Value")
  for
    text in [
      "null", "null.int", "true", "\"s\"", "1", "1.25", "1e0", "[1, null.string]",
      "{a: 1.0}",
    ] {
    assert_true(v.validate(@text.read_ion(text)).is_valid(), msg=text)
  }
  for
    text in [
      "symbol", "{{YQ==}}", "{{\"a\"}}", "2024T", "()", "nan", "tag::1", "{a: symbol}",
    ] {
    let result = v.validate(@text.read_ion(text))
    assert_false(result.is_valid(), msg=text)
    assert_eq(result.findings[0].code, @validation.UnsupportedValue)
  }
}

///|
test "collection nulls duplicates unknown members and union cardinality follow core rules" {
  assert_false(
    validator("list Value { member: String }")
    .validate(@text.read_ion("[null.string]"))
    .is_valid(),
  )
  assert_true(
    validator("@sparse\nlist Value { member: String }")
    .validate(@text.read_ion("[null.string]"))
    .is_valid(),
  )
  assert_true(
    validator("union Value { text: String, flag: Unit }")
    .validate(@text.read_ion("{text: \"x\"}"))
    .is_valid(),
  )
  assert_false(
    validator("union Value { text: String, flag: Unit }")
    .validate(@text.read_ion("{}"))
    .is_valid(),
  )
  let v = validator("structure Value { @required name: String }")
  let missing = v.validate(@text.read_ion("{}"))
  assert_eq(missing.findings[0].code, @validation.RequiredMember)
  assert_eq(missing.findings[0].native_kind, None)
  let duplicate = v.validate(@text.read_ion("{name: \"x\", name: 2}"))
  let f = duplicate.findings.filter(f => f.code == @validation.DuplicateMember)[0]
  assert_eq(f.path.steps(), [@validation.Field("name", 1)])
  assert_eq(f.native_kind, Some(@ion.IonType::Int))
  assert_false(
    v.validate(@text.read_ion("{name: \"x\", extra: true}")).is_valid(),
  )
}

///|
test "adapter preserves policies while forcing the native profile" {
  let config = @validation.Config::new(
    unknown_members=@validation.Ignore,
    nonnumeric_floats=true,
  )
  let v = validator("structure Value { value: Double }", config~)
  assert_true(
    v.validate(@text.read_ion("{value: nan, extra: {a: [1, 2]}}")).is_valid(),
  )
  let unsupported = v.validate(@text.read_ion("{extra: {a: symbol}}"))
  assert_eq(unsupported.findings[0].code, @validation.UnsupportedValue)
  assert_eq(unsupported.findings[0].path.pointer(), "/extra/a")
  let limited = validator(
    "document Value",
    config=@validation.Config::new(limits=@validation.Limits::new(work=3)),
  )
  let result = limited.validate(@text.read_ion("[1, [2, [3, 4]]]"))
  assert_false(result.complete)
  assert_false(result.is_valid())
  assert_true(
    result.findings.iter().any(f => f.code == @validation.LimitExceeded),
  )
}

///|
test "annotations are rejected without moving descendant occurrence paths" {
  let value = @text.read_ion("tag::{name: 1}")
  let result = validator("structure Value { name: String }").validate(value)
  assert_eq(result.findings[0].code, @validation.UnsupportedValue)
  assert_eq(result.findings[0].path.pointer(), "")
  let mismatch = result.findings.filter(f => f.code == @validation.TypeMismatch)[0]
  assert_eq(mismatch.path.pointer(), "/name")
  assert_eq(mismatch.native_kind, Some(@ion.IonType::Int))
}

///|
test "unresolved symbols and annotations remain unsupported native values" {
  let v = validator("document Value")
  let symbol = v.validate(
    @ion.Ion::symbol_token(@ion.SymbolToken::from_sid(999)),
  )
  assert_eq(symbol.findings[0].code, @validation.UnsupportedValue)
  assert_eq(symbol.findings[0].native_kind, Some(@ion.IonType::Symbol))
  let annotated = @ion.Ion::list([@ion.Ion::clob(b"a")]).with_annotation(
    @ion.SymbolToken::from_sid(998),
  )
  let result = v.validate(annotated)
  assert_eq(result.findings[0].code, @validation.UnsupportedValue)
  assert_eq(result.findings[0].native_kind, Some(@ion.IonType::List))
  assert_eq(result.findings[1].path.steps(), [@validation.Index(0)])
  assert_eq(result.findings[1].native_kind, Some(@ion.IonType::Clob))
  assert_eq(annotated.annotations()[0].sid(), Some(998))
}

///|
test "binary floats keep their exact magnitude rather than printed decimal magnitude" {
  let v = validator("@range(max: 0.1)\ndouble Value")
  assert_true(v.validate(@text.read_ion("0.1")).is_valid())
  let binary_float = v.validate(@text.read_ion("1e-1"))
  assert_false(binary_float.is_valid())
  assert_eq(binary_float.findings[0].code, @validation.Range)
  assert_eq(binary_float.findings[0].native_kind, Some(@ion.IonType::Float))
  let nonfinite = validator(
    "@range(min: 0)\ndouble Value",
    config=@validation.Config::new(nonnumeric_floats=true),
  ).validate(@text.read_ion("nan"))
  assert_eq(nonfinite.findings[0].code, @validation.Range)
}

///|
test "member names and findings limits retain the supplied configuration" {
  let v = validator(
    "structure Value { @jsonName(\"wire\") name: String }",
    config=@validation.Config::new(member_names=@validation.JsonName),
  )
  assert_true(v.validate(@text.read_ion("{wire: \"ok\"}")).is_valid())
  let limited = validator(
    "list Value { member: String }",
    config=@validation.Config::new(limits=@validation.Limits::new(findings=2)),
  ).validate(@text.read_ion("[1, 2, 3]"))
  assert_false(limited.complete)
  assert_eq(limited.findings.length(), 2)
  assert_eq(limited.findings[1].code, @validation.LimitExceeded)
}

///|
test "unresolved fields use physical field positions and preserve the original value" {
  let field = @ion.Field::from_token(
    @ion.SymbolToken::from_sid(99),
    @ion.Ion::int(2),
  )
  let value = @ion.Ion::from_fields([field])
  let result = validator("document Value").validate(value)
  assert_eq(result.findings[0].code, @validation.UnsupportedValue)
  assert_eq(result.findings[0].path.steps(), [@validation.FieldNamePosition(0)])
  assert_eq(result.findings[0].native_kind, Some(@ion.IonType::Symbol))
  assert_true(value.equals(@ion.Ion::from_fields([field])))
}

///|
test "unresolved field name and unsupported value have separate native kinds" {
  let value = @ion.Ion::from_fields([
    @ion.Field::from_token(@ion.SymbolToken::from_sid(99), @ion.Ion::clob(b"a")),
  ])
  let result = validator("document Value").validate(value)
  assert_eq(result.findings.length(), 2)
  assert_eq(result.findings[0].native_kind, Some(@ion.IonType::Symbol))
  assert_eq(result.findings[1].native_kind, Some(@ion.IonType::Clob))
  assert_eq(result.findings[0].path.steps(), [@validation.FieldNamePosition(0)])
  assert_eq(result.findings[1].path.steps(), [@validation.FieldPosition(0)])
}

///|
test "map key findings identify field name symbols" {
  let result = validator(
    "@pattern(\"^[a-z]+$\")\nstring Key\nmap Value { key: Key, value: Integer }",
  ).validate(@text.read_ion("{INVALID: 1}"))
  assert_eq(result.findings[0].code, @validation.Pattern)
  assert_eq(result.findings[0].path.steps(), [@validation.MapKey("INVALID", 0)])
  assert_eq(result.findings[0].native_kind, Some(@ion.IonType::Symbol))
}

///|
test "invalid programmatic timestamp reports a finding rather than raising" {
  let value = @ion.Ion::timestamp(
    @ion.Timestamp(
      year=2024,
      month=Some(2),
      day=Some(30),
      hour=Some(1),
      minute=Some(2),
      second=Some(3),
      offset=Some(@ion.Known(0)),
    ),
  )
  let result = validator("timestamp Value").validate(value)
  assert_false(result.is_valid())
  assert_eq(result.findings[0].code, @validation.UnsupportedValue)
  assert_eq(result.findings[0].native_kind, Some(@ion.IonType::Timestamp))
}

///|
test "equivalent Ion text and binary produce equal findings without mutating input" {
  let original = @text.read_ion(
    "{name: \"x\", name: 1, nested: [true, symbol], decimal: -0d-4}",
  )
  let before = @text.write_ion(original)
  let encoded = @binary.write_binary_value(original)
  let decoded = @binary.read_binary_value(encoded)
  let v = validator(
    "structure Value { name: String, nested: Document, decimal: BigDecimal }",
  )
  assert_eq(v.validate(original), v.validate(decoded))
  assert_eq(@text.write_ion(original), before)
  assert_true(original.equals(decoded))
}

///|
test "native uniqueness compares numeric values and byte contents" {
  let numeric = validator("@uniqueItems\nlist Value { member: Document }").validate(
    @text.read_ion("[1, 1.0, 1e0]"),
  )
  assert_true(
    numeric.findings.iter().any(f => f.code == @validation.UniqueItems),
  )
  let blobs = validator("@uniqueItems\nlist Value { member: Blob }").validate(
    @text.read_ion("[{{YQ==}}, {{YQ==}}]"),
  )
  assert_true(blobs.findings.iter().any(f => f.code == @validation.UniqueItems))
}

///|
test "JSON diagnostics retain structured occurrence paths and native kinds" {
  let result = validator("structure Value { value: String }").validate(
    @text.read_ion("{value: 2}"),
  )
  guard @json.to_json(result) is Object(json) else {
    fail("expected result object")
  }
  assert_eq(json.get("valid"), Some(Json::boolean(false)))
  guard json.get("findings") is Some(Array(findings)) else {
    fail("expected findings array")
  }
  guard findings[0] is Object(finding) else { fail("expected finding object") }
  assert_eq(finding.get("nativeKind"), Some(Json::string("int")))
  assert_eq(finding.get("pointer"), Some(Json::string("/value")))
  assert_eq(finding.get("path"), Some(@json.to_json(result.findings[0].path)))
}

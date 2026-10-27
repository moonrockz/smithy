///|
let numbers_model : String =
  #|$version: "2"
  #|namespace example
  #|structure Amounts {
  #|  big: BigInteger
  #|  exact: BigDecimal
  #|  @range(max: 10)
  #|  small: BigDecimal
  #|  name: String
  #|  tags: Tags
  #|}
  #|list Tags { member: String }

///|
test "exact numbers survive check, decode and encode" {
  let codec = @codec.PreparedCodec::prepare(
    load(numbers_model),
    id("example#Amounts"),
  )
  let text = "{\"big\":123456789012345678901234567890,\"exact\":0.1000000000000000000000001,\"small\":10.0000000000000000000000001}"
  let result = codec.check(text)
  assert_eq(result.findings.length(), 1)
  assert_eq(result.findings[0].code, Constraint(Range))
  assert_eq(result.findings[0].path.pointer(), "/small")
  let ok = "{\"big\":123456789012345678901234567890,\"exact\":0.1000000000000000000000001,\"small\":9.99999999999999999999999}"
  assert_eq(codec.canonicalize(ok), ok)
}

///|
test "escaped duplicate member names are refused before projection" {
  let codec = @codec.PreparedCodec::prepare(
    load(numbers_model),
    id("example#Amounts"),
  )
  let result = codec.check("{\"name\":\"a\",\"\\u006eame\":\"b\"}")
  assert_false(result.is_valid())
  assert_eq(result.findings[0].code, DuplicateName)
  let failed = failure(() => {
    ignore(codec.decode("{\"name\":\"a\",\"\\u006eame\":\"b\"}"))
  })
  assert_eq(failed.findings[0].code, DuplicateName)
}

///|
test "limits stop the request without a value or output" {
  let limits = @codec.CodecLimits::new(work=20)
  let codec = @codec.PreparedCodec::prepare(
    load(numbers_model),
    id("example#Amounts"),
    limits~,
  )
  let tags = Array::make(50, "\"t\"").join(",")
  let text = "{\"tags\":[" + tags + "]}"
  let result = codec.check(text)
  assert_false(result.complete)
  assert_false(result.is_valid())
  assert_eq(result.findings[result.findings.length() - 1].code, LimitExceeded)
  assert_false(failure(() => ignore(codec.decode(text))).complete)
  assert_false(failure(() => ignore(codec.canonicalize(text))).complete)
  let shallow = @codec.PreparedCodec::prepare(
    load(tuple_model),
    id("example#Call"),
    profile=Some(profile("arrays")),
    limits=@codec.CodecLimits::new(depth=2),
  )
  let deep = shallow.check("[\"f\",[\"a\",1]]")
  assert_false(deep.complete)
  let input = @codec.PreparedCodec::prepare(
    load(numbers_model),
    id("example#Amounts"),
    limits=@codec.CodecLimits::new(input_bytes=8),
  )
  assert_false(input.check("{\"name\":\"abcdef\"}").complete)
}

///|
test "encoding refuses invalid caller values and other roots" {
  let model = load(expr_model)
  let codec = @codec.PreparedCodec::prepare(
    model,
    id("example#Expr"),
    profile=Some(profile("array")),
  )
  // An incomplete structure and an invalid union payload are refused with findings.
  let result = failure(() => {
    ignore(
      codec.value(
        Union(
          "Add",
          Structure([("left", Union("Num", @codec.LogicalValue::number("1")))]),
        ),
      ),
    )
  })
  assert_eq(result.findings[0].code, Constraint(RequiredMember))
  let result = failure(() => ignore(codec.value(Union("Mul", Structure([])))))
  assert_eq(result.findings[0].code, UnknownTag)
  let result = failure(() => {
    ignore(codec.value(Union("Num", @codec.LogicalValue::number("500"))))
  })
  assert_eq(result.findings[0].code, Constraint(Range))
  // A value of another root is refused.
  let other = @codec.PreparedCodec::prepare(
    load(numbers_model),
    id("example#Amounts"),
  )
  let amounts = other.decode("{\"name\":\"a\"}")
  let result = failure(() => ignore(codec.encode(amounts)))
  assert_eq(result.findings[0].code, IncompatibleValue)
  // A model edit after preparation does not change the prepared codec.
  let value = codec.decode("[\"Num\",3]")
  model.shapes.remove(id("example#Add"))
  assert_eq(codec.encode(value), "[\"Num\",3]")
}

///|
fn failure(run : () -> Unit raise) -> @codec.CodecResult raise {
  try run() catch {
    @codec.CodecFailure(result) => result
    e => fail("expected a codec failure, but found " + e.to_string())
  } noraise {
    _ => fail("expected a codec failure")
  }
}

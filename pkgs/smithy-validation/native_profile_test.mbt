///|
enum NativeValue {
  Null
  Text(String)
  Int(String)
  List(Array[NativeValue])
  Fields(Array[(String?, NativeValue)])
  Scalar(@validation.NativeScalar)
  Sexp(Array[NativeValue])
  Annotated(NativeValue)
}

///|
impl @validation.ValueView for NativeValue with fn inspect(self) {
  match self {
    Null => Null
    Text(s) => String(s)
    Int(s) => Number(@smithy.NodeNumber::parse(s).unwrap())
    List(a) => Array(a)
    Fields(a) => NativeObject(a)
    Scalar(s) => Native(s)
    Sexp(a) => Sexp(a)
    Annotated(a) => Annotated([None], a)
  }
}

///|
fn native_validator(
  source : String,
  config~ : @validation.Config = @validation.Config::new(profile=NativeProfile),
) -> @validation.PreparedValidator raise {
  validator(source, config~)
}

///|
fn decimal(s : String) -> NativeValue {
  Scalar(Decimal(@smithy.NodeNumber::parse(s).unwrap()))
}

///|
fn timestamp(full~ : Bool = true, known~ : Bool = true) -> NativeValue raise {
  Scalar(
    Timestamp(
      @validation.NativeTimestamp::new(
        2024,
        month=Some(2),
        day=Some(29),
        hour=Some(12),
        minute=Some(30),
        second=if full { Some(0) } else { None },
        offset=if known { KnownOffsetMinutes(0) } else { UnknownOffset },
      ),
    ),
  )
}

///|
test "native decimal kind controls target independently of integral magnitude" {
  for kind in ["bigDecimal", "float", "double", "document"] {
    assert_true(
      native_validator(kind + " Value").validate(decimal("-0.00")).is_valid(),
      msg=kind,
    )
  }
  for kind in ["byte", "short", "integer", "long", "bigInteger", "string"] {
    assert_eq(
      codes(native_validator(kind + " Value").validate(decimal("1.0"))),
      ["TypeMismatch"],
      msg=kind,
    )
  }
  assert_eq(
    codes(
      native_validator("@range(max: 0.1)\nbigDecimal Value").validate(
        decimal("0.10000000000000000001"),
      ),
    ),
    ["Range"],
  )
  assert_eq(codes(native_validator("float Value").validate(decimal("4e38"))), [
    "NumericBounds",
  ])
  assert_eq(codes(validator("bigDecimal Value").validate(decimal("1"))), [
    "UnsupportedValue",
  ])
}

///|
test "native floats use exact binary values and do not coerce to decimals or integers" {
  let value = NativeValue::Scalar(Float(0.1))
  assert_eq(
    codes(native_validator("@range(max: 0.1)\ndouble Value").validate(value)),
    ["Range"],
  )
  for kind in ["float", "double", "document"] {
    assert_true(native_validator(kind + " Value").validate(value).is_valid())
  }
  for kind in ["integer", "bigInteger", "bigDecimal"] {
    assert_eq(
      codes(
        native_validator(kind + " Value").validate(
          NativeValue::Scalar(Float(1.0)),
        ),
      ),
      ["TypeMismatch"],
    )
  }
  assert_eq(
    codes(
      native_validator("float Value").validate(
        NativeValue::Scalar(Float(4.0e38)),
      ),
    ),
    ["NumericBounds"],
  )
  let enabled = @validation.Config::new(
    profile=NativeProfile,
    nonnumeric_floats=true,
  )
  for f in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    let v = NativeValue::Scalar(Float(f))
    assert_eq(codes(native_validator("double Value").validate(v)), [
      "UnsupportedValue",
    ])
    assert_true(
      native_validator("double Value", config=enabled).validate(v).is_valid(),
    )
    assert_eq(
      codes(native_validator("document Value", config=enabled).validate(v)),
      ["UnsupportedValue"],
    )
  }
  assert_eq(
    codes(
      native_validator("@range(min: 0, max: 1)\ndouble Value", config=enabled).validate(
        NativeValue::Scalar(Float(0.0 / 0.0)),
      ),
    ),
    ["Range"],
  )
}

///|
test "native blobs and timestamps accept only their physical native kinds" {
  let blob = NativeValue::Scalar(Blob(b"ab"))
  assert_true(
    native_validator("@length(min: 2, max: 2)\nblob Value")
    .validate(blob)
    .is_valid(),
  )
  assert_eq(
    codes(native_validator("@length(max: 1)\nblob Value").validate(blob)),
    ["Length"],
  )
  assert_true(
    native_validator("timestamp Value").validate(timestamp()).is_valid(),
  )
  for value in [timestamp(full=false), timestamp(known=false)] {
    assert_eq(codes(native_validator("timestamp Value").validate(value)), [
      "UnsupportedValue",
    ])
  }
  for
    (kind, value) in [
      ("blob", NativeValue::Text("YQ==")),
      ("timestamp", NativeValue::Int("0")),
      ("timestamp", NativeValue::Text("2024-02-29T12:30:00Z")),
      ("double", NativeValue::Text("NaN")),
    ] {
    assert_eq(codes(native_validator(kind + " Value").validate(value)), [
      "TypeMismatch",
    ])
  }
  for
    value in [
      blob,
      timestamp(),
      NativeValue::Scalar(Symbol(Some("x"))),
      NativeValue::Scalar(Clob(b"a")),
      NativeValue::Sexp([]),
    ] {
    assert_eq(codes(native_validator("document Value").validate(value)), [
      "UnsupportedValue",
    ])
    assert_eq(
      codes(
        native_validator(
          "structure Value {}",
          config=@validation.Config::new(
            profile=NativeProfile,
            unknown_members=Ignore,
          ),
        ).validate(NativeValue::Fields([(Some("ignored"), value)])),
      ),
      ["UnsupportedValue"],
    )
  }
}

///|
test "native typed null follows collection placement and never means absent" {
  let null = NativeValue::Scalar(TypedNull(IntKind))
  assert_true(native_validator("document Value").validate(null).is_valid())
  assert_eq(codes(native_validator("integer Value").validate(null)), [
    "TypeMismatch",
  ])
  assert_true(
    native_validator("@sparse\nlist Value { member: Integer }")
    .validate(NativeValue::List([null]))
    .is_valid(),
  )
  assert_eq(
    codes(
      native_validator("structure Value { @required count: Integer }").validate(
        NativeValue::Fields([(Some("count"), null)]),
      ),
    ),
    ["TypeMismatch"],
  )
}

///|
test "unresolved field positions preserve siblings duplicates and budget inspection" {
  let v = native_validator("structure Value { a: String }")
  let input = NativeValue::Fields([
    (Some("a"), Text("one")),
    (None, Scalar(Symbol(None))),
    (Some("a"), Text("two")),
  ])
  let result = v.validate(input)
  assert_eq(codes(result), [
    "UnsupportedValue", "DuplicateMember", "UnsupportedValue",
  ])
  assert_eq(result.findings[0].path.steps(), [@validation.FieldNamePosition(1)])
  assert_eq(result.findings[1].path.steps(), [@validation.Field("a", 1)])
  assert_eq(result.findings[2].path.steps(), [@validation.FieldPosition(1)])
  let key = @validation.InstancePath::root().field_name_position(1)
  assert_eq(key.pointer(), "/1")
  assert_eq(
    @json.to_json(key),
    @json.parse("[{\"kind\":\"fieldNamePosition\",\"index\":1}]"),
  )
  let mut invalid_name = false
  ignore(@validation.InstancePath::root().field_name_position(-1)) catch {
    _ => invalid_name = true
  }
  assert_true(invalid_name)
  let path = @validation.InstancePath::root().field_position(2)
  assert_eq(path.pointer(), "/2")
  assert_eq(
    @json.to_json(path),
    @json.parse("[{\"kind\":\"fieldPosition\",\"index\":2}]"),
  )
  let mut rejected = false
  ignore(@validation.InstancePath::root().field_position(-1)) catch {
    _ => rejected = true
  }
  assert_true(rejected)
  let bounded = native_validator(
    "document Value",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(depth=2),
    ),
  )
  assert_false(
    bounded.validate(NativeValue::Fields([(None, List([List([Null])]))])).complete,
  )
}

///|
test "annotations reject at the same path and still inspect descendants within limits" {
  let value = NativeValue::Annotated(
    Fields([(Some("a"), Scalar(Symbol(None)))]),
  )
  let result = native_validator("document Value").validate(value)
  assert_eq(codes(result), ["UnsupportedValue", "UnsupportedValue"])
  assert_eq(result.findings[1].path.pointer(), "/a")
  let cycle : Array[NativeValue] = []
  let list = NativeValue::List(cycle)
  cycle.push(Annotated(list))
  let result = native_validator(
    "document Value",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(work=20),
    ),
  ).validate(list)
  assert_false(result.complete)
  assert_true(codes(result).contains("LimitExceeded"))
  let result = native_validator(
    "document Value",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(work=3),
    ),
  ).validate(NativeValue::Sexp([Null, Null, Null, Null]))
  assert_false(result.complete)
}

///|
test "native uniqueness compares exact mathematical numbers bytes timestamp components and null" {
  let numbers = native_validator(
    "@uniqueItems\nlist Value { member: Document }",
  )
  for
    values in [
      [NativeValue::Int("1"), decimal("1.0")],
      [NativeValue::Int("1"), NativeValue::Scalar(Float(1.0))],
      [NativeValue::Null, NativeValue::Scalar(TypedNull(BlobKind))],
    ] {
    assert_eq(codes(numbers.validate(NativeValue::List(values))), [
      "UniqueItems",
    ])
  }
  assert_true(
    numbers
    .validate(NativeValue::List([decimal("0.1"), Scalar(Float(0.1))]))
    .is_valid(),
  )
  assert_eq(
    codes(
      native_validator("@uniqueItems\nlist Value { member: Blob }").validate(
        NativeValue::List([Scalar(Blob(b"abc")), Scalar(Blob(b"abc"))]),
      ),
    ),
    ["UniqueItems"],
  )
  assert_eq(
    codes(
      native_validator("@uniqueItems\nlist Value { member: Timestamp }").validate(
        NativeValue::List([timestamp(), timestamp()]),
      ),
    ),
    ["UniqueItems"],
  )
  let result = numbers.validate(
    NativeValue::List([Annotated(Int("1")), Annotated(Int("1"))]),
  )
  assert_eq(codes(result), ["UnsupportedValue", "UnsupportedValue"])
}

///|
test "native float subnormals extrema signed zero and nonfinite ranges remain exact" {
  let smallest = NativeValue::Scalar(Float(1L.reinterpret_as_double()))
  let m = model("double Value")
  let range = @smithy.ShapeId::parse("smithy.api#range").unwrap()
  m.shapes.get(target("Value")).unwrap().traits[range] = @smithy.Object({
    "max": @smithy.Number(@smithy.NodeNumber::parse("4e-324").unwrap()),
  })
  let bounded = @validation.PreparedValidator::prepare(
    m,
    target("Value"),
    config=@validation.Config::new(profile=NativeProfile),
  )
  assert_eq(codes(bounded.validate(smallest)), ["Range"])
  m.shapes.get(target("Value")).unwrap().traits[range] = @smithy.Object({
    "min": @smithy.Number(@smithy.NodeNumber::parse("4e-324").unwrap()),
    "max": @smithy.Number(@smithy.NodeNumber::parse("5e-324").unwrap()),
  })
  assert_true(
    @validation.PreparedValidator::prepare(
      m,
      target("Value"),
      config=@validation.Config::new(profile=NativeProfile),
    )
    .validate(smallest)
    .is_valid(),
  )
  let largest = NativeValue::Scalar(
    Float(0x7fefffffffffffffL.reinterpret_as_double()),
  )
  assert_true(native_validator("double Value").validate(largest).is_valid())
  assert_eq(codes(native_validator("float Value").validate(largest)), [
    "NumericBounds",
  ])
  let config = @validation.Config::new(
    profile=NativeProfile,
    nonnumeric_floats=true,
  )
  assert_true(
    native_validator("@range(min: 0)\ndouble Value", config~)
    .validate(NativeValue::Scalar(Float(1.0 / 0.0)))
    .is_valid(),
  )
  assert_eq(
    codes(
      native_validator("@range(max: 0)\ndouble Value", config~).validate(
        NativeValue::Scalar(Float(1.0 / 0.0)),
      ),
    ),
    ["Range"],
  )
  let unique = native_validator(
    "@uniqueItems\nlist Value { member: Double }",
    config~,
  )
  assert_eq(
    codes(
      unique.validate(
        NativeValue::List([Scalar(Float(0.0 / 0.0)), Scalar(Float(0.0 / 0.0))]),
      ),
    ),
    ["UniqueItems"],
  )
  assert_eq(
    codes(unique.validate(NativeValue::List([Scalar(Float(-0.0)), Int("0")]))),
    ["UniqueItems"],
  )
}

///|
test "native fields retain member constraint paths sparse map placement and required history" {
  let v = native_validator(
    "@range(min: 10)\ninteger Count\nstructure Value { @required count: Count }",
  )
  let result = v.validate(
    NativeValue::Fields([(Some("count"), Int("1")), (Some("count"), Int("2"))]),
  )
  assert_eq(codes(result), ["DuplicateMember", "Range", "Range"])
  assert_eq(result.findings[2].path.steps(), [@validation.Field("count", 1)])
  assert_eq(result.findings[2].shape, target("Value$count"))
  let result = v.validate(NativeValue::Fields([(None, Int("15"))]))
  assert_eq(codes(result), ["UnsupportedValue", "RequiredMember"])
  let null = NativeValue::Scalar(TypedNull(TimestampKind))
  assert_true(
    native_validator("@sparse\nmap Value { key: String, value: Timestamp }")
    .validate(NativeValue::Fields([(Some("x"), null)]))
    .is_valid(),
  )
  assert_eq(
    codes(
      native_validator("map Value { key: String, value: Timestamp }").validate(
        NativeValue::Fields([(Some("x"), null)]),
      ),
    ),
    ["TypeMismatch"],
  )
  assert_eq(
    codes(
      native_validator("timestamp Value").validate(
        NativeValue::Scalar(InvalidTimestamp),
      ),
    ),
    ["UnsupportedValue"],
  )
  assert_true(
    native_validator("@timestampFormat(\"date-time\")\ntimestamp Value")
    .validate(timestamp())
    .is_valid(),
  )
}

///|
test "native uniqueness preserves object names and invalid value identity" {
  let v = native_validator("@uniqueItems\nlist Value { member: Document }")
  assert_eq(
    codes(
      v.validate(
        NativeValue::List([
          Fields([(Some("a"), Int("1")), (Some("b"), Int("2"))]),
          Fields([(Some("b"), decimal("2.0")), (Some("a"), Int("1"))]),
        ]),
      ),
    ),
    ["UniqueItems"],
  )
  let result = v.validate(
    NativeValue::List([Fields([(None, Int("1"))]), Fields([(None, Int("1"))])]),
  )
  assert_eq(codes(result), ["UnsupportedValue", "UnsupportedValue"])
  let bytes = native_validator("@uniqueItems\nlist Value { member: Blob }")
  assert_true(
    bytes
    .validate(NativeValue::List([Scalar(Blob(b"a")), Scalar(Blob(b"b"))]))
    .is_valid(),
  )
}

///|
test "native uniqueness charges field scans before inspecting unresolved names" {
  let value = NativeValue::Fields([
    (None, Null),
    (Some("a"), Null),
    (Some("b"), Null),
  ])
  let result = native_validator(
    "@uniqueItems\nlist Value { member: Document }",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(work=8),
    ),
  ).validate(NativeValue::List([value, value]))
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
}

///|
test "native timestamp uniqueness retains fractional precision" {
  let values : Array[NativeValue] = []
  for fraction in ["0.0", "0.00"] {
    values.push(
      Scalar(
        Timestamp(
          @validation.NativeTimestamp::new(
            2024,
            month=Some(2),
            day=Some(29),
            hour=Some(12),
            minute=Some(30),
            second=Some(0),
            fraction=Some(@smithy.NodeNumber::parse(fraction).unwrap()),
            offset=KnownOffsetMinutes(0),
          ),
        ),
      ),
    )
  }
  assert_true(
    native_validator("@uniqueItems\nlist Value { member: Timestamp }")
    .validate(NativeValue::List(values))
    .is_valid(),
  )
}

///|
enum ProbeNode {
  Scalar
  Children(Array[ProbeValue])
  Annotation(Int32, ProbeValue)
}

///|
struct ProbeValue {
  width : Int32
  inspected : Array[Int32]
  node : ProbeNode
}

///|
impl @validation.ValueView for ProbeValue with fn expansion_size(self) {
  self.width
}

///|
impl @validation.ValueView for ProbeValue with fn inspect(self) {
  self.inspected[0] += 1
  match self.node {
    Scalar => Null
    Children(values) => Array(values)
    Annotation(count, value) => Annotated(Array::make(count, None), value)
  }
}

///|
test "validation preflights container and annotation expansion before inspecting" {
  for annotated in [false, true] {
    let inspected = [0]
    let leaf : ProbeValue = { width: 0, inspected, node: Scalar, }
    let value : ProbeValue = {
      width: 100,
      inspected,
      node: if annotated {
        Annotation(0, leaf)
      } else {
        Children([])
      },
    }
    let result = native_validator(
      "document Value",
      config=@validation.Config::new(
        profile=NativeProfile,
        limits=@validation.Limits::new(work=8),
      ),
    ).validate(value)
    assert_false(result.complete)
    assert_eq(codes(result), ["LimitExceeded"])
    assert_eq(inspected[0], 0)
  }
}

///|
test "uniqueness preflights both operands before inspecting either expansion" {
  let root_count = [0]
  let left_count = [0]
  let right_count = [0]
  let left : ProbeValue = { width: 0, inspected: left_count, node: Scalar, }
  let right : ProbeValue = {
    width: 100,
    inspected: right_count,
    node: Children([]),
  }
  let root : ProbeValue = {
    width: 2,
    inspected: root_count,
    node: Children([right, left]),
  }
  let result = native_validator(
    "@uniqueItems\nlist Value { member: Document }",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(work=8),
    ),
  ).validate(root)
  assert_false(result.complete)
  assert_eq(codes(result), ["LimitExceeded"])
  assert_eq(root_count[0], 1)
  assert_eq(left_count[0], 0)
  assert_eq(right_count[0], 0)
}

///|
test "native timestamp preparation ignores legal HTTP date serialization" {
  assert_true(
    native_validator("@timestampFormat(\"http-date\")\ntimestamp Value")
    .validate(timestamp())
    .is_valid(),
  )
  let mut rejected = false
  ignore(validator("@timestampFormat(\"http-date\")\ntimestamp Value")) catch {
    @validation.UnsupportedConstraint(_, _) => rejected = true
    _ => fail("Expected unsupported HTTP date in JSON profile")
  }
  assert_true(rejected)
}

///|
test "annotation tag expansions consume aggregate validation work" {
  let inspected = [0]
  let leaf : ProbeValue = { width: 0, inspected: [0], node: Scalar, }
  let annotated : ProbeValue = {
    width: 4,
    inspected,
    node: Annotation(4, leaf),
  }
  let root : ProbeValue = {
    width: 2,
    inspected: [0],
    node: Children([annotated, annotated]),
  }
  let result = native_validator(
    "document Value",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(work=10),
    ),
  ).validate(root)
  assert_false(result.complete)
  assert_eq(inspected[0], 1)
  assert_eq(codes(result), ["UnsupportedValue", "LimitExceeded"])
}

///|
test "annotation tag expansions consume aggregate uniqueness work" {
  let inspected = [0]
  let leaf : ProbeValue = { width: 0, inspected: [0], node: Scalar, }
  let annotated : ProbeValue = {
    width: 4,
    inspected,
    node: Annotation(4, leaf),
  }
  let root : ProbeValue = {
    width: 3,
    inspected: [0],
    node: Children([annotated, annotated, annotated]),
  }
  let result = native_validator(
    "@uniqueItems\nlist Value { member: Document }",
    config=@validation.Config::new(
      profile=NativeProfile,
      limits=@validation.Limits::new(work=16),
    ),
  ).validate(root)
  assert_false(result.complete)
  assert_eq(inspected[0], 4)
  assert_eq(codes(result), ["LimitExceeded"])
}

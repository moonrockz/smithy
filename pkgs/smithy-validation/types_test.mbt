///|
test "instance paths retain field occurrences map keys and source positions" {
  let root = @validation.InstancePath::root()
  let field = root.field("a/b~c", occurrence=1)
  assert_eq(field.pointer(), "/a~1b~0c")
  assert_eq(field.steps(), [@validation.Field("a/b~c", 1)])
  assert_true(field != root.field("a/b~c"))
  assert_true(root.map_key("a/b~c") != root.field("a/b~c"))
  assert_eq(root.field("params").append(root.index(2)).pointer(), "/params/2")
  let mut rejected = 0
  ignore(root.index(-1)) catch {
    _ => rejected += 1
  }
  ignore(root.field("x", occurrence=-1)) catch {
    _ => rejected += 1
  }
  ignore(root.map_key("x", occurrence=-1)) catch {
    _ => rejected += 1
  }
  assert_eq(rejected, 3)
}

///|
test "limits reject invalid budgets rather than disabling checks" {
  for
    (depth, work, findings) in [
      (0, 1, 1),
      (1025, 1, 1),
      (1, 0, 1),
      (1, 10000001, 1),
      (1, 1, 0),
      (1, 1, 10001),
    ] {
    let mut rejected = false
    ignore(@validation.Limits::new(depth~, work~, findings~)) catch {
      _ => rejected = true
    }
    assert_true(rejected)
  }
  ignore(@validation.Limits::new(depth=1024, work=10000000, findings=10000))
}

///|
test "exact numbers expose their token and integral classification" {
  for
    (text, integral) in [
      ("9007199254740993", true),
      ("1e1000000", true),
      ("-0", true),
      ("9223372036854775807.1", false),
    ] {
    let number = @smithy.NodeNumber::parse(text).unwrap()
    assert_eq(number.to_string(), text)
    assert_eq(number.is_integer(), integral)
  }
  assert_eq(@smithy.NodeNumber::parse("1"), @smithy.NodeNumber::parse("1.0"))
}

///|
test "JSON view preserves numbers and reports invalid host numbers" {
  let input = @json.parse("9007199254740993")
  match @validation.ValueView::inspect(input) {
    Number(n) => assert_eq(n.to_string(), "9007199254740993")
    _ => fail("Expected exact number view")
  }
  match @validation.ValueView::inspect(Json::number(1.0 / 0.0)) {
    InvalidNumber => ()
    _ => fail("Expected invalid numeric input")
  }
}

///|
test "native timestamp boundary rejects impossible dates and partial times" {
  ignore(@validation.NativeTimestamp::new(2024, month=Some(2), day=Some(29)))
  for
    (year, month, day, hour) in [
      (2023, 2, 29, None),
      (2024, 13, 1, None),
      (2024, 1, 32, None),
      (2024, 1, 1, Some(12)),
    ] {
    let mut rejected = false
    ignore(
      @validation.NativeTimestamp::new(
        year,
        month=Some(month),
        day=Some(day),
        hour~,
      ),
    ) catch {
      _ => rejected = true
    }
    assert_true(rejected)
  }
}

///|
test "neutral native timestamps restrict seconds to zero through fifty-nine" {
  for offset in [@validation.UnknownOffset, @validation.KnownOffsetMinutes(0)] {
    let timestamp = @validation.NativeTimestamp::new(
      2016,
      month=Some(12),
      day=Some(31),
      hour=Some(23),
      minute=Some(59),
      second=Some(59),
      offset~,
    )
    assert_eq(timestamp.second(), Some(59))
    let mut rejected = false
    ignore(
      @validation.NativeTimestamp::new(
        2016,
        month=Some(12),
        day=Some(31),
        hour=Some(23),
        minute=Some(59),
        second=Some(60),
        offset~,
      ),
    ) catch {
      @validation.ConfigurationError(_) => rejected = true
    }
    assert_true(rejected)
  }
}

///|
test "instance path map keys distinguish occurrence key token and value identity" {
  let root = @validation.InstancePath::root()
  let paths = [
    root.field("a"),
    root.field("a", occurrence=1),
    root.map_key("a"),
    root.index(0),
    root.field_position(0),
    root.field_name_position(0),
  ]
  let values : Map[@validation.InstancePath, Int32] = Map([])
  for i in 0..<paths.length() {
    values[paths[i]] = i
  }
  assert_eq(values.length(), 6)
  assert_eq(values.get(root.field("a", occurrence=1)), Some(1))
  assert_eq(values.get(root.field_name_position(0)), Some(5))
  assert_eq(values.get(root.field("b")), None)
}

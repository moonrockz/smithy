///|
test "date-time accepts every recorded UTC leap second" {
  let v = validator("@timestampFormat(\"date-time\")\ntimestamp Value")
  // Insertion days from NIST's table, independently listed from the parser.
  for
    date in [
      "1972-06-30", "1972-12-31", "1973-12-31", "1974-12-31", "1975-12-31", "1976-12-31",
      "1977-12-31", "1978-12-31", "1979-12-31", "1981-06-30", "1982-06-30", "1983-06-30",
      "1985-06-30", "1987-12-31", "1989-12-31", "1990-12-31", "1992-06-30", "1993-06-30",
      "1994-06-30", "1995-12-31", "1997-06-30", "1998-12-31", "2005-12-31", "2008-12-31",
      "2012-06-30", "2015-06-30", "2016-12-31",
    ] {
    let text = date + "T23:59:60Z"
    assert_true(v.validate_json(Json::string(text)).is_valid(), msg=text)
  }
}

///|
test "date-time leap seconds account for offsets fractions and calendar rollovers" {
  let trait_validator = validator(
    "@timestampFormat(\"date-time\")\ntimestamp Value",
  )
  let configured = validator(
    "timestamp Value",
    config=@validation.Config::new(timestamp_format=@validation.DateTime),
  )
  for v in [trait_validator, configured] {
    for
      text in [
        "2016-12-31T23:59:60Z", "2016-12-31t23:59:60.12345678901234567890z", "2016-12-31T23:59:60+00:00",
        "2016-12-31T23:59:60-00:00", "1990-12-31T15:59:60-08:00", "2017-01-01T00:59:60+01:00",
        "2017-01-01T05:29:60.5+05:30", "2015-07-01T00:29:60+00:30", "2015-06-30T23:58:60-00:01",
        "2015-07-01T23:58:60+23:59", "2015-06-30T00:00:60-23:59", "1972-07-01T00:00:60+00:01",
        "2016-12-31T23:59:59Z", "2017-01-01T00:00:00Z", "2024-02-29T12:00:59.5+05:30",
        "2099-12-31T23:59:59Z",
      ] {
      assert_true(v.validate_json(Json::string(text)).is_valid(), msg=text)
    }
  }
}

///|
test "date-time rejects false leap seconds and malformed extended seconds" {
  let v = validator("@timestampFormat(\"date-time\")\ntimestamp Value")
  for
    text in [
      "2016-12-30T23:59:60Z", "2016-06-30T23:59:60Z", "2017-12-31T23:59:60Z", "2099-12-31T23:59:60Z",
      "1971-12-31T23:59:60Z", "1972-01-01T00:00:60Z", "2016-12-31T22:59:60Z", "2016-12-31T23:58:60Z",
      "2016-12-31T23:59:61Z", "2016-12-31T24:00:60Z", "2016-12-31T23:60:60Z", "2016-12-31T23:59:60+01:00",
      "2017-01-01T00:59:60-01:00", "2017-01-01T00:00:60+00:00", "2015-06-31T00:29:60+00:30",
      "2015-07-02T00:29:60+00:30", "2016-12-31T23:59:60+24:00", "2016-12-31T23:59:60-00:60",
      "2016-12-31T23:59:60", "2016-12-31T23:59:60.Z", "2016-12-31T23:59:60Zx", "2016-12-31T23:59:60+00:00x",
      "0001-01-01T00:00:60+00:01", "9999-12-31T23:59:60-23:59",
    ] {
    let result = v.validate_json(Json::string(text))
    assert_eq(codes(result), ["InvalidTimestamp"], msg=text)
    assert_true(result.complete)
    assert_eq(result.findings[0].path.pointer(), "")
    assert_eq(result.findings[0].shape, target("Value"))
  }
}

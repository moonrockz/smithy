///|
test "to_number accepts the Java decimal and hexadecimal double syntax" {
  for
    (text, expected) in [
      (" 1.5 ", 1.5),
      ("\t\n1.5\r", 1.5),
      ("1.5d", 1.5),
      ("1.5f", 1.5),
      ("1.5D", 1.5),
      ("1.5F", 1.5),
      (".5", 0.5),
      ("5.", 5.0),
      ("+1.5", 1.5),
      ("0x1.8p1", 3.0),
      ("-0X.8P+2F", -2.0),
      ("0x1Ep0", 30.0),
      ("0x1.00000000000008p0", 1.0),
      ("0x1.0000000000000801p0", 1.0000000000000002),
      ("0x0.0000000000001p-1022", 5.0e-324),
      ("0x0.00000000000008p-1022", 0.0),
      ("0x0.0000000000000801p-1022", 5.0e-324),
      ("0x1.fffffffffffffp1023", 1.7976931348623157e308),
      ("1e-999999999999999999", 0.0),
      ("+12", 12.0),
    ] {
    let result = @jmespath.search("to_number(@)", Json::string(text))
    guard result is Number(n, ..) else {
      fail(text + " did not return a number")
    }
    assert_eq(n, expected, msg=text)
  }
  for
    text in [
      "1_0.5", " 12 ", "0x1p3", "1.5 d", "1.5ff", "0x1.8", "0x.p1", "0x1.8p", "1e",
      "1.e+", ".", "\u{a0}1.5", "1.5\u{a0}", "NaN", "Infinity",
    ] {
    assert_eq(
      @jmespath.search("to_number(@)", Json::string(text)),
      Json::null(),
      msg=text,
    )
  }
}

///|
test "to_number keeps overflow and signed zero as Java doubles" {
  for text in ["1e999", "1e999999999999999999", "0x1.0p999999999999999999"] {
    let result = @jmespath.search("to_number(@)", Json::string(text))
    guard result is Number(n, ..) else {
      fail(text + " did not return a number")
    }
    assert_true(n.is_pos_inf(), msg=text)
    assert_eq(
      @jmespath.search("to_number(@) > `1e308`", Json::string(text)),
      Json::boolean(true),
    )
  }
  for text in ["-1e999", "-0x1.0p9999"] {
    guard @jmespath.search("to_number(@)", Json::string(text)) is Number(n, ..) else {
      fail(text)
    }
    assert_true(n.is_neg_inf(), msg=text)
  }
  for text in ["-0.0", "-1e-9999", "-0x0.0p0", "-0x1.0p-9999"] {
    guard @jmespath.search("to_number(@)", Json::string(text)) is Number(n, ..) else {
      fail(text)
    }
    assert_eq(n.reinterpret_as_int64(), 0x8000000000000000L, msg=text)
  }
}

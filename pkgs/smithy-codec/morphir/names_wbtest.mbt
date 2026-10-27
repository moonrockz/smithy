///|
/// naming-conformance.json legacyDecodeCases and roundTripCases: (legacy array JSON, canonical).
let legacy_cases : Array[(String, String)] = [
  ("[\"value\", \"in\", \"u\", \"s\", \"d\"]", "value-in-USD"),
  ("[\"a\"]", "a"),
  ("[\"morphir\", \"s\", \"d\", \"k\"]", "morphir-SDK"),
  ("[\"point\", \"x\", \"y\"]", "point-XY"),
  ("[\"max\", \"n\"]", "max-n"),
  ("[\"get\", \"h\", \"t\", \"m\", \"l\"]", "get-HTML"),
  ("[\"u\", \"s\"]", "US"),
  ("[\"f\", \"r\", \"2052\", \"a\"]", "FR-2052-a"),
  ("[\"1\", \"2\"]", "1-2"),
  ("[\"u\", \"1\"]", "u-1"),
  ("[\"v\", \"2\", \"api\"]", "v-2-api"),
  ("[\"user\", \"account\"]", "user-account"),
  ("[\"value\", \"in\", \"u\", \"s\", \"d\"]", "value-in-USD"),
  ("[\"in\", \"usd\"]", "in-usd"),
  ("[\"get\", \"h\", \"t\", \"m\", \"l\"]", "get-HTML"),
  ("[\"my\", \"a\", \"p\", \"i\", \"client\"]", "my-API-client"),
  ("[\"user\", \"i\", \"d\"]", "user-ID"),
  ("[\"i\", \"o\", \"error\"]", "IO-error"),
  ("[\"h\", \"t\", \"m\", \"l\", \"parser\"]", "HTML-parser"),
  ("[\"a\"]", "a"),
  ("[\"max\", \"n\"]", "max-n"),
  ("[\"2052\"]", "2052"),
  ("[\"data\", \"i\", \"d\", \"tables\"]", "data-ID-tables"),
  ("[\"aux\"]", "aux"),
  ("[\"c\", \"o\", \"n\"]", "CON"),
  ("[\"nul\", \"pointer\"]", "nul-pointer"),
  ("[\"com1\"]", "com1"),
]

///|
/// naming-conformance.json rejectCases and roundTripCases: (input, valid in the uppercase style).
let name_validity : Array[(String, Bool)] = [
  ("Usd", false),
  ("value-in-(usd)", false),
  ("user_id", false),
  ("", false),
  ("-user", false),
  ("user-", false),
  ("value-in--usd", false),
  ("value-in-USD", true),
  ("user--id", false),
  ("morphir/SDK", false),
  ("user---id", false),
  ("--", false),
  ("USD-usd", true),
  ("MyName", false),
  ("user-account", true),
  ("value-in-USD", true),
  ("in-usd", true),
  ("get-HTML", true),
  ("my-API-client", true),
  ("user-ID", true),
  ("IO-error", true),
  ("HTML-parser", true),
  ("a", true),
  ("max-n", true),
  ("2052", true),
  ("FR2052A", true),
  ("data-ID-tables", true),
  ("aux", true),
  ("CON", true),
  ("nul-pointer", true),
  ("com1", true),
]

///|
/// naming-conformance.json pathCases and fqNameCases (uppercase style).
let path_cases : Array[String] = [
  "morphir/SDK", "US/FR2052A/data-tables", "my-org/domain/users",
]

///|
let fqname_cases : Array[String] = [
  "morphir/SDK:list#map", "my-org:domain#value-in-USD",
]

///|
/// format-version-conformance.json scalarCases: (JSON value, normalized release or diagnostic code, canonical JSON).
let version_cases : Array[(String, String, String)] = [
  ("1", "1.0.0", "1"),
  ("2", "2.0.0", "2"),
  ("3", "3.0.0", "3"),
  ("\"3.0.0\"", "3.0.0", "3"),
  ("\"3.0.1\"", "3.0.1", "\"3.0.1\""),
  ("\"3.1.0\"", "3.1.0", "\"3.1.0\""),
  ("\"3.2.0\"", "3.2.0", "\"3.2.0\""),
  ("4", "4.0.0", "4"),
  ("\"4.0.0\"", "4.0.0", "4"),
  ("\"4.0.1\"", "4.0.1", "\"4.0.1\""),
  ("\"4.1.0\"", "4.1.0", "\"4.1.0\""),
  ("\"5.0.0\"", "5.0.0", "5"),
  ("\"5.2.7\"", "5.2.7", "\"5.2.7\""),
  ("5", "5.0.0", "5"),
  ("4294967295", "4294967295.0.0", "4294967295"),
  ("\"4294967295.0.0\"", "4294967295.0.0", "4294967295"),
  ("\"4294967296.0.0\"", "format_version_out_of_range", ""),
  ("0", "invalid_format_version_syntax", ""),
  ("\"1.0.0\"", "invalid_format_version_syntax", ""),
  ("\"2.0.0\"", "invalid_format_version_syntax", ""),
  ("\"3.0\"", "invalid_format_version_syntax", ""),
  ("\"3.0.0.0\"", "invalid_format_version_syntax", ""),
  ("\"3.+1.0\"", "invalid_format_version_syntax", ""),
  ("\"3.-1.0\"", "invalid_format_version_syntax", ""),
  ("\" 3.0.0\"", "invalid_format_version_syntax", ""),
  ("\"3.01.0\"", "invalid_format_version_syntax", ""),
  ("\"4.0.01\"", "invalid_format_version_syntax", ""),
  ("\"3.0.0-alpha\"", "invalid_format_version_syntax", ""),
  ("\"4.0.0+build\"", "invalid_format_version_syntax", ""),
  ("4294967296", "format_version_out_of_range", ""),
  ("\"3.4294967296.0\"", "format_version_out_of_range", ""),
  ("\"4.0.4294967296\"", "format_version_out_of_range", ""),
  ("-1", "invalid_format_version_type", ""),
  ("3.5", "invalid_format_version_type", ""),
  ("true", "invalid_format_version_type", ""),
  ("null", "invalid_format_version_type", ""),
  ("[3]", "invalid_format_version_type", ""),
  ("{\"major\": 3}", "invalid_format_version_type", ""),
]

///|
fn parse(text : String) -> Json {
  @validation.parse_json_value(text) catch {
    _ => abort("bad test JSON " + text)
  }
}

///|
test "v4 legacy word arrays decode as the naming corpus records" {
  for case_ in legacy_cases {
    assert_eq(
      v4_name_read(parse(case_.0), []).map_err(e => e.message),
      Ok(case_.1),
    )
  }
}

///|
test "v4 canonical names are accepted and kept exactly as written" {
  for case_ in name_validity {
    let result = v4_name_read(Json::string(case_.0), [])
    assert_eq(result is Ok(_), case_.1, msg=case_.0)
    if case_.1 {
      assert_eq(result.map_err(e => e.message), Ok(case_.0))
    }
  }
  // names-0003: the retired parenthesized spelling and a mixed-case segment are refused.
  assert_true(v4_name_read(Json::string("value-in-(usd)"), []) is Err(_))
  assert_true(v4_name_read(Json::string("value-in-Usd"), []) is Err(_))
  // u-s (two words) and US (one initialism) are different names; canonical strings are not renormalized.
  assert_eq(
    v4_name_read(Json::string("u-s"), []).map_err(e => e.message),
    Ok("u-s"),
  )
}

///|
test "v4 paths and fully qualified names" {
  for text in path_cases {
    assert_eq(
      v4_path_read(Json::string(text), []).map_err(e => e.message),
      Ok(text),
    )
  }
  for text in fqname_cases {
    assert_eq(
      v4_fqname_read(Json::string(text)).map_err(e => e.message),
      Ok(text),
    )
  }
  // names-0004, names-0006: the SDK package name.
  assert_eq(
    v4_path_read(parse("[[\"morphir\"], [\"s\", \"d\", \"k\"]]"), []).map_err(e => {
      e.message
    }),
    Ok("morphir/SDK"),
  )
  // names-0005: legacy FQName array.
  assert_eq(
    v4_fqname_read(
      parse("[[[\"morphir\"], [\"s\", \"d\", \"k\"]], [[\"list\"]], [\"map\"]]"),
    ).map_err(e => e.message),
    Ok("morphir/SDK:list#map"),
  )
  // Mixed legacy parts: canonical path strings inside a legacy array (wire reference D9).
  assert_eq(
    v4_fqname_read(parse("[\"morphir/SDK\", \"list\", \"map\"]")).map_err(e => {
      e.message
    }),
    Ok("morphir/SDK:list#map"),
  )
  // D9: the 4-element example of the v4 schema is not an FQName.
  assert_true(
    v4_fqname_read(
      parse("[[\"morphir\"], [\"s\", \"d\", \"k\"], [\"list\"], [\"map\"]]"),
    )
    is Err(_),
  )
  for bad in ["morphir/SDK", "a", "a:b", "a#b:c", "a:b#c#d", "a:b:c#d"] {
    assert_true(v4_fqname_read(Json::string(bad)) is Err(_), msg=bad)
  }
  // A bare name never parses as an FQName, and an FQName never parses as a name: the two string forms are
  // disjoint (wire reference 2.2).
  assert_true(
    v4_name_read(Json::string("morphir/SDK:basics#int"), []) is Err(_),
  )
  assert_true(v4_fqname_read(Json::string("a")) is Err(_))
}

///|
test "v3 names, paths and FQNames round-trip through their logical text" {
  let fq = "[[[\"morphir\"],[\"s\",\"d\",\"k\"]],[[\"basics\"]],[\"int\"]]"
  let text = v3_fqname_read(parse(fq)).map_err(e => e.message)
  assert_eq(text, Ok("morphir/s-d-k:basics#int"))
  assert_eq(
    v3_fqname_json("morphir/s-d-k:basics#int")
    .map(j => j.stringify())
    .map_err(e => e.message),
    Ok(fq),
  )
  assert_eq(
    v3_name_read(parse("[\"f\",\"r\",\"2052\",\"a\"]"), []).map_err(e => {
      e.message
    }),
    Ok("f-r-2052-a"),
  )
  // The v3 schema word grammar (D10).
  for
    bad in ["[]", "[\"\"]", "[\"A\"]", "[\"a-b\"]", "[\"2a\"]", "[1]", "\"a\""] {
    assert_true(v3_name_read(parse(bad), []) is Err(_), msg=bad)
  }
  assert_true(v3_fqname_read(parse("[[[\"a\"]],[[\"b\"]]]")) is Err(_))
  let error = v3_path_read(parse("[[\"a\"],[\"B\"]]"), []).unwrap_err()
  assert_eq(error.at, [1, 0])
}

///|
test "v3 key order is Elm's Dict order of word lists" {
  let names = ["ab", "a-b", "a", "b", "a-b-c", "2052", "a1"]
  names.sort_by(v3_name_compare)
  assert_eq(names, ["2052", "a", "a-b", "a-b-c", "a1", "ab", "b"])
  // Paths compare Name by Name, not as joined text: ["a"],["b"] < ["a","x"].
  let paths = ["a-x", "a/b"]
  paths.sort_by(v3_path_compare)
  assert_eq(paths, ["a/b", "a-x"])
}

///|
test "formatVersion scalars follow the format-version corpus" {
  for case_ in version_cases {
    let value = parse(case_.0)
    match format_version_read(value) {
      Ok(text) => {
        assert_eq(text, case_.1, msg=case_.0)
        assert_eq(
          format_version_json(text).map(j => j.stringify()),
          Ok(case_.2),
          msg=case_.0,
        )
      }
      Err(message) =>
        assert_true(
          message.has_prefix(case_.1 + ":"),
          msg=case_.0 + " " + message,
        )
    }
  }
  // Wire reference section 0 gap: an integral token with a fraction or an exponent is not an integer.
  assert_true(format_version_read(parse("3.0")) is Err(_))
  assert_true(format_version_read(parse("3e0")) is Err(_))
}

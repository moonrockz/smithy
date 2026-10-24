///|
fn mismatch(pointer : String, message : String) -> Expected {
  { code: "TypeMismatch", pointer, message, }
}

///|
test "a bare string is a compact type" {
  assert_eq(
    sort(Type, "a"),
    Compact([mismatch("", "I expected a union value, but found string.")]),
  )
}

///|
test "a bare array is a compact type" {
  assert_eq(
    sort(Type, ["a", "b"]),
    Compact([mismatch("", "I expected a union value, but found array.")]),
  )
}

///|
test "a wrapper with a string payload is compact" {
  assert_eq(
    sort(Type, { "Reference": "morphir/SDK:basics#int" }),
    Compact([
      mismatch("/Reference", "I expected a structure value, but found string."),
    ]),
  )
}

///|
test "a wrapper with an array payload is compact" {
  assert_eq(
    sort(Type, { "Tuple": ["a"] }),
    Compact([
      mismatch("/Tuple", "I expected a structure value, but found array."),
    ]),
  )
}

///|
test "a wrapper with an object payload is expanded" {
  assert_eq(
    sort(Type, { "Variable": { "attributes": {}, "name": "a" } }),
    Expanded,
  )
  assert_eq(sort(Type, { "Unit": {} }), Expanded)
}

///|
test "a compact field is found with an escaped pointer" {
  assert_eq(
    sort(Type, { "Record": { "fields": { "a/b": "x" } } }),
    Compact([
      mismatch(
        "/Record/fields/a~1b", "I expected a union value, but found string.",
      ),
    ]),
  )
}

///|
test "a legacy array name is compact" {
  assert_eq(
    sort(Type, { "Variable": { "name": ["a"] } }),
    Compact([
      mismatch("/Variable/name", "I expected a string value, but found array."),
    ]),
  )
}

///|
test "each compact argument gives one finding" {
  assert_eq(
    sort(Type, {
      "Reference": { "fqname": "a:b#c", "args": [{ "Unit": {} }, "x"] },
    }),
    Compact([
      mismatch(
        "/Reference/args/1", "I expected a union value, but found string.",
      ),
    ]),
  )
  assert_eq(
    sort(Type, { "Function": { "parameterType": "a", "returnType": ["b"] } }),
    Compact([
      mismatch(
        "/Function/parameterType", "I expected a union value, but found string.",
      ),
      mismatch(
        "/Function/returnType", "I expected a union value, but found array.",
      ),
    ]),
  )
}

///|
test "a spelling that the sort does not know is Unknown" {
  assert_eq(sort(Type, { "Hole": {} }), Unknown(""))
  assert_eq(
    sort(Type, { "Variable": { "attrs": {}, "name": "a" } }),
    Unknown("/Variable/attrs"),
  )
  assert_eq(sort(Type, { "Variable": {}, "Unit": {} }), Unknown(""))
  assert_eq(sort(Type, 5), Unknown(""))
  assert_eq(
    sort(Type, { "Record": { "fields": ["a"] } }),
    Unknown("/Record/fields"),
  )
  assert_eq(
    sort(Type, { "Variable": { "attributes": [], "name": "a" } }),
    Unknown("/Variable/attributes"),
  )
}

///|
test "Unknown wins over a compact finding" {
  assert_eq(
    sort(Type, { "Tuple": { "elements": ["a", { "Hole": {} }] } }),
    Unknown("/Tuple/elements/1"),
  )
}

///|
test "names, paths and attributes" {
  assert_eq(sort(FQName, "a:b#c"), Expanded)
  assert_eq(sort(Name, 5), Unknown(""))
  assert_eq(
    sort(Path, [["morphir"], ["s", "d", "k"]]),
    Compact([mismatch("", "I expected a string value, but found array.")]),
  )
  assert_eq(sort(TypeAttributes, {}), Expanded)
  assert_eq(sort(SourceLocation, { "startLine": 1 }), Expanded)
  assert_eq(sort(SourceLocation, "x"), Unknown(""))
}

///|
test "a new spelling is named in the snapshot line" {
  let example : Example = {
    source: "s.json",
    at: "/a",
    kind: Type,
    verdict: Accepted,
    value: { "Hole": {} },
  }
  assert_eq(example.line(), "s.json /a Type accepted unknown() {\"Hole\":{}}")
}

///|
test "snapshot lines for each verdict" {
  let legacy : Example = {
    source: "k.feature",
    at: "line 4",
    kind: Name,
    verdict: Legacy("legacy_spelling"),
    value: ["a"],
  }
  assert_eq(
    legacy.line(),
    "k.feature line 4 Name legacy(legacy_spelling) - [\"a\"]",
  )
  let rejected : Example = {
    source: "k.feature",
    at: "line 5",
    kind: Name,
    verdict: Rejected("invalid_name"),
    value: "Usd",
  }
  assert_eq(
    rejected.line(),
    "k.feature line 5 Name rejected(invalid_name) - \"Usd\"",
  )
  let compact : Example = {
    source: "k.feature",
    at: "line 6",
    kind: Type,
    verdict: Accepted,
    value: "a",
  }
  assert_eq(compact.line(), "k.feature line 6 Type accepted compact(1) \"a\"")
}

///|
test "rejected_code maps the Morphir diagnostics" {
  assert_eq(rejected_code("invalid_name"), Some("Pattern"))
  assert_eq(rejected_code("unknown_node"), Some("UnknownMember"))
  assert_eq(rejected_code("unknown_member"), Some("UnknownMember"))
  assert_eq(rejected_code("invalid_type"), Some("TypeMismatch"))
  assert_eq(rejected_code("other"), None)
}

///|
test "kind shapes" {
  assert_eq(Name.shape(), "morphir.ir.v4#Name")
  assert_eq(SourceLocation.shape(), "morphir.ir.v4#SourceLocation")
}

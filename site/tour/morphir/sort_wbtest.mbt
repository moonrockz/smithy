///|
fn mismatch(
  pointer : String,
  spelling : Spelling,
  message : String,
) -> Expected {
  { code: "TypeMismatch", pointer, message, spelling, }
}

///|
test "a bare string is a compact type" {
  assert_eq(
    sort(Type, "a"),
    Other([mismatch("", Compact, "I expected a union value, but found string.")]),
  )
}

///|
test "a bare array is a legacy type" {
  assert_eq(
    sort(Type, ["a", "b"]),
    Other([mismatch("", Legacy, "I expected a union value, but found array.")]),
  )
}

///|
test "a wrapper with a string payload is an accepted wrapper" {
  assert_eq(
    sort(Type, { "Reference": "morphir/SDK:basics#int" }),
    Other([
      mismatch(
        "/Reference",
        Wrapper,
        "I expected a structure value, but found string.",
      ),
    ]),
  )
}

///|
test "a wrapper with an array payload is an accepted wrapper" {
  assert_eq(
    sort(Type, { "Tuple": ["a"] }),
    Other([
      mismatch(
        "/Tuple",
        Wrapper,
        "I expected a structure value, but found array.",
      ),
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
test "a field in another spelling is found with an escaped pointer" {
  assert_eq(
    sort(Type, { "Record": { "fields": { "a/b": "x" } } }),
    Other([
      mismatch(
        "/Record/fields/a~1b",
        Compact,
        "I expected a union value, but found string.",
      ),
    ]),
  )
}

///|
test "a legacy array name is legacy" {
  assert_eq(
    sort(Type, { "Variable": { "name": ["a"] } }),
    Other([
      mismatch(
        "/Variable/name",
        Legacy,
        "I expected a string value, but found array.",
      ),
    ]),
  )
}

///|
test "each argument in another spelling gives one finding" {
  assert_eq(
    sort(Type, {
      "Reference": { "fqname": "a:b#c", "args": [{ "Unit": {} }, "x"] },
    }),
    Other([
      mismatch(
        "/Reference/args/1",
        Compact,
        "I expected a union value, but found string.",
      ),
    ]),
  )
  assert_eq(
    sort(Type, { "Function": { "parameterType": "a", "returnType": ["b"] } }),
    Other([
      mismatch(
        "/Function/parameterType",
        Compact,
        "I expected a union value, but found string.",
      ),
      mismatch(
        "/Function/returnType",
        Legacy,
        "I expected a union value, but found array.",
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
test "Unknown wins over a finding of another spelling" {
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
    Other([mismatch("", Legacy, "I expected a string value, but found array.")]),
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
  assert_eq(example.line(), "Accepted unknown(#) Type s.json /a")
}

///|
test "snapshot lines for each verdict and form" {
  let legacy : Example = {
    source: "k.feature",
    at: "line 4",
    kind: Name,
    verdict: Legacy("legacy_spelling"),
    value: ["a"],
  }
  assert_eq(legacy.line(), "Legacy(legacy_spelling) - Name k.feature line 4")
  let rejected : Example = {
    ..legacy,
    at: "line 5",
    verdict: Rejected("invalid_name"),
  }
  assert_eq(rejected.line(), "Rejected(invalid_name) - Name k.feature line 5")
  let compact : Example = {
    source: "k.feature",
    at: "line 6",
    kind: Type,
    verdict: Accepted,
    value: { "Function": { "parameterType": "a", "returnType": ["b"] } },
  }
  assert_eq(
    compact.line(),
    "Accepted compact(#/Function/parameterType)+legacy(#/Function/returnType) Type k.feature line 6",
  )
  let wrapper : Example = {
    ..compact,
    at: "line 9",
    value: { "Tuple": { "elements": [["a"], { "Reference": "x:y#z" }, "b"] } },
  }
  assert_eq(
    wrapper.line(),
    "Accepted compact(#/Tuple/elements/2)+accepted(#/Tuple/elements/1/Reference)+legacy(#/Tuple/elements/0) Type k.feature line 9",
  )
  // A finding at the root of the value prints as `#`, not as nothing.
  let root : Example = { ..compact, at: "line 8", value: "a", }
  assert_eq(root.line(), "Accepted compact(#) Type k.feature line 8")
  let expanded : Example = { ..compact, at: "line 7", value: { "Unit": {} }, }
  assert_eq(expanded.line(), "Accepted expanded Type k.feature line 7")
}

///|
test "rejected_code maps the Morphir diagnostics" {
  assert_eq(rejected_code("invalid_name"), Some("Pattern"))
  assert_eq(rejected_code("unknown_node"), Some("UnknownMember"))
  assert_eq(rejected_code("unknown_member"), Some("UnknownMember"))
  assert_eq(rejected_code("invalid_type"), Some("TypeMismatch"))
  assert_eq(rejected_code("breaks_max_items"), Some("TypeMismatch"))
  assert_eq(rejected_code("other"), None)
}

///|
test "kind shapes" {
  assert_eq(Name.shape(), "morphir.ir.v4#Name")
  assert_eq(SourceLocation.shape(), "morphir.ir.v4#SourceLocation")
}

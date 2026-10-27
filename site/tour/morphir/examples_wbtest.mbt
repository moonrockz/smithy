///|
test "schema examples come from a definition and from its oneOf arms" {
  let schema : Json = {
    "definitions": {
      "NameString": { "examples": ["a-b"] },
      "Name": {
        "oneOf": [{ "examples": ["a"] }, { "examples": [["a"], ["b", "c"]] }],
      },
      "Other": { "examples": ["skipped"] },
    },
  }
  let found = schema_examples(schema)
  assert_eq(found.map(fn(e) { (e.at, e.kind, e.value.stringify()) }), [
    ("/definitions/NameString/examples/0", Name, "\"a-b\""),
    ("/definitions/Name/oneOf/0/examples/0", Name, "\"a\""),
    ("/definitions/Name/oneOf/1/examples/0", Name, "[\"a\"]"),
    ("/definitions/Name/oneOf/1/examples/1", Name, "[\"b\",\"c\"]"),
  ])
  assert_true(found.all(fn(e) { e.verdict == Accepted }))
}

///|
test "an arm example with more items than maxItems is rejected" {
  let schema : Json = {
    "definitions": {
      "FQName": {
        "oneOf": [
          { "examples": ["a:b#c"] },
          { "maxItems": 3, "examples": [["a", "b", "c"], ["a", "b", "c", "d"]] },
        ],
      },
    },
  }
  assert_eq(schema_examples(schema).map(fn(e) { e.verdict }), [
    Accepted,
    Accepted,
    Rejected("breaks_max_items"),
  ])
}

///|
test "file examples are the top type nodes of a document" {
  let document : Json = {
    "a": {
      "typeExp": { "Record": { "fields": { "x": { "Unit": {} } } } },
      "inputs": { "p": "x", "q/r": { "Unit": {} } },
      "values": [{ "outputType": "o" }],
    },
    "pairs": { "inputs": [["n", "t"], ["m", { "Unit": {} }]] },
    "c": { "constructors": { "Some": [["v", "a"]], "None": [] } },
    "outputType": { "Variable": { "name": "a", "baseType": "inner" } },
  }
  let found = file_examples("f.json", document)
  assert_eq(found.map(fn(e) { e.at }), [
    "/a/typeExp", "/a/inputs/p", "/a/inputs/q~1r", "/a/values/0/outputType", "/pairs/inputs/0/1",
    "/pairs/inputs/1/1", "/c/constructors/Some/0/1", "/outputType",
  ])
  assert_true(found.all(fn(e) { e.kind == Type && e.source == "f.json" }))
}

///|
test "naming examples have the verdicts of the corpus" {
  let corpus : Json = {
    "roundTripCases": [{ "canonical": { "uppercase": "a-b" } }],
    "legacyDecodeCases": [
      { "legacyArray": ["v", "i"], "canonical": { "uppercase": "v-I" } },
    ],
    "rejectCases": [
      { "input": "Usd", "validAs": { "uppercase": false } },
      { "input": "USD", "validAs": { "uppercase": true } },
    ],
    "pathCases": [{ "canonical": { "uppercase": "a/B" } }],
    "fqNameCases": [{ "canonical": { "uppercase": "a:b#c" } }],
  }
  let found = naming_examples("n.json", corpus)
  assert_eq(found.map(fn(e) { (e.at, e.kind, e.verdict) }), [
    ("/roundTripCases/0/canonical/uppercase", Name, Accepted),
    ("/legacyDecodeCases/0/canonical/uppercase", Name, Accepted),
    ("/legacyDecodeCases/0/legacyArray", Name, Accepted),
    ("/rejectCases/0/input", Name, Rejected("invalid_name")),
    ("/rejectCases/1/input", Name, Accepted),
    ("/pathCases/0/canonical/uppercase", Path, Accepted),
    ("/fqNameCases/0/canonical/uppercase", FQName, Accepted),
  ])
}

///|
test "quotes name the two lesson 39 values and the start values of lessons 40 and 41" {
  assert_eq(quotes.map(fn(q) { q.lesson + "/" + q.case_ + "/" + q.file }), [
    "39-morphir-limits/start/deal.json", "39-morphir-limits/v3/deal.json", "40-morphir-profiles/start/deal.json",
    "41-morphir-version-3/start/append.json",
  ])
}

///|
test "inputTypes gives one example for each entry" {
  let document : Json = {
    "def": { "inputTypes": { "a": "x", "b/c": { "Unit": {} } } },
  }
  assert_eq(file_examples("f.json", document).map(fn(e) { e.at }), [
    "/def/inputTypes/a", "/def/inputTypes/b~1c",
  ])
}

///|
test "a reject case without validAs is rejected" {
  let corpus : Json = { "rejectCases": [{ "input": "Usd" }] }
  assert_eq(naming_examples("n.json", corpus).map(fn(e) { e.verdict }), [
    Rejected("invalid_name"),
  ])
}

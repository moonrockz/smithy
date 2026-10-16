///|
fn round_trip(text : String) -> @json_ast.JsonAst raise {
  let value = @json.parse(text)
  let document = @json_ast.decode(value)
  assert_eq(@json_ast.encode(document), value)
  assert_eq(@json_ast.parse(@json_ast.stringify(document)), document)
  document
}

///|
test "duplicate keys, escaped strings and nested values retain core JSON behavior" {
  let text =
    #|{"smithy":"2","metadata":{"value":{"old":99},"value":[0.10000000000000000001,{"quoted\"key":"\\\"123😀","number":-0.00000000000000000001e-1000}],"text":"1.2345","emoji":"\ud83d\ude00"}}
  let document = @json_ast.parse(text)
  assert_eq(@json_ast.encode(document), @json.parse(text))
  let encoded = @json_ast.stringify(document)
  assert_true(encoded.contains("0.10000000000000000001"))
  assert_true(encoded.contains("-0.00000000000000000001e-1000"))
  assert_true(!encoded.contains("old"))
  assert_eq(@json_ast.parse(encoded), document)
}

///|
test "deep metadata is parsed and emitted without a recursive codec walk" {
  let text = "{\"smithy\":\"2\",\"metadata\":{\"deep\":" +
    "[".repeat(900) +
    "1.0000000000000000001" +
    "]".repeat(900) +
    "}}"
  let encoded = @json_ast.stringify(@json_ast.parse(text))
  assert_true(encoded.contains("1.0000000000000000001"))
}

///|
test "law: arbitrary input either decodes or raises an error without panicking" {
  @quickcheck.check(
    (text : String) => {
      try @json_ast.parse(text) |> ignore catch {
        _ => ()
      }
      true
    },
    count=300,
    max_size=30,
    seed=5032,
  )
}

///|
test "callers can construct every payload through the public API" {
  let reference = @json_ast.JsonReference::new("smithy.api#String")
  let member_ = @json_ast.JsonMember::new(reference.target)
  let document = @json_ast.JsonAst::new(shapes={
    "example.test#Names": @json_ast.JsonShape::new(List(Some(member_))),
    "example.test#Get": @json_ast.JsonShape::new(
      Operation(@json_ast.JsonOperation::new(input=reference)),
    ),
    "example.test#Service": @json_ast.JsonShape::new(
      Service(@json_ast.JsonService::new(version="v1")),
    ),
    "example.test#Resource": @json_ast.JsonShape::new(
      Resource(@json_ast.JsonResource::new(properties={ "name": reference })),
    ),
  })
  assert_eq(@json_ast.decode(@json.to_json(document)), document)
  let shape : @json_ast.JsonShape = @json.from_json({ "type": "string" })
  assert_eq(@json.to_json(shape), { "type": "string" })
  let decoded_reference : @json_ast.JsonReference = @json.from_json(
    @json.to_json(reference),
  )
  assert_eq(decoded_reference, reference)
  let decoded_member : @json_ast.JsonMember = @json.from_json(
    @json.to_json(member_),
  )
  assert_eq(decoded_member, member_)
}

///|
fn error_at(text : String, expected : String) -> Unit raise {
  try @json_ast.parse(text) |> ignore catch {
    @json.JsonDecodeError((path, _)) => assert_eq(path.to_string(), expected)
    other => fail("wrong error: \{other}")
  } noraise {
    _ => fail("expected a decode error at \{expected}")
  }
}

///|
test "documents preserve absence, explicit emptiness, and version spelling" {
  let empty = round_trip("{\"smithy\":\"2\"}")
  assert_eq(empty.smithy, "2")
  assert_eq(empty.metadata, None)
  assert_eq(empty.shapes, None)
  let explicit = round_trip(
    "{\"smithy\":\"2.0\",\"metadata\":{},\"shapes\":{}}",
  )
  assert_eq(explicit.metadata, Some({}))
  assert_eq(explicit.shapes, Some({}))
  // Version support is a loader decision; this codec preserves the string.
  round_trip("{\"smithy\":\"3.7\"}") |> ignore
}

///|
test "all thirteen simple types and legacy sets round trip" {
  for
    keyword in [
      "blob", "boolean", "document", "string", "byte", "short", "integer", "long",
      "float", "double", "bigInteger", "bigDecimal", "timestamp",
    ] {
    let document = round_trip(
      "{\"smithy\":\"2.0\",\"shapes\":{\"test.example#Value\":{\"type\":\"\{keyword}\"}}}",
    )
    let shape = document.shapes.unwrap().get("test.example#Value").unwrap()
    assert_eq(shape.kind.keyword(), keyword)
    assert_true(shape.kind is Simple(_))
  }
  round_trip(
    (
      #|{"smithy":"1.0","shapes":{"test.example#Values":{"type":"set","member":{"target":"smithy.api#String"}}}}
    ),
  )
  |> ignore
}

///|
test "aggregate members, enum values, apply entries and mixins round trip" {
  let document = round_trip(
    (
      #|{
      #|  "smithy": "2.0",
      #|  "metadata": {"nested": [true, false, null, {"key": "value"}]},
      #|  "shapes": {
      #|    "test.example#Names": {"type": "list", "member": {"target": "smithy.api#String", "traits": {"smithy.api#required": {}}}},
      #|    "test.example#Lookup": {"type": "map", "key": {"target": "smithy.api#String"}, "value": {"target": "smithy.api#Integer"}},
      #|    "test.example#Data": {"type": "structure", "members": {"z": {"target": "smithy.api#String"}, "a": {"target": "smithy.api#Boolean"}}, "traits": {}, "mixins": [{"target": "test.example#Base"}]},
      #|    "test.example#Choice": {"type": "union", "members": {"name": {"target": "smithy.api#String"}}},
      #|    "test.example#Color": {"type": "enum", "members": {"RED": {"target": "smithy.api#Unit", "traits": {"smithy.api#enumValue": "red"}}}},
      #|    "test.example#Status": {"type": "intEnum", "members": {"OK": {"target": "smithy.api#Unit", "traits": {"smithy.api#enumValue": 200}}}},
      #|    "test.example#Base": {"type": "structure", "members": {}, "traits": {"smithy.api#mixin": {}}},
      #|    "test.example#Data$z": {"type": "apply", "traits": {"smithy.api#documentation": "A name"}}
      #|  }
      #|}
    ),
  )
  let shape = document.shapes.unwrap().get("test.example#Data").unwrap()
  guard shape.kind is Structure(Some(ms)) else { fail("expected members") }
  assert_eq(ms.keys().to_array(), ["z", "a"])
  assert_eq(shape.mixins.unwrap()[0].target, "test.example#Base")
}

///|
test "operation service and every resource property round trip" {
  let document = round_trip(
    (
      #|{
      #|  "smithy": "2.0",
      #|  "shapes": {
      #|    "test.example#Get": {
      #|      "type": "operation", "input": {"target": "test.example#Input"},
      #|      "output": {"target": "test.example#Output"}, "errors": [{"target": "test.example#Error"}], "mixins": []
      #|    },
      #|    "test.example#Service": {
      #|      "type": "service", "version": "2026-10-16", "operations": [{"target": "test.example#Get"}],
      #|      "resources": [{"target": "test.example#Resource"}], "errors": [], "rename": {"other.example#Get": "OtherGet"}
      #|    },
      #|    "test.example#Resource": {
      #|      "type": "resource", "identifiers": {"id": {"target": "smithy.api#String"}}, "properties": {"size": {"target": "smithy.api#Integer"}},
      #|      "create": {"target": "test.example#Create"}, "put": {"target": "test.example#Put"},
      #|      "read": {"target": "test.example#Get"}, "update": {"target": "test.example#Update"},
      #|      "delete": {"target": "test.example#Delete"}, "list": {"target": "test.example#List"},
      #|      "operations": [], "collectionOperations": [{"target": "test.example#Batch"}], "resources": []
      #|    }
      #|  }
      #|}
    ),
  )
  guard document.shapes.unwrap().get("test.example#Get").unwrap().kind
    is Operation(op) else {
    fail("expected operation")
  }
  assert_eq(op.input.unwrap().target, "test.example#Input")
  // References need not resolve inside an individual document.
  assert_eq(op.errors.unwrap()[0].target, "test.example#Error")
}

///|
test "unflattened shapes retain omitted fields and explicit empty members" {
  for
    keyword in [
      "list", "set", "map", "structure", "union", "enum", "intEnum", "operation",
      "service", "resource",
    ] {
    round_trip(
      "{\"smithy\":\"2\",\"shapes\":{\"test.example#Derived\":{\"type\":\"\{keyword}\",\"mixins\":[{\"target\":\"test.example#Base\"}]}}}",
    )
    |> ignore
  }
  round_trip(
    (
      #|{"smithy":"2","shapes":{"test.example#Empty":{"type":"structure","members":{},"traits":{},"mixins":[]}}}
    ),
  )
  |> ignore
  round_trip(
    (
      #|{"smithy":"2","shapes":{"test.example#Empty":{"type":"apply"}}}
    ),
  )
  |> ignore
}

///|
test "exact numeric spellings survive metadata and trait values" {
  let text =
    #|{"smithy":"2","metadata":{"big":9007199254740993,"decimal":0.12345678901234567890123456789,"exp":1e1000},"shapes":{"test.example#Number":{"type":"bigDecimal","traits":{"smithy.api#default":123456789012345678901234567890}}}}
  let encoded = @json_ast.stringify(@json_ast.parse(text))
  for
    spelling in [
      "9007199254740993", "0.12345678901234567890123456789", "1e1000", "123456789012345678901234567890",
    ] {
    if !encoded.contains(spelling) {
      fail("lost numeric spelling \{spelling}: \{encoded}")
    }
  }
}

///|
test "decode errors locate missing fields and reject null, wrong types and unknown properties" {
  for
    (text, path) in [
      ("[]", ""),
      ("{}", "/smithy"),
      ("{\"smithy\":2}", "/smithy"),
      ("{\"smithy\":\"2\",\"metadata\":null}", "/metadata"),
      ("{\"smithy\":\"2\",\"shapes\":[]}", "/shapes"),
      ("{\"smithy\":\"2\",\"extra\":true}", "/extra"),
      ("{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{}}}", "/shapes/x.y#S/type"),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"unknown\"}}}", "/shapes/x.y#S/type",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"list\",\"member\":{}}}}",
        "/shapes/x.y#S/member/target",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"list\",\"member\":null}}}",
        "/shapes/x.y#S/member",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"string\",\"members\":{}}}}",
        "/shapes/x.y#S/members",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"apply\",\"mixins\":[]}}}",
        "/shapes/x.y#S/mixins",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"operation\",\"errors\":[{\"target\":\"String\"}]}}}",
        "/shapes/x.y#S/errors/0/target",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"resource\",\"collectionOperations\":[{\"target\":false}]}}}",
        "/shapes/x.y#S/collectionOperations/0/target",
      ),
      (
        "{\"smithy\":\"2\",\"shapes\":{\"x.y#S\":{\"type\":\"service\",\"version\":null}}}",
        "/shapes/x.y#S/version",
      ),
    ] {
    error_at(text, path)
  }
}

///|
test "absolute identifiers and member names are checked without resolving references" {
  for
    id in [
      "Name", "#Name", "x..y#Name", "x.y#", "x.y#Name$", "x.y#Name$x$y", "x.y#1Name",
      "x.y#Name#Other", "é#Name", "x.y#Na/me",
    ] {
    let shapes : Map[String, Json] = Map([])
    shapes[id] = { "type": "string" }
    let fields : Map[String, Json] = {
      "smithy": "2",
      "shapes": Json::object(shapes),
    }
    error_at(
      Json::object(fields).stringify(),
      "/shapes/" +
      id.replace_all(old="~", new="~0").replace_all(old="/", new="~1"),
    )
  }
  error_at(
    (
      #|{"smithy":"2","shapes":{"x.y#S":{"type":"string","traits":{"required":{}}}}}
    ),
    "/shapes/x.y#S/traits/required",
  )
  error_at(
    (
      #|{"smithy":"2","shapes":{"x.y#S":{"type":"structure","members":{"not-valid":{"target":"smithy.api#String"}}}}}
    ),
    "/shapes/x.y#S/members/not-valid",
  )
  error_at(
    (
      #|{"smithy":"2","shapes":{"x.y#S":{"type":"service","rename":{"x.y#Other":"not-valid"}}}}
    ),
    "/shapes/x.y#S/rename/x.y#Other",
  )
}

///|
test "malformed JSON and excessive nesting raise core parse errors" {
  for
    text in [
      "{",
      "{\"smithy\":\"2\",}",
      "[".repeat(1100) + "0" + "]".repeat(1100),
    ] {
    try @json_ast.parse(text) |> ignore catch {
      @json.InvalidChar(_, _)
      | @json.InvalidEof
      | @json.InvalidNumber(_, _)
      | @json.InvalidIdentEscape(_)
      | @json.DepthLimitExceeded => ()
      other => fail("wrong error: \{other}")
    } noraise {
      _ => fail("expected a JSON syntax error")
    }
  }
}

///|
test "law: arbitrary metadata and traits round trip without changing values" {
  @quickcheck.check(
    (values : (Array[String], Int32, Bool)) => {
      let (strings, number, flag) = values
      let value : Json = {
        "strings": @json.to_json(strings),
        "number": @json.to_json(number),
        "flag": @json.to_json(flag),
        "nil": Json::null(),
      }
      let document : @json_ast.JsonAst = {
        smithy: "2.0",
        metadata: Some({ "value": value }),
        shapes: Some({
          "test.example#Value": {
            kind: Simple(Document),
            traits: Some({ "test.example#trait": value }),
            mixins: None,
          },
        }),
      }
      @json_ast.parse(@json_ast.stringify(document)) == document
    },
    count=300,
    max_size=20,
    seed=5031,
  )
}

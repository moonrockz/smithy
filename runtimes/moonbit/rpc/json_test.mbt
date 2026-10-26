///|
test "parse and write keep the exact text of every number" {
  let text = "{\"a\":20.00,\"b\":12345678901234567.00,\"c\":-0.0e+10,\"d\":9007199254740993,\"e\":[1,2.50,1E400]}"
  let json = @rpc.parse_json(text)
  inspect(@rpc.write_json(json), content=text)
}

///|
test "a big integer does not go through a Double" {
  let json = @rpc.parse_json("9007199254740993")
  guard json is Number(_, repr=Some(text)) else { fail("I expected a number") }
  inspect(text, content="9007199254740993")
}

///|
test "write removes whitespace and keeps member order" {
  let json = @rpc.parse_json(
    " { \"z\" : 1 , \"a\" : [ true , false , null ] , \"m\" : { } , \"n\" : [ ] } ",
  )
  inspect(
    @rpc.write_json(json),
    content="{\"z\":1,\"a\":[true,false,null],\"m\":{},\"n\":[]}",
  )
}

///|
test "strings escape and unescape" {
  let json = @rpc.parse_json(
    "\"a\\\"b\\\\c\\/d\\n\\t\\u0001\\u00e9\\ud83d\\ude00\"",
  )
  assert_true(json is String(s) && s == "a\"b\\c/d\n\t\u{01}é😀")
  inspect(@rpc.write_json(json), content="\"a\\\"b\\\\c/d\\n\\t\\u0001é😀\"")
}

///|
test "numbers without repr are written as JSON numbers" {
  inspect(@rpc.write_json(Json::number(3.0)), content="3")
  inspect(@rpc.write_json(Json::number(0.5)), content="0.5")
  inspect(@rpc.write_json(Json::number(0.0 / 0.0)), content="null")
}

///|
test "deep nesting does not overflow the stack" {
  let depth = 100000
  let text = "[".repeat(depth) + "]".repeat(depth)
  let json = @rpc.parse_json(text, max_depth=depth)
  inspect(@rpc.write_json(json) == text, content="true")
}

///|
test "the nesting depth is limited" {
  let at_limit = "[".repeat(@rpc.max_json_depth) +
    "]".repeat(@rpc.max_json_depth)
  inspect(
    @rpc.write_json(@rpc.parse_json(at_limit)) == at_limit,
    content="true",
  )
  let deeper = "{\"next\":".repeat(@rpc.max_json_depth) +
    "[]" +
    "}".repeat(@rpc.max_json_depth)
  let message = try @rpc.parse_json(deeper) |> ignore catch {
    DecodeError(message~, ..) => message
  } noraise {
    _ => "no error"
  }
  inspect(
    message,
    content="I expected at most 1000 nested arrays and objects at offset 8000 of the JSON text, found '['.",
  )
}

///|
test "parse errors name the construct and what was found" {
  let cases = [
    "", "{", "[1,]", "{\"a\" 1}", "01", "1.", "tru", "\"abc", "[1] x", "{\"a\":1,}",
    "\"\\q\"", "-",
  ]
  let messages = cases.map(text => {
    try @rpc.parse_json(text) catch {
      DecodeError(message~, ..) => message
    } noraise {
      _ => "no error"
    }
  })
  inspect(
    messages.join("\n"),
    content=(
      #|I expected a JSON value at offset 0 of the JSON text, found the end of the input.
      #|I expected a quoted member name at offset 1 of the JSON text, found the end of the input.
      #|I expected a JSON value at offset 3 of the JSON text, found ']'.
      #|I expected ':' after the member name at offset 5 of the JSON text, found '1'.
      #|I expected the end of the input after the JSON value at offset 1 of the JSON text, found '1'.
      #|I expected a JSON number at offset 0 of the JSON text, found '1'.
      #|I expected the literal true at offset 0 of the JSON text, found 't'.
      #|I expected a closing quote of the string at offset 4 of the JSON text, found the end of the input.
      #|I expected the end of the input after the JSON value at offset 4 of the JSON text, found 'x'.
      #|I expected a quoted member name at offset 7 of the JSON text, found '}'.
      #|I expected an escape character after a backslash at offset 2 of the JSON text, found 'q'.
      #|I expected a JSON number at offset 0 of the JSON text, found '-'.
    ),
  )
}

///|
fn show_json(json : Json?) -> String {
  match json {
    Some(value) => @rpc.write_json(value)
    None => "absent"
  }
}

///|
test "resolve a JSON pointer" {
  let json = @rpc.parse_json(
    "{\"capabilities\":{\"payment\":true,\"a/b\":[0,{\"x\":null}]}}",
  )
  inspect(
    show_json(@rpc.resolve_pointer(json, "/capabilities/payment")),
    content="true",
  )
  inspect(
    show_json(@rpc.resolve_pointer(json, "/capabilities/a~1b/1/x")),
    content="null",
  )
  inspect(
    show_json(@rpc.resolve_pointer(json, "/capabilities/none")),
    content="absent",
  )
  inspect(
    show_json(@rpc.resolve_pointer(json, "/capabilities/a~1b/01")),
    content="absent",
  )
  inspect(@rpc.child_path("/a", "x/y~z"), content="/a/x~1y~0z")
}

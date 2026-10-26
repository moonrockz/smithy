///|
fn decode_message(f : () -> Unit raise @rpc.DecodeError) -> String {
  try f() catch {
    DecodeError(path~, message~) => "\{path}: \{message}"
  } noraise {
    _ => "no error"
  }
}

///|
test "a decimal keeps its exact text" {
  let json = @rpc.parse_json("{\"amount\":12345678901234567.00}")
  let fields = @rpc.object_of(json, path="")
  let amount = @rpc.Decimal::from_json(
    @rpc.required(fields, "amount", path=""),
    path="/amount",
  )
  inspect(amount, content="12345678901234567.00")
  inspect(@rpc.write_json(amount.to_json()), content="12345678901234567.00")
  inspect(@rpc.Decimal::parse("2.50").unwrap(), content="2.50")
  assert_true(@rpc.Decimal::parse("2.") is None)
}

///|
test "decimals compare by exact value" {
  let d = (text : String) => @rpc.Decimal::parse(text).unwrap()
  inspect(
    d("12345678901234568.00").compare_value(d("12345678901234567.00")),
    content="1",
  )
  inspect(d("2.50").compare_value(d("2.5")), content="0")
  inspect(d("2.50") == d("2.5"), content="false")
  inspect(d("-1").compare_value(d("0.5")), content="-1")
  inspect(d("0.00").compare_value(d("-0")), content="0")
  inspect(d("1e3").compare_value(d("999.99")), content="1")
  inspect(d("-20.13").compare_value(d("-20.14")), content="1")
}

///|
test "a big integer and an Int64 keep their exact text" {
  let big = @rpc.BigInteger::from_json(
    @rpc.parse_json("900719925474099312345"),
    path="",
  )
  inspect(@rpc.write_json(big.to_json()), content="900719925474099312345")
  let long = @rpc.decode_int64(@rpc.parse_json("9007199254740993"), path="")
  inspect(long, content="9007199254740993")
  inspect(@rpc.write_json(@rpc.encode_int64(long)), content="9007199254740993")
  inspect(
    decode_message(() => {
      @rpc.decode_int64(@rpc.parse_json("9223372036854775808"), path="/n")
      |> ignore
    }),
    content="/n: I expected a 64-bit integer, found 9223372036854775808, which is out of range.",
  )
  inspect(
    decode_message(() => {
      @rpc.decode_int(@rpc.parse_json("1.5"), path="/n") |> ignore
    }),
    content="/n: I expected a 32-bit integer, found the number 1.5.",
  )
}

///|
test "scalar decoders name the path and the value found" {
  inspect(
    decode_message(() => {
      @rpc.decode_string(Json::boolean(true), path="/a") |> ignore
    }),
    content="/a: I expected a string, found a boolean.",
  )
  inspect(
    decode_message(() => {
      let obj = @rpc.object_of(@rpc.parse_json("{}"), path="/p")
      @rpc.required(obj, "x", path="/p") |> ignore
    }),
    content="/p/x: I expected the required member x, found nothing.",
  )
  inspect(@rpc.decode_bool(Json::boolean(false), path=""), content="false")
  inspect(
    @rpc.decode_double(Json::string("-Infinity"), path=""),
    content="-Infinity",
  )
}

///|
test "a blob is base64 text" {
  let json = @rpc.encode_blob(b"test-signature")
  inspect(@rpc.write_json(json), content="\"dGVzdC1zaWduYXR1cmU=\"")
  inspect(@rpc.decode_blob(json, path="") == b"test-signature", content="true")
  inspect(
    decode_message(() => {
      @rpc.decode_blob(Json::string("@@"), path="/s") |> ignore
    }),
    content="/s: I expected base64 text, found '@@'.",
  )
}

///|
test "a timestamp keeps its JSON value" {
  let t = @rpc.Timestamp::from_json(
    @rpc.parse_json("1700000000.50"),
    format=EpochSeconds,
    path="",
  )
  inspect(@rpc.write_json(t.to_json()), content="1700000000.50")
  let d = @rpc.Timestamp::from_json(
    Json::string("1985-04-12T23:20:50.52Z"),
    format=DateTime,
    path="",
  )
  inspect(d, content="\"1985-04-12T23:20:50.52Z\"")
  inspect(
    decode_message(() => {
      @rpc.Timestamp::from_json(
        Json::string("yesterday"),
        format=DateTime,
        path="/t",
      )
      |> ignore
    }),
    content="/t: I expected a date-time timestamp such as 1985-04-12T23:20:50.52Z, found 'yesterday'.",
  )
}

///|
test "request IDs keep their text exactly" {
  let big = @rpc.RequestId::from_json(@rpc.parse_json("900719925474099312345"))
  inspect(big.unwrap(), content="900719925474099312345")
  inspect(
    @rpc.write_json(big.unwrap().to_json()),
    content="900719925474099312345",
  )
  let text = @rpc.RequestId::from_json(Json::string("payment-1"))
  inspect(@rpc.write_json(text.unwrap().to_json()), content="\"payment-1\"")
  assert_true(@rpc.RequestId::from_json(@rpc.parse_json("1.5")) is None)
  assert_true(@rpc.RequestId::from_json(Json::null()) is None)
  inspect(
    @rpc.RequestId::Number("1") == @rpc.RequestId::Text("1"),
    content="false",
  )
}

///|
test "lists, maps and unions" {
  let json = @rpc.parse_json("{\"b\":1,\"a\":2}")
  let map = @rpc.decode_map(json, path="", (v, p) => @rpc.decode_int(v, path=p))
  inspect(map.to_array().map(p => "\{p.0}=\{p.1}").join(","), content="b=1,a=2")
  let encoded = @rpc.encode_map(map, @rpc.encode_int)
  inspect(@rpc.write_json(encoded), content="{\"b\":1,\"a\":2}")
  inspect(
    decode_message(() => {
      @rpc.decode_array(@rpc.parse_json("[1,\"x\"]"), path="/l", (v, p) => {
        @rpc.decode_int(v, path=p)
      })
      |> ignore
    }),
    content="/l/1: I expected a 32-bit integer, found a string.",
  )
  let (name, _) = @rpc.union_member(
    @rpc.parse_json(
      "{\"chip\":{\"maskedNumber\":\"**** 4242\"},\"swipe\":null}",
    ),
    path="/entry",
  )
  inspect(name, content="chip")
  inspect(
    decode_message(() => {
      @rpc.union_member(@rpc.parse_json("{\"a\":1,\"b\":2}"), path="/u")
      |> ignore
    }),
    content="/u: I expected one union member that is not null, found 2: a, b.",
  )
  inspect(
    decode_message(() => {
      @rpc.reject_unknown(
        @rpc.object_of(@rpc.parse_json("{\"a\":1,\"z\":2}"), path=""),
        ["a"],
        path="/s",
      )
    }),
    content="/s/z: I expected only declared members, found the unknown member z.",
  )
}

///|
test "named and positional params" {
  inspect(
    @rpc.write_json(@rpc.named_params(None, path="/params")),
    content="{}",
  )
  inspect(
    decode_message(() => {
      @rpc.named_params(Some(@rpc.parse_json("[1]")), path="/params") |> ignore
    }),
    content="/params: I expected named params (an object), found an array.",
  )
  let names = ["a", "b", "c"]
  let obj = @rpc.positional_params(
    Some(@rpc.parse_json("[1,2]")),
    names,
    either=false,
    path="/params",
  )
  inspect(@rpc.write_json(obj), content="{\"a\":1,\"b\":2}")
  inspect(
    decode_message(() => {
      @rpc.positional_params(
        Some(@rpc.parse_json("[1,2,3,4]")),
        names,
        either=false,
        path="/params",
      )
      |> ignore
    }),
    content="/params/3: I expected at most 3 positional params, found 4.",
  )
  inspect(
    @rpc.write_json(
      @rpc.to_positional(@rpc.parse_json("{\"c\":3,\"a\":1}"), names),
    ),
    content="[1,null,3]",
  )
  inspect(
    @rpc.write_json(@rpc.to_positional(@rpc.parse_json("{\"a\":1}"), names)),
    content="[1]",
  )
}

///|
test "a required member may be null; only an absent member is an error" {
  let fields = @rpc.object_of(@rpc.parse_json("{\"id\":null}"), path="/params")
  // A Document member keeps the null value.
  assert_true(@rpc.required(fields, "id", path="/params") is Null)
  inspect(
    decode_message(() => {
      @rpc.required(fields, "other", path="/params") |> ignore
    }),
    content="/params/other: I expected the required member other, found nothing.",
  )
  // A typed member rejects the null value with its own decoder.
  inspect(
    decode_message(() => {
      @rpc.decode_string(
        @rpc.required(fields, "id", path="/params"),
        path="/params/id",
      )
      |> ignore
    }),
    content="/params/id: I expected a string, found null.",
  )
}

///|
fn bad_adapter(
  name : String,
  read : (Json, @codec.AdapterContext) -> Result[
    @codec.ScalarValue,
    @codec.AdapterFailure,
  ],
) -> @codec.ScalarAdapter raise {
  @codec.ScalarAdapter::new(
    @contract.AdapterId::parse(name),
    inputs=[StringKind],
    output=StringKind,
    read~,
    write=(value, _) => {
      match value {
        Text(text) => Ok(Json::string(text))
        _ => Err(@codec.AdapterFailure::new("text"))
      }
    },
  )
}

///|
test "failing, malformed and expanding adapters cannot produce values" {
  let registry = @codec.AdapterRegistry::new()
    .register(
      bad_adapter("test.fails", (_, _) => {
        Err(@codec.AdapterFailure::new("I refuse."))
      }),
    )
    .register(
      bad_adapter("test.kind", (_, _) => {
        Ok(Numeric(@smithy.NodeNumber::parse("1").unwrap()))
      }),
    )
    .register(
      bad_adapter("test.greedy", (value, context) => {
        // An adapter that charges for an expansion larger than the request allows.
        if context.charge(1000000) {
          match value {
            String(text) => Ok(Text(text))
            _ => Err(@codec.AdapterFailure::new("text"))
          }
        } else {
          Err(@codec.AdapterFailure::new("I ran out of work."))
        }
      }),
    )
  let model = load(
    header +
    "structure R {\n" +
    "  @jsonEncoding(base: {adapter: \"test.fails\"}) a: String\n" +
    "  @jsonEncoding(base: {adapter: \"test.kind\"}) b: String\n" +
    "  @jsonEncoding(base: {adapter: \"test.greedy\"}) c: String\n" +
    "}",
  )
  let codec = @codec.PreparedCodec::prepare(
    model,
    id("example#R"),
    adapters=registry,
    limits=@codec.CodecLimits::new(work=1000),
  )
  let fails = codec.check("{\"a\":\"x\"}")
  assert_eq(fails.findings[0].code, AdapterFailure)
  assert_eq(fails.findings[0].path.pointer(), "/a")
  assert_eq(codec.check("{\"b\":\"x\"}").findings[0].code, AdapterFailure)
  let greedy = codec.check("{\"c\":\"x\"}")
  assert_false(greedy.complete)
  assert_eq(
    failure(() => ignore(codec.decode("{\"c\":\"x\"}"))).complete,
    false,
  )
}

///|
/// The laws that every representation keeps: a complete valid check agrees with decoding, decoding the
/// encoding gives the value back, canonical output is a fixed point, and another profile of the same root
/// writes a value that decodes to the same logical value.
fn check_laws(
  codecs : Array[@codec.PreparedCodec],
  inputs : Array[String],
) -> Unit raise {
  for codec in codecs {
    for text in inputs {
      let result = codec.check(text)
      let decoded = codec.decode(text) catch {
        @codec.CodecFailure(failed) => {
          assert_false(result.is_valid())
          assert_eq(failed, result)
          continue
        }
      }
      assert_true(result.is_valid())
      let encoded = codec.encode(decoded)
      assert_true(codec.decode(encoded) == decoded)
      assert_eq(codec.canonicalize(encoded), encoded)
      for other in codecs {
        let text = other.encode(decoded)
        assert_true(other.decode(text) == decoded)
        assert_true(codec.decode(codec.encode(other.decode(text))) == decoded)
      }
    }
  }
}

///|
test "laws across object, array, compact and expanded representations" {
  let expr = load(expr_model)
  check_laws(
    ["object", "array"].map(p => {
      @codec.PreparedCodec::prepare(
        expr,
        id("example#Expr"),
        profile=Some(profile(p)),
      ) catch {
        _ => panic()
      }
    }),
    [
      "{\"Add\":{\"left\":{\"Num\":1},\"right\":{\"Num\":2}}}", "[\"Add\",[\"Num\",1],[\"Num\",2]]",
      "[\"Add\",[\"Num\",1],[\"Num\",200]]", "{\"Num\":3}", "[\"Num\"]",
    ],
  )
  let shapes = load(shapes_model)
  check_laws(
    ["external", "internal", "adjacent", "mixed"].map(p => {
      @codec.PreparedCodec::prepare(
        shapes,
        id("example#Doc"),
        profile=Some(profile(p)),
      ) catch {
        _ => panic()
      }
    }),
    [
      "{\"op\":{\"Add\":{\"left\":1,\"right\":2}},\"id\":\"x\"}", "{\"op\":{\"kind\":\"neg\",\"v\":4},\"id\":7}",
      "{\"op\":{\"t\":\"Stop\"}}", "{\"op\":{\"kind\":\"Stop\"}}", "{\"op\":{\"Stop\":{}},\"id\":1.5}",
    ],
  )
  check_laws(
    ["compact", "expanded"].map(p => type_codec(p) catch { _ => panic() }),
    [
      "\"a\"", "{\"Variable\":{\"attrs\":{},\"name\":[\"a\",\"b\"]}}", "[\"x:y\",{\"Reference\":[\"x:z\",\"q\"]}]",
      "{\"Reference\":{\"fqname\":\"x:z\",\"attributes\":{\"source\":\"s\"}}}", "{\"Tuple\":{\"elements\":[]}}",
      "\"bad:\"",
    ],
  )
  let tables = load(dictionary_model)
  check_laws(
    ["entries", "object"].map(p => {
      @codec.PreparedCodec::prepare(
        tables,
        id("example#Fields"),
        profile=Some(profile(p)),
        adapters=registry(),
      ) catch {
        _ => panic()
      }
    }),
    [
      "[[[\"b\",\"c\"],1],[\"z\",2]]", "{\"a\":1,\"b-c\":2}", "[[\"a\",1],[\"a\",2]]",
    ],
  )
}

///|
test "caller-built values follow the same laws" {
  let compact = type_codec("compact")
  let expanded = type_codec("expanded")
  let built = compact.value(
    Union(
      "Reference",
      Structure([
        ("fqname", String("x:list")),
        (
          "args",
          List([
            Union(
              "Variable",
              Structure([("name", String("a")), ("attributes", Structure([]))]),
            ),
          ]),
        ),
      ]),
    ),
  )
  assert_eq(compact.encode(built), "{\"Reference\":[\"x:list\",\"a\"]}")
  assert_true(compact.decode(compact.encode(built)) == built)
  assert_true(expanded.decode(expanded.encode(built)) == built)
}

///|
test "review regressions: empty members, accepted dictionary kinds and sparse nulls" {
  // A present empty member without @emptyAsAbsent keeps the expanded form.
  let compact = type_codec("compact")
  let text = "{\"Reference\":{\"fqname\":\"x:y\",\"args\":[]}}"
  let value = compact.decode(text)
  assert_eq(compact.encode(value), text)
  assert_true(compact.decode(compact.encode(value)) == value)
  assert_eq(
    compact.canonicalize("{\"Reference\":{\"fqname\":\"x:y\"}}"),
    "\"x:y\"",
  )
  // An untagged union sees both layouts of a dictionary that accepts the other layout.
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {dictionary: {layout: \"object\", accept: [\"entries\"]}})\nmap D { key: String, value: String }\nlist L { member: String }\n@untagged union U { d: D, l: L }",
      "example#U",
      None,
    ),
    content="InvalidDeclaration: example#U: Untagged members d and l both accept JSON array values.",
  )
  // Null elements of sparse lists and maps are kept, whatever their target layout.
  let model = load(
    header +
    "@sparse list Items { member: Dict }\nmap Dict { key: String, value: String }\n@sparse map Opts { key: String, value: U }\nunion U { a: String }\nstructure R { items: Items, opts: Opts }",
  )
  let codec = @codec.PreparedCodec::prepare(model, id("example#R"))
  let sparse = "{\"items\":[null,{\"k\":\"v\"}],\"opts\":{\"x\":null,\"y\":{\"a\":\"b\"}}}"
  assert_eq(codec.canonicalize(sparse), sparse)
  let built = codec.value(Structure([("items", List([Null]))]))
  assert_eq(codec.encode(built), "{\"items\":[null]}")
  // A dense list still refuses null.
  let dense = @codec.PreparedCodec::prepare(
    load(header + "list L { member: String }\nstructure R { l: L }"),
    id("example#R"),
  )
  assert_false(dense.check("{\"l\":[null]}").is_valid())
}

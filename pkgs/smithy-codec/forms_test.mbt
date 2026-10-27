///|
/// A test name adapter: reads "a-b" or ["a","b"], writes "a-b". Keys order by word count, then text.
fn words_adapter() -> @codec.ScalarAdapter raise {
  @codec.ScalarAdapter::new(
    @contract.AdapterId::parse("test.words"),
    inputs=[StringKind, ArrayKind],
    output=StringKind,
    read=(value, context) => {
      ignore(context.charge(1))
      match value {
        String(text) =>
          if text.length() > 0 && !text.contains(":") {
            Ok(Text(text))
          } else {
            Err(@codec.AdapterFailure::new("I expected words without ':'."))
          }
        Array(items) => {
          let words : Array[String] = []
          for i, item in items {
            guard item is String(word) && word.length() > 0 else {
              return Err(
                @codec.AdapterFailure::new(
                  "I expected a word.",
                  path=@validation.InstancePath::root().index(i) catch {
                    _ => @validation.InstancePath::root()
                  },
                ),
              )
            }
            words.push(word)
          }
          if words.is_empty() {
            Err(@codec.AdapterFailure::new("I expected at least one word."))
          } else {
            Ok(Text(words.join("-")))
          }
        }
        _ => Err(@codec.AdapterFailure::new("I expected words."))
      }
    },
    write=(value, _) => {
      match value {
        Text(text) => Ok(Json::string(text))
        _ => Err(@codec.AdapterFailure::new("I expected text."))
      }
    },
    compare=Some((a, b) => {
      let count = fn(s : String) { s.split("-").count() }
      if count(a) != count(b) {
        count(a).compare(count(b))
      } else {
        a.compare(b)
      }
    }),
  )
}

///|
/// A reference adapter: reads "pkg:name", rejects plain words.
fn reference_adapter() -> @codec.ScalarAdapter raise {
  @codec.ScalarAdapter::new(
    @contract.AdapterId::parse("test.ref"),
    inputs=[StringKind],
    output=StringKind,
    read=(value, _) => {
      match value {
        String(text) if text.contains(":") => Ok(Text(text))
        _ => Err(@codec.AdapterFailure::new("I expected pkg:name."))
      }
    },
    write=(value, _) => {
      match value {
        Text(text) => Ok(Json::string(text))
        _ => Err(@codec.AdapterFailure::new("I expected text."))
      }
    },
  )
}

///|
fn registry() -> @codec.AdapterRegistry raise {
  @codec.AdapterRegistry::new()
  .register(words_adapter())
  .register(reference_adapter())
}

///|
let type_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|use smithy.serialization#emptyAsAbsent
  #|
  #|@jsonProfiles([
  #|  {id: "compact"}
  #|  {id: "expanded", ruleSet: "compact", writer: "expanded"}
  #|])
  #|@jsonEncoding(base: {forms: [
  #|  {member: "Variable", read: {kind: "string", adapter: "test.words"}, bind: "name", write: {empty: ["attributes"]}}
  #|  {member: "Reference", read: {kind: "string", adapter: "test.ref"}, bind: "fqname", write: {empty: ["attributes", "args"]}}
  #|  {member: "Tuple", read: {kind: "array"}, bind: "elements", write: {empty: ["attributes"]}}
  #|]})
  #|union Type {
  #|  Variable: VariableType
  #|  Reference: ReferenceType
  #|  Tuple: TupleType
  #|}
  #|
  #|structure VariableType {
  #|  @emptyAsAbsent
  #|  @jsonEncoding(base: {aliases: ["attrs"]})
  #|  attributes: Attributes
  #|  @required
  #|  name: Name
  #|}
  #|
  #|@jsonEncoding(base: {forms: [
  #|  {read: {kind: "array"}, positions: ["fqname"], rest: "args", write: {empty: ["attributes"], present: ["args"]}}
  #|]})
  #|structure ReferenceType {
  #|  @emptyAsAbsent
  #|  attributes: Attributes
  #|  @required
  #|  @jsonEncoding(base: {adapter: "test.ref"})
  #|  fqname: String
  #|  args: TypeList
  #|}
  #|
  #|structure TupleType {
  #|  @emptyAsAbsent
  #|  attributes: Attributes
  #|  @required
  #|  elements: TypeList
  #|}
  #|
  #|list TypeList {
  #|  member: Type
  #|}
  #|
  #|structure Attributes {
  #|  source: String
  #|}
  #|
  #|@jsonEncoding(base: {adapter: "test.words"})
  #|@length(max: 20)
  #|string Name

///|
fn type_codec(name : String) -> @codec.PreparedCodec raise {
  @codec.PreparedCodec::prepare(
    load(type_model),
    id("example#Type"),
    profile=Some(profile(name)),
    adapters=registry(),
  )
}

///|
test "compact and expanded forms decode to equal values" {
  let compact = type_codec("compact")
  let expanded = type_codec("expanded")
  let a = compact.decode("\"a\"")
  let b = compact.decode("{\"Variable\":{\"name\":\"a\"}}")
  let c = compact.decode("{\"Variable\":{\"name\":[\"a\"],\"attributes\":{}}}")
  assert_true(a == b)
  assert_true(b == c)
  assert_eq(a.logical().selected().unwrap().0, "Variable")
  assert_eq(compact.encode(c), "\"a\"")
  assert_eq(expanded.encode(a), "{\"Variable\":{\"name\":\"a\"}}")
  // A string with ':' selects the reference form; arrays select tuples.
  let r = compact.decode("[\"x:list\",[\"x:int\"]]")
  assert_eq(r.logical().selected().unwrap().0, "Tuple")
  assert_eq(compact.encode(r), "[\"x:list\",[\"x:int\"]]")
  let wrapped = compact.decode("{\"Reference\":[\"x:list\",\"a\"]}")
  assert_eq(compact.encode(wrapped), "{\"Reference\":[\"x:list\",\"a\"]}")
  assert_eq(
    expanded.encode(wrapped),
    "{\"Reference\":{\"fqname\":\"x:list\",\"args\":[{\"Variable\":{\"name\":\"a\"}}]}}",
  )
  // Non-empty attributes select the expanded payload.
  let attributed = compact.decode(
    "{\"Variable\":{\"attrs\":{\"source\":\"s\"},\"name\":\"a\"}}",
  )
  assert_eq(
    compact.encode(attributed),
    "{\"Variable\":{\"attributes\":{\"source\":\"s\"},\"name\":\"a\"}}",
  )
  // Canonicalization is idempotent.
  for
    text in [
      "\"a-b\"", "[\"x:y\",{\"Reference\":[\"x:z\",\"q\"]}]", "{\"Tuple\":{\"elements\":[]}}",
    ] {
    let once = compact.canonicalize(text)
    assert_eq(compact.canonicalize(once), once)
  }
}

///|
test "alias collisions and invalid shorthand report the source location" {
  let compact = type_codec("compact")
  let collision = compact.check(
    "{\"Variable\":{\"attrs\":{},\"attributes\":{},\"name\":\"a\"}}",
  )
  assert_eq(collision.findings[0].code, MemberCollision)
  assert_eq(collision.findings[0].path.pointer(), "/Variable/attributes")
  let long = compact.check("[\"x:y\",\"aaaaaaaaaaaaaaaaaaaaaaaaaa\"]")
  assert_eq(long.findings[0].code, Constraint(Length))
  assert_eq(long.findings[0].path.pointer(), "/1")
  let bad_word = compact.check("{\"Variable\":{\"name\":[\"a\",3]}}")
  assert_eq(bad_word.findings[0].code, AdapterFailure)
  assert_eq(bad_word.findings[0].path.pointer(), "/Variable/name/1")
  let nested = compact.check(
    "{\"Reference\":[\"x:list\",[\"a\",\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"]]}",
  )
  assert_eq(nested.findings[0].path.pointer(), "/Reference/1/1")
}

///|
test "ambiguous compact input and overlapping declarations" {
  let both = @codec.ScalarAdapter::new(
    @contract.AdapterId::parse("test.any"),
    inputs=[StringKind],
    output=StringKind,
    read=(value, _) => {
      match value {
        String(text) => Ok(Text(text))
        _ => Err(@codec.AdapterFailure::new("text"))
      }
    },
    write=(value, _) => {
      match value {
        Text(text) => Ok(Json::string(text))
        _ => Err(@codec.AdapterFailure::new("text"))
      }
    },
  )
  let model = load(
    header +
    "@jsonEncoding(base: {forms: [\n" +
    "{member: \"A\", read: {kind: \"string\", adapter: \"test.any\"}, bind: \"name\"}\n" +
    "{member: \"B\", read: {kind: \"string\", adapter: \"test.words\"}, bind: \"name\"}\n" +
    "]})\nunion U { A: N, B: N }\nstructure N { @required name: String }",
  )
  let codec = @codec.PreparedCodec::prepare(
    model,
    id("example#U"),
    adapters=@codec.AdapterRegistry::new()
      .register(both)
      .register(words_adapter()),
  )
  let result = codec.check("\"word\"")
  assert_eq(result.findings[0].code, AmbiguousForm)
  assert_eq(codec.check("\"a:b\"").is_valid(), true)
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {forms: [{member: \"A\", read: {kind: \"string\"}, bind: \"name\"}, {member: \"B\", read: {kind: \"string\"}, bind: \"name\"}]})\nunion U { A: N, B: N }\nstructure N { @required name: String }",
      "example#U",
      None,
    ),
    content="InvalidDeclaration: example#U: Two string forms overlap without guards that tell them apart.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {forms: [{member: \"A\", read: {kind: \"object\"}, bind: \"name\"}]})\nunion U { A: N }\nstructure N { @required name: Document }",
      "example#U",
      None,
    ),
    content="InvalidDeclaration: example#U: A object form overlaps the shape's own object layout without a guard.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {forms: [{member: \"A\", read: {kind: \"string\"}, bind: \"name\", write: {}}]})\nunion U { A: N }\nstructure N { @required name: String, other: String }",
      "example#U",
      None,
    ),
    content="InvalidDeclaration: example#U: The form's writer would drop member other; list it as empty.",
  )
}

///|
let tuple_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|
  #|@jsonProfiles([{id: "arrays"}])
  #|@jsonEncoding(profiles: {arrays: {tuple: {members: ["name", "size", "note"], optional: "omit"}}})
  #|structure Entry {
  #|  @required
  #|  name: String
  #|  @required
  #|  size: Integer
  #|  note: String
  #|}
  #|
  #|@jsonEncoding(profiles: {arrays: {tuple: {members: ["head"], rest: "tail"}}})
  #|structure Call {
  #|  @required
  #|  head: String
  #|  tail: Entries
  #|}
  #|
  #|list Entries {
  #|  member: Entry
  #|}

///|
test "tuples with optional tails and rest lists" {
  let model = load(tuple_model)
  let entry = @codec.PreparedCodec::prepare(
    model,
    id("example#Entry"),
    profile=Some(profile("arrays")),
  )
  assert_eq(entry.canonicalize("[\"a\",1]"), "[\"a\",1]")
  assert_eq(entry.canonicalize("[\"a\",1,\"n\"]"), "[\"a\",1,\"n\"]")
  let short = entry.check("[\"a\"]")
  assert_eq(short.findings[0].code, MissingMember)
  assert_eq(short.findings[0].path.pointer(), "/1")
  let long = entry.check("[\"a\",1,\"n\",2]")
  assert_eq(long.findings[0].code, Arity)
  assert_eq(long.findings[0].path.pointer(), "/3")
  let call = @codec.PreparedCodec::prepare(
    model,
    id("example#Call"),
    profile=Some(profile("arrays")),
  )
  let value = call.decode("[\"f\",[\"a\",1],[\"b\",2,\"x\"]]")
  assert_eq(value.logical().get("tail").unwrap().get("x") is None, true)
  assert_eq(call.encode(value), "[\"f\",[\"a\",1],[\"b\",2,\"x\"]]")
  let nested = call.check("[\"f\",[\"a\",1],[\"b\",\"2\"]]")
  assert_eq(nested.findings[0].path.pointer(), "/2/1")
  // A caller value with a hole cannot be written with omitted positions.
  let hole = entry.value(
    Structure([
      ("name", String("a")),
      ("size", @codec.LogicalValue::number("1")),
    ]),
  )
  assert_eq(entry.encode(hole), "[\"a\",1]")
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {tuple: {members: [\"a\", \"b\"], optional: \"omit\"}})\nstructure R { a: String, @required b: String }",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#R: Required member b follows an optional position, which leaves a hole.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {tuple: {members: [\"a\"]}})\nstructure R { @required a: String, b: String }",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#R: Member b has no tuple position.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {tuple: {members: [\"a\", \"a\"]}})\nstructure R { @required a: String }",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#R: The tuple lists member a at two positions.",
  )
  inspect(
    refusal(
      header +
      "@jsonEncoding(base: {tuple: {members: [\"a\"], rest: \"b\"}})\nstructure R { @required a: String, b: String }",
      "example#R",
      None,
    ),
    content="InvalidDeclaration: example#R: The rest member b needs a list target.",
  )
}

///|
let dictionary_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|
  #|@jsonProfiles([
  #|  {id: "entries", defaults: {dictionary: {layout: "entries", key: "test.words", order: "adapter"}}}
  #|  {id: "object", defaults: {dictionary: {layout: "object", key: "test.words"}}}
  #|])
  #|map Fields {
  #|  key: String
  #|  value: Integer
  #|}

///|
test "dictionary layouts preserve key identity" {
  let model = load(dictionary_model)
  let entries = @codec.PreparedCodec::prepare(
    model,
    id("example#Fields"),
    profile=Some(profile("entries")),
    adapters=registry(),
  )
  let object = @codec.PreparedCodec::prepare(
    model,
    id("example#Fields"),
    profile=Some(profile("object")),
    adapters=registry(),
  )
  let value = entries.decode("[[[\"b\",\"c\"],1],[\"z\",2],[[\"a\"],3]]")
  assert_eq(entries.encode(value), "[[\"a\",3],[\"z\",2],[\"b-c\",1]]")
  assert_eq(object.encode(value), "{\"a\":3,\"b-c\":1,\"z\":2}")
  assert_true(object.decode(object.encode(value)) == value)
  let duplicate = entries.check("[[[\"a\",\"b\"],1],[\"a-b\",2]]")
  assert_eq(duplicate.findings[0].code, DuplicateKey)
  assert_eq(duplicate.findings[0].path.pointer(), "/1/0")
  let malformed = entries.check("[[\"a\",1,2]]")
  assert_eq(malformed.findings[0].code, Arity)
  assert_eq(malformed.findings[0].path.pointer(), "/0")
}

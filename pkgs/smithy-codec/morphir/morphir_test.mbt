///|
let collision_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonEncoding
  #|
  #|@jsonEncoding(base: {dictionary: {layout: "object", key: "morphir.v4.name", order: "preserve", accept: ["entries"]}})
  #|map V4Inputs {
  #|  key: String
  #|  value: Integer
  #|}
  #|
  #|@jsonEncoding(base: {dictionary: {layout: "entries", key: "morphir.v3.name", order: "adapter"}})
  #|map V3Fields {
  #|  key: String
  #|  value: Integer
  #|}
  #|
  #|structure Header {
  #|  @required
  #|  @jsonEncoding(base: {adapter: "morphir.format-version"})
  #|  formatVersion: String
  #|}

///|
fn codec(root : String) -> @codec.PreparedCodec raise {
  let loaded = @contract.loader()
    .add_idl("model.smithy", collision_model)
    .assemble()
  @codec.PreparedCodec::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#" + root).unwrap(),
    adapters=@morphir.registry(),
  )
}

///|
test "the registry holds every Morphir adapter once" {
  let ids = @morphir.adapters().map(a => a.id().to_string())
  assert_eq(ids, [
    "morphir.format-version", "morphir.v3.fqname", "morphir.v3.name", "morphir.v3.path",
    "morphir.v4.fqname", "morphir.v4.float-token", "morphir.v4.integer-token", "morphir.v4.name",
    "morphir.v4.path",
  ])
  let registry = @morphir.registry()
  for id in ids {
    assert_true(registry.get(@contract.AdapterId::parse(id)) is Some(_))
  }
}

///|
test "legacy and canonical spellings of one v4 name are one key" {
  let inputs = codec("V4Inputs")
  assert_eq(
    inputs.canonicalize("[[[\"value\",\"in\",\"u\",\"s\",\"d\"],1],[\"b\",2]]"),
    "{\"value-in-USD\":1,\"b\":2}",
  )
  let collision = inputs.check(
    "[[[\"value\",\"in\",\"u\",\"s\",\"d\"],1],[\"value-in-USD\",2]]",
  )
  assert_false(collision.is_valid())
  assert_eq(collision.findings[0].code, DuplicateKey)
  assert_eq(collision.findings[0].path.pointer(), "/1/0")
  let invalid = inputs.check("{\"value-in-(usd)\":1}")
  assert_eq(invalid.findings[0].code, AdapterFailure)
}

///|
test "v3 keys are written in Elm order and duplicates are refused" {
  let fields = codec("V3Fields")
  assert_eq(
    fields.canonicalize("[[[\"b\"],1],[[\"a\",\"b\"],2],[[\"a\"],3]]"),
    "[[[\"a\"],3],[[\"a\",\"b\"],2],[[\"b\"],1]]",
  )
  let duplicate = fields.check("[[[\"a\"],1],[[\"a\"],2]]")
  assert_eq(duplicate.findings[0].code, DuplicateKey)
  let bad = fields.check("[[[\"A\"],1]]")
  assert_eq(bad.findings[0].code, AdapterFailure)
  assert_eq(bad.findings[0].path.pointer(), "/0/0/0")
}

///|
test "formatVersion is normalized and written canonically" {
  let header = codec("Header")
  assert_eq(
    header.canonicalize("{\"formatVersion\":\"4.0.0\"}"),
    "{\"formatVersion\":4}",
  )
  assert_eq(
    header.canonicalize("{\"formatVersion\":\"3.1.0\"}"),
    "{\"formatVersion\":\"3.1.0\"}",
  )
  assert_eq(
    header.canonicalize("{\"formatVersion\":3}"),
    "{\"formatVersion\":3}",
  )
  for
    bad in ["\"3.0\"", "3.0", "0", "\"2.0.0\"", "true", "-1", "\"4.0.0-beta\""] {
    assert_false(
      header.check("{\"formatVersion\":" + bad + "}").is_valid(),
      msg=bad,
    )
  }
}

///|
test "an adapter fails when the request has no work left" {
  let loaded = @contract.loader()
    .add_idl("model.smithy", collision_model)
    .assemble()
  let tight = @codec.PreparedCodec::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#V3Fields").unwrap(),
    adapters=@morphir.registry(),
    limits=@codec.CodecLimits::new(work=20),
  )
  let words = Array::make(200, "\"a\"").join(",")
  let result = tight.check("[[[" + words + "],1]]")
  assert_false(result.is_valid())
  assert_false(result.complete)
}

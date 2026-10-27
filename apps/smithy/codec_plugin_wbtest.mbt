///|
let codec_plugin_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|@jsonProfiles([{id: "object"}, {id: "array", defaults: {union: {style: "tagArray"}}}])
  #|union Expr {
  #|  Num: Count
  #|  Add: Add
  #|}
  #|@range(max: 100)
  #|integer Count
  #|@jsonEncoding(profiles: {array: {tuple: {members: ["left", "right"]}}})
  #|structure Add {
  #|  @required
  #|  left: Expr
  #|  @required
  #|  right: Expr
  #|}

///|
fn codec_plugin_files() -> Map[String, String] {
  {
    "/work/values/a.json": "[\"Add\",[\"Num\",1],[\"Num\", 2]]",
    "/work/values/bad.json": "[\"Add\",[\"Num\",1],[\"Num\",200]]",
  }
}

///|
fn run_codec_plugin(settings : String) -> Map[String, String] raise {
  let model = model_loader()
  .add_idl("expr.smithy", codec_plugin_model)
  .assemble().model.unwrap()
  let files = codec_plugin_files()
  json_codec_plugin("/work", model, @json.parse(settings), read=path => {
    match files.get(path) {
      Some(text) => text
      None => fail("no file " + path)
    }
  })
}

///|
fn codec_plugin_refusal(settings : String) -> String raise {
  try run_codec_plugin(settings) catch {
    @build.InvalidBuildConfig(message) => message
    error => raise error
  } noraise {
    _ => fail("expected a refusal")
  }
}

///|
test "jsonCodec canonicalizes with the library contract" {
  let files = run_codec_plugin(
    "{\"action\":\"canonicalize\",\"shape\":\"example#Expr\",\"profile\":\"array\",\"values\":[{\"input\":\"values/a.json\"}]}",
  )
  let model = model_loader()
  .add_idl("expr.smithy", codec_plugin_model)
  .assemble().model.unwrap()
  let library = @codec.PreparedCodec::prepare(
    model,
    @smithy.ShapeId::parse("example#Expr").unwrap(),
    profile=Some(@codec_contract.ProfileId::parse("array")),
    adapters=host_adapters(),
  )
  assert_eq(
    files["a.json"],
    library.canonicalize(codec_plugin_files()["/work/values/a.json"]) + "\n",
  )
  let checked = run_codec_plugin(
    "{\"action\":\"check\",\"shape\":\"example#Expr\",\"profile\":\"array\",\"values\":[{\"input\":\"values/a.json\"}]}",
  )
  assert_true(checked.contains("json-codec-check.json"))
}

///|
test "jsonCodec refuses invalid values and rule changes" {
  let invalid = codec_plugin_refusal(
    "{\"action\":\"check\",\"shape\":\"example#Expr\",\"profile\":\"array\",\"values\":[{\"input\":\"values/bad.json\"}]}",
  )
  assert_true(invalid.contains("values/bad.json/2/1: error[Range]"))
  let rules = codec_plugin_refusal(
    "{\"action\":\"check\",\"shape\":\"example#Expr\",\"profile\":\"array\",\"unionStrategy\":\"object\",\"values\":[{\"input\":\"values/a.json\"}]}",
  )
  assert_true(rules.contains("unknown setting `unionStrategy`"))
  let escape = codec_plugin_refusal(
    "{\"action\":\"check\",\"shape\":\"example#Expr\",\"values\":[{\"input\":\"../a.json\"}]}",
  )
  assert_true(escape.contains("inside the build configuration directory"))
  let unknown = codec_plugin_refusal(
    "{\"action\":\"check\",\"shape\":\"example#Expr\",\"profile\":\"tree\",\"values\":[{\"input\":\"values/a.json\"}]}",
  )
  assert_true(unknown.contains("no profile tree"))
}

///|
test "generators and exporters refuse serialization profiles" {
  let model = model_loader()
  .add_idl("expr.smithy", codec_plugin_model)
  .assemble().model.unwrap()
  let refused = try
    refuse_profile("jsonSchema", json_schema_plugin)(
      model,
      @json.parse("{\"profile\":\"array\"}"),
    )
  catch {
    @build.InvalidBuildConfig(message) => message
    error => raise error
  } noraise {
    _ => fail("expected a refusal")
  }
  assert_true(
    refused.contains("jsonSchema does not support serialization profiles"),
  )
  // Ordinary export is unchanged: unionStrategy still selects a schema rendering.
  let schema = refuse_profile("jsonSchema", json_schema_plugin)(
    model,
    @json.parse("{\"unionStrategy\":\"oneOf\"}"),
  )
  assert_true(schema.contains("schema.json"))
}

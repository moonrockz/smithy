///|
/// Reads an integer baseline `N` or a release string; writes N for N.0.0, else the string.
fn version_adapter() -> @codec.ScalarAdapter raise {
  @codec.ScalarAdapter::new(
    @contract.AdapterId::parse("test.version"),
    inputs=[NumberKind, StringKind],
    output=StringKind,
    read=(value, _) => {
      match value {
        Number(_, ..) =>
          match @codec.json_number(value) {
            Some(n) if n.is_integer() && !n.to_string().contains(".") =>
              Ok(Text(n.to_string() + ".0.0"))
            _ =>
              Err(
                @codec.AdapterFailure::new(
                  "I expected an integer major release.",
                ),
              )
          }
        String(text) =>
          try @contract.Release::parse(text) catch {
            _ => Err(@codec.AdapterFailure::new("I expected X.Y.Z."))
          } noraise {
            _ => Ok(Text(text))
          }
        _ => Err(@codec.AdapterFailure::new("I expected a version."))
      }
    },
    write=(value, _) => {
      match value {
        Text(text) =>
          if text.has_suffix(".0.0") {
            Ok(
              @codec.number_json(
                @smithy.NodeNumber::parse(
                  text.split(".").collect()[0].to_owned(),
                ).unwrap(),
              ),
            )
          } else {
            Ok(Json::string(text))
          }
        _ => Err(@codec.AdapterFailure::new("I expected text."))
      }
    },
  )
}

///|
let bundle_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.serialization#jsonProfiles
  #|use smithy.serialization#jsonEncoding
  #|use smithy.serialization#jsonBundle
  #|
  #|@jsonBundle(
  #|  id: "doc"
  #|  version: {field: "formatVersion", adapter: "test.version"}
  #|  releases: [
  #|    {since: "1.0.0", until: "2.0.0", root: V1, profiles: ["v1"]}
  #|    {since: "2.0.0", until: "2.1.0", root: V2, profiles: ["v2", "v2-wrapped"]}
  #|  ]
  #|)
  #|structure Documents {}
  #|
  #|@jsonProfiles([{id: "v1", defaults: {union: {style: "tagArray"}}}])
  #|structure V1 {
  #|  @required
  #|  @jsonEncoding(base: {adapter: "test.version"})
  #|  formatVersion: String
  #|  @required
  #|  body: Node
  #|}
  #|
  #|@jsonProfiles([
  #|  {id: "v2"}
  #|  {id: "v2-wrapped", defaults: {union: {style: "adjacent", tag: "kind", content: "value"}}}
  #|])
  #|structure V2 {
  #|  @required
  #|  @jsonEncoding(base: {adapter: "test.version"})
  #|  formatVersion: String
  #|  @required
  #|  body: Node2
  #|}
  #|
  #|union Node {
  #|  Leaf: Integer
  #|}
  #|
  #|union Node2 {
  #|  Leaf: Integer
  #|  Note: String
  #|}

///|
fn bundle() -> @codec.PreparedBundle raise {
  @codec.PreparedBundle::prepare(
    load(bundle_model),
    @contract.BundleId::parse("doc"),
    adapters=@codec.AdapterRegistry::new().register(version_adapter()),
  )
}

///|
test "dispatch selects the release root before decoding" {
  let b = bundle()
  let v1 = b.decode("{\"body\":[\"Leaf\",1],\"formatVersion\":1}")
  assert_eq(v1.release().to_string(), "1.0.0")
  assert_eq(b.encode(v1), "{\"formatVersion\":1,\"body\":[\"Leaf\",1]}")
  let v15 = b.decode("{\"formatVersion\":\"1.5.0\",\"body\":[\"Leaf\",1]}")
  assert_eq(
    b.encode(v15),
    "{\"formatVersion\":\"1.5.0\",\"body\":[\"Leaf\",1]}",
  )
  let v2 = b.decode("{\"formatVersion\":\"2.0.0\",\"body\":{\"Note\":\"n\"}}")
  assert_eq(v2.release().to_string(), "2.0.0")
  assert_eq(b.encode(v2), "{\"formatVersion\":2,\"body\":{\"Note\":\"n\"}}")
  assert_eq(
    b.encode(v2, profile=Some(profile("v2-wrapped"))),
    "{\"formatVersion\":2,\"body\":{\"kind\":\"Note\",\"value\":\"n\"}}",
  )
  // The v1 payload is not interpreted as v2, and a v2 value cannot be written as v1.
  assert_eq(
    b.check("{\"formatVersion\":1,\"body\":{\"Note\":\"n\"}}").findings[0].code,
    KindMismatch,
  )
  assert_eq(
    failure(() => ignore(b.encode(v2, profile=Some(profile("v1"))))).findings[0].code,
    VersionConflict,
  )
}

///|
test "missing, malformed, unsupported and conflicting versions are distinct" {
  let b = bundle()
  let codes = [
    ("{\"body\":[\"Leaf\",1]}", None),
    ("{\"formatVersion\":\"1.x\",\"body\":[\"Leaf\",1]}", None),
    ("{\"formatVersion\":true,\"body\":[\"Leaf\",1]}", None),
    ("{\"formatVersion\":3,\"body\":[\"Leaf\",1]}", None),
    ("{\"formatVersion\":1,\"body\":[\"Leaf\",1]}", Some("v2")),
  ].map(entry => {
    let result = b.check(
      entry.0,
      profile=entry.1.map(p => {
        @contract.ProfileId::parse(p) catch {
          _ => panic()
        }
      }),
    )
    result.findings[0].code.to_string() +
    " " +
    result.findings[0].path.pointer()
  })
  inspect(
    codes.join("\n"),
    content=(
      #|MissingVersion /formatVersion
      #|InvalidVersion /formatVersion
      #|InvalidVersion /formatVersion
      #|UnsupportedVersion /formatVersion
      #|VersionConflict /formatVersion
    ),
  )
}

///|
test "bundle declarations are checked" {
  let model = load(
    header +
    "use smithy.serialization#jsonBundle\n@jsonProfiles([{id: \"p\"}])\nstructure R { formatVersion: String }\n" +
    "@jsonBundle(id: \"b\", version: {field: \"formatVersion\", adapter: \"test.version\"}, releases: [" +
    "{since: \"1.0.0\", until: \"2.0.0\", root: R, profiles: [\"p\"]}, {since: \"1.5.0\", until: \"3.0.0\", root: R, profiles: [\"p\"]}])\nstructure B {}",
  )
  try @contract.declared_bundles(model) catch {
    e =>
      inspect(
        e.message(),
        content="example#B: Release intervals [1.0.0, 2.0.0) and [1.5.0, 3.0.0) overlap.",
      )
  } noraise {
    _ => fail("expected a refusal")
  }
  let model = load(bundle_model)
  try bundle_with(model, "missing") catch {
    e =>
      inspect(
        e.message(),
        content="I expected a declared document bundle, but found no bundle missing.",
      )
  } noraise {
    _ => fail("expected a refusal")
  }
}

///|
fn bundle_with(
  model : @smithy.Model,
  name : String,
) -> Unit raise @contract.ContractError {
  ignore(
    @codec.PreparedBundle::prepare(
      model,
      @contract.BundleId::parse(name) catch {
        _ => panic()
      },
    ),
  )
}

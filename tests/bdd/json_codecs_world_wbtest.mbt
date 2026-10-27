///|
struct JsonCodecWorld {
  mut model : @smithy.Model?
  mut codec : @codec.PreparedCodec?
  mut bundle : @codec.PreparedBundle?
  mut refusal : @codec_contract.ContractError?
  mut result : @codec.CodecResult?
  mut canonical : String?
  decoded : Array[@codec.CodecValue]
}

///|
fn JsonCodecWorld::new() -> JsonCodecWorld {
  {
    model: None,
    codec: None,
    bundle: None,
    refusal: None,
    result: None,
    canonical: None,
    decoded: [],
  }
}

///|
/// Reads an integer major release or an X.Y.Z string; writes N for N.0.0.
fn bdd_version_adapter() -> @codec.ScalarAdapter raise {
  @codec.ScalarAdapter::new(
    @codec_contract.AdapterId::parse("test.version"),
    inputs=[NumberKind, StringKind],
    output=StringKind,
    read=(value, _) => {
      match value {
        Number(_, ..) =>
          match @codec.json_number(value) {
            Some(n) if n.is_integer() && !n.to_string().contains(".") =>
              Ok(Text(n.to_string() + ".0.0"))
            _ =>
              Err(@codec.AdapterFailure::new("I expected an integer release."))
          }
        String(text) =>
          try @codec_contract.Release::parse(text) catch {
            _ => Err(@codec.AdapterFailure::new("I expected X.Y.Z."))
          } noraise {
            _ => Ok(Text(text))
          }
        _ => Err(@codec.AdapterFailure::new("I expected a version."))
      }
    },
    write=(value, _) => {
      match value {
        Text(text) if text.has_suffix(".0.0") =>
          Ok(
            @codec.number_json(
              @smithy.NodeNumber::parse(text[:text.length() - 4].to_owned()).unwrap(),
            ),
          )
        Text(text) => Ok(Json::string(text))
        _ => Err(@codec.AdapterFailure::new("I expected text."))
      }
    },
  )
}

///|
fn JsonCodecWorld::profile(text : String) -> @codec_contract.ProfileId? raise {
  if text == "" {
    None
  } else {
    Some(@codec_contract.ProfileId::parse(text))
  }
}

///|
fn JsonCodecWorld::check(self : JsonCodecWorld, text : String) -> Unit raise {
  let result = match (self.codec, self.bundle) {
    (Some(codec), _) => codec.check(text)
    (_, Some(bundle)) => bundle.check(text)
    _ => fail("Prepare a codec first")
  }
  self.result = Some(result)
  if result.is_valid() {
    match self.codec {
      Some(codec) => self.decoded.push(codec.decode(text))
      None => ()
    }
  }
}

///|
impl @moonspec.World for JsonCodecWorld with fn configure(self, setup) {
  setup.given1("the codec model:", fn(doc : @moonspec.DocString) raise {
    let loaded = @codec_contract.loader()
      .add_idl("model.smithy", doc.content)
      .assemble()
    guard loaded.model is Some(model) else {
      fail(loaded.diagnostics.map(d => d.message).join("\n"))
    }
    self.model = Some(model)
  })
  setup.when2("I prepare the codec of {string} with profile {string}", fn(
    root : String,
    profile : String,
  ) raise {
    self.refusal = None
    self.codec = None
    let profile = JsonCodecWorld::profile(profile)
    let root = @smithy.ShapeId::parse(root).unwrap()
    let model = self.model.unwrap()
    let prepared = @codec.PreparedCodec::prepare(
      model,
      root,
      profile~,
      adapters=@morphir.registry(),
    ) catch {
      error => {
        self.refusal = Some(error)
        return
      }
    }
    self.codec = Some(prepared)
  })
  setup.when1("I prepare the document bundle {string}", fn(id : String) raise {
    self.bundle = Some(
      @codec.PreparedBundle::prepare(
        self.model.unwrap(),
        @codec_contract.BundleId::parse(id),
        adapters=@codec.AdapterRegistry::new().register(bdd_version_adapter()),
      ),
    )
  })
  setup.then1("preparation is refused with {string}", fn(code : String) raise {
    guard self.refusal is Some(error) else { fail("Expected a refusal") }
    assert_eq(error.code(), code)
  })
  setup.when1("I check the JSON {string}", fn(text : String) raise {
    self.check(text)
  })
  setup.when2(
    "I check JSON that spells the member {string} a second time as {string}",
    fn(name : String, escaped : String) raise {
      // The step text keeps the backslash, so the JSON input holds the escape sequence itself.
      assert_true(escaped.has_prefix("\\"))
      self.check(
        "{\"" +
        name +
        "\":{\"Stop\":{}},\"" +
        escaped[1:].to_owned() +
        "\":{\"Stop\":{}}}",
      )
    },
  )
  setup.then0("the JSON is valid", fn() raise {
    guard self.result is Some(result) else { fail("Check first") }
    assert_true(result.is_valid())
  })
  setup.then2("the codec finding is {string} at {string}", fn(
    code : String,
    pointer : String,
  ) raise {
    guard self.result is Some(result) && result.findings.length() > 0 else {
      fail("Expected a finding")
    }
    assert_eq(result.findings[0].code.to_string(), code)
    assert_eq(result.findings[0].path.pointer(), pointer)
  })
  setup.then0("the check is incomplete", fn() raise {
    guard self.result is Some(result) else { fail("Check first") }
    assert_false(result.complete)
    assert_false(result.is_valid())
  })
  setup.then0("the decoded values are equal", fn() raise {
    assert_true(self.decoded.length() >= 2)
    for value in self.decoded {
      assert_true(value == self.decoded[0])
    }
  })
  setup.when1("I canonicalize the JSON {string}", fn(text : String) raise {
    self.canonical = Some(
      match (self.codec, self.bundle) {
        (Some(codec), _) => codec.canonicalize(text)
        (_, Some(bundle)) => bundle.canonicalize(text)
        _ => fail("Prepare a codec first")
      },
    )
  })
  setup.then1("the canonical JSON is {string}", fn(text : String) raise {
    assert_eq(self.canonical, Some(text))
    let again = match (self.codec, self.bundle) {
      (Some(codec), _) => codec.canonicalize(text)
      (_, Some(bundle)) => bundle.canonicalize(text)
      _ => fail("Prepare a codec first")
    }
    assert_eq(again, text)
  })
  setup.then1("the value validator still reports {string}", fn(
    text : String,
  ) raise {
    let validator = @validation.PreparedValidator::prepare(
      self.model.unwrap(),
      @smithy.ShapeId::parse(text).unwrap(),
    )
    let result = validator.validate_json(
      @validation.parse_json_value("{\"op\":[\"Add\",1,2]}"),
    )
    assert_eq(result.findings[0].code, @validation.TypeMismatch)
  })
}

///|
async test "JSON codecs feature" {
  @moonspec.run_or_fail(
    JsonCodecWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/json-codecs.feature"),
    ]),
  )
  |> ignore
}

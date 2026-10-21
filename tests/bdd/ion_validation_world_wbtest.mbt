///|
struct IonValidationWorld {
  mut prepared : @ion_validation.PreparedValidator?
  mut text : String
  mut result : @ion_validation.ValidationResult?
}

///|
fn IonValidationWorld::new() -> IonValidationWorld {
  { prepared: None, text: "", result: None, }
}

///|
impl @moonspec.World for IonValidationWorld with fn configure(self, setup) {
  setup.given0("a prepared count Ion validator", fn() raise {
    self.prepared = Some(
      @ion_validation.PreparedValidator::prepare(
        value_model(
          "@range(min: 1, max: 100)\ninteger Count\nstructure Input { @required count: Count }",
        ),
        @smithy.ShapeId::parse("example#Input").unwrap(),
      ),
    )
  })
  setup.when1("I validate the Ion text {string}", fn(text : String) raise {
    self.text = text
    self.result = Some(
      self.prepared.unwrap().validate(@ion_text.read_ion(text)),
    )
  })
  setup.when0("I validate the equivalent Ion binary", fn() raise {
    let binary = @ion_binary.write_binary_value(@ion_text.read_ion(self.text))
    self.result = Some(
      self.prepared.unwrap().validate(@ion_binary.read_binary_value(binary)),
    )
  })
  setup.then0("the Ion value is valid", fn() raise {
    assert_true(self.result.unwrap().is_valid())
  })
  setup.then0("the duplicate Ion field has occurrence 1", fn() raise {
    let result = self.result.unwrap()
    assert_false(result.is_valid())
    assert_true(
      result.findings.any(f => {
        f.code == @validation.DuplicateMember &&
        f.path.steps() == [@validation.Field("count", 1)]
      }),
    )
  })
  setup.then4(
    "the Ion finding is {string} at {string} on {string} with kind {string}",
    fn(code : String, pointer : String, shape : String, kind : String) raise {
      let result = self.result.unwrap()
      assert_false(result.is_valid())
      assert_true(result.complete)
      assert_true(
        result.findings.any(f => {
          f.code.to_string() == code &&
          f.path.pointer() == pointer &&
          f.shape.to_string() == shape &&
          f.native_kind.map(k => k.to_text()) == Some(kind)
        }),
      )
    },
  )
}

///|
async test "Direct Ion value validation feature" {
  @moonspec.run_or_fail(
    IonValidationWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/ion-validation.feature"),
    ]),
  )
  |> ignore
}

///|
struct ValueValidationWorld {
  mut model : @smithy.Model?
  mut prepared : @validation.PreparedValidator?
  mut result : @validation.ValidationResult?
  mut problem : String?
}

///|
fn ValueValidationWorld::new() -> ValueValidationWorld {
  { model: None, prepared: None, result: None, problem: None, }
}

///|
fn value_model(source : String) -> @smithy.Model raise {
  let loaded = @smithy.Loader::new()
    .add_idl("value.smithy", "$version: \"2\"\nnamespace example\n" + source)
    .assemble()
  guard loaded.model is Some(model) else {
    fail("Could not assemble value fixture")
  }
  model
}

///|
impl @moonspec.World for ValueValidationWorld with fn configure(self, setup) {
  setup.given0("a prepared date-time member validator", fn() raise {
    self.prepared = Some(
      @validation.PreparedValidator::prepare(
        value_model(
          "@timestampFormat(\"date-time\")\ntimestamp Time\nstructure Input { @required at: Time }",
        ),
        @smithy.ShapeId::parse("example#Input").unwrap(),
      ),
    )
  })
  setup.given0("a prepared count value validator", fn() raise {
    let model = value_model(
      "@range(min: 1, max: 100)\ninteger Count\nstructure Input { @required count: Count }",
    )
    self.prepared = Some(
      @validation.PreparedValidator::prepare(
        model,
        @smithy.ShapeId::parse("example#Input").unwrap(),
      ),
    )
  })
  setup.given0("a value model with an unsupported pattern", fn() raise {
    self.model = Some(value_model("@pattern(\"(?=a)a\")\nstring Input"))
  })
  setup.given1("a value model whose input has the pattern {string}", fn(
    pattern : String,
  ) raise {
    self.model = Some(
      value_model("@pattern(\"" + pattern + "\")\nstring Input"),
    )
  })
  setup.when0("I prepare the value validator", fn() raise {
    try {
      self.prepared = Some(
        @validation.PreparedValidator::prepare(
          self.model.unwrap(),
          @smithy.ShapeId::parse("example#Input").unwrap(),
        ),
      )
    } catch {
      @validation.UnsupportedConstraint(_, _) =>
        self.problem = Some("UnsupportedConstraint")
      error => raise error
    }
  })
  setup.when1("I validate the JSON value {string}", fn(text : String) raise {
    self.problem = None
    self.result = None
    try {
      self.result = Some(
        self.prepared.unwrap().validate_json(@validation.parse_json_value(text)),
      )
    } catch {
      @validation.DuplicateJsonKey(_) => self.problem = Some("DuplicateJsonKey")
      error => raise error
    }
  })
  setup.then0("the value is valid", fn() raise {
    assert_true(self.result.unwrap().is_valid())
  })
  setup.then3("the value finding is {string} at {string} on {string}", fn(
    code : String,
    pointer : String,
    shape : String,
  ) raise {
    let result = self.result.unwrap()
    assert_false(result.is_valid())
    assert_true(result.complete)
    assert_eq(result.findings.length(), 1)
    assert_eq(result.findings[0].code.to_string(), code)
    assert_eq(result.findings[0].path.pointer(), pointer)
    assert_eq(result.findings[0].shape.to_string(), shape)
  })
  setup.then0("value preparation reports an unsupported constraint", fn() raise {
    assert_eq(self.problem, Some("UnsupportedConstraint"))
  })
  setup.then0("the JSON value has duplicate names", fn() raise {
    assert_eq(self.problem, Some("DuplicateJsonKey"))
  })
}

///|
async test "Direct application value validation feature" {
  @moonspec.run_or_fail(
    ValueValidationWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/value-validation.feature"),
    ]),
  )
  |> ignore
}

///|
struct OpenApiWorld {
  mut model : @smithy.Model?
  mut result : Result[@openapi.Conversion, @openapi.OpenApiError]?
}

///|
fn OpenApiWorld::new() -> OpenApiWorld {
  { model: None, result: None, }
}

///|
impl @moonspec.World for OpenApiWorld with fn configure(self, setup) {
  setup.given1("the OpenAPI model {string}", fn(file : String) raise {
    let loader = @smithy.Loader::new()
    for input in @openapi.protocol_definitions() {
      ignore(loader.add(input))
    }
    ignore(
      loader.add_idl(file, @xfs.read_file_to_string("tck/openapi/" + file)),
    )
    self.model = loader.assemble().model
    assert_true(self.model is Some(_))
  })
  setup.when2("I convert service {string} to OpenAPI {string}", fn(
    service : String,
    version : String,
  ) {
    let config = @openapi.Config::new(
      @openapi.ServiceId::parse(service).unwrap(),
      version=@openapi.OpenApiVersion::parse(version).unwrap(),
      combine_error_responses=true,
    )
    self.result = Some(
      Ok(@openapi.convert_result(self.model.unwrap(), config)) catch {
        error => Err(error)
      },
    )
  })
  setup.then1("the OpenAPI document matches {string}", fn(file : String) raise {
    guard self.result is Some(Ok(converted)) else { fail("conversion failed") }
    assert_eq(
      converted.document,
      @json.parse(@xfs.read_file_to_string("tck/openapi/" + file)),
    )
  })
  setup.then0("OpenAPI conversion reports a missing service", fn() raise {
    assert_true(self.result is Some(Err(@openapi.MissingService(_))))
  })
}

///|
async test "OpenAPI feature" {
  @moonspec.run_or_fail(
    OpenApiWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/openapi.feature"),
    ]),
  )
  |> ignore
}

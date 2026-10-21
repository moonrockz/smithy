///|
struct OpenRpcWorld {
  mut model : @smithy.Model?
  mut result : Result[@openrpc.Conversion, @openrpc.OpenRpcError]?
}

///|
fn OpenRpcWorld::new() -> OpenRpcWorld {
  { model: None, result: None, }
}

///|
impl @moonspec.World for OpenRpcWorld with fn configure(self, setup) {
  setup.given0("the OpenRPC calculator model", fn() raise {
    let loaded = @rpc.loader()
      .add_idl(
        "calculator.smithy",
        @xfs.read_file_to_string("../examples/openrpc/model.smithy"),
      )
      .assemble()
    guard loaded.model is Some(model) else {
      fail(loaded.diagnostics.map(d => d.message).join("\n"))
    }
    self.model = Some(model)
  })
  setup.when1("I export OpenRPC with settings {string}", fn(
    settings : String,
  ) raise {
    let settings = @json.parse(settings)
    self.result = Some(
      Ok(
        @openrpc.convert_result(
          self.model.unwrap(),
          @openrpc.Config::from_json(settings),
        ),
      ) catch {
        error => Err(error)
      },
    )
  })
  setup.then0(
    "the OpenRPC document describes named positional and either methods",
    fn() raise {
      guard self.result is Some(Ok(converted)) &&
        converted.document
        is { "openrpc": String("1.3.2"), "methods": Array(methods), .. } else {
        fail("Expected OpenRPC 1.3.2")
      }
      assert_eq(methods.length(), 3)
      for
        (name, mode) in [
          ("clear", "by-position"),
          ("history", "by-name"),
          ("subtract", "either"),
        ] {
        assert_true(
          methods
          .iter()
          .any(value => {
            value is { "name": String(n), "paramStructure": String(m), .. } &&
            n == name &&
            m == mode
          }),
        )
      }
    },
  )
  setup.then0(
    "OpenRPC preserves explicit null results and application error data",
    fn() raise {
      guard self.result is Some(Ok(converted)) &&
        converted.document is { "methods": Array(methods), .. } else {
        fail("Expected methods")
      }
      assert_true(
        methods
        .iter()
        .any(value => {
          value
          is {
            "name": String("clear"),
            "result": { "schema": { "type": String("null"), .. }, .. },
            ..
          }
        }),
      )
      assert_true(
        methods
        .iter()
        .any(value => {
          value
          is {
            "name": String("subtract"),
            "x-smithy-error-data": Array(errors),
            ..
          } &&
          !errors.is_empty()
        }),
      )
    },
  )
  setup.then0("OpenRPC reports structured omission warnings", fn() raise {
    guard self.result is Some(Ok(converted)) else {
      fail("Expected successful conversion with warnings")
    }
    assert_true(
      converted.warnings
      .iter()
      .any(w => {
        w.code == @openrpc.OmittedProtocolSemantics &&
        w.shape.to_string() == "example.rpc#Calculator"
      }),
    )
    assert_true(
      converted.warnings.iter().any(w => w.code == @openrpc.OmittedErrorData),
    )
  })
  setup.then1("OpenRPC reports an invalid selection for {string}", fn(
    shape : String,
  ) raise {
    guard self.result is Some(Err(error)) else {
      fail("Expected failed selection")
    }
    assert_eq(error.shape().to_string(), shape)
  })
}

///|
async test "OpenRPC feature" {
  @moonspec.run_or_fail(
    OpenRpcWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/openrpc.feature"),
    ]),
  )
  |> ignore
}

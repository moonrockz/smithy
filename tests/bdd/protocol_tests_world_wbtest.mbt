///|
struct ProtocolTestsWorld {
  mut suite : @protocoltests.Suite?
  mut result : @protocoltests.Outcome?
}

///|
fn ProtocolTestsWorld::new() -> ProtocolTestsWorld {
  { suite: None, result: None, }
}

///|
struct HttpFixture {
  message : @protocoltests.HttpMessage
}

///|
impl @protocoltests.Protocol for HttpFixture with fn produce(self, _case) {
  self.message
}

///|
impl @moonspec.World for ProtocolTestsWorld with fn configure(self, setup) {
  setup.given0("the greeting protocol test suite", fn() raise {
    let loaded = @protocoltests.loader()
      .add_idl(
        "greeting.smithy",
        @xfs.read_file_to_string("../examples/protocol-tests/greeting.smithy"),
      )
      .assemble()
    self.suite = Some(@protocoltests.Suite::from_model(loaded.model.unwrap()))
  })
  setup.when1("the fixture protocol produces a {string} request", fn(
    verb : String,
  ) {
    let case_ = self.suite
      .unwrap()
      .cases()
      .filter(c => c.id().to_string() == "GreetingRequest")[0]
    self.result = Some(
      @protocoltests.run(
        HttpFixture::{
          message: @protocoltests.HttpMessage::Request(
            verb~,
            uri="/greeting",
            query=[],
            host=None,
            headers=[("content-type", "application/json")],
            body=b"{\"name\": \"Ada\"}",
          ),
        },
        case_,
        side=Client,
      ),
    )
  })
  setup.when0(
    "the fixture protocol produces a response with an arbitrary body",
    fn() {
      let case_ = self.suite
        .unwrap()
        .cases()
        .filter(c => c.id().to_string() == "GreetingResponse")[0]
      self.result = Some(
        @protocoltests.run(
          HttpFixture::{
            message: @protocoltests.HttpMessage::Response(
              code=200,
              headers=[],
              body=b"arbitrary",
            ),
          },
          case_,
          side=Server,
        ),
      )
    },
  )
  setup.then0("the protocol case matches", fn() raise {
    assert_eq(self.result, Some(@protocoltests.Matched))
  })
  setup.then0("the protocol case reports a method mismatch", fn() raise {
    assert_true(
      self.result is Some(Mismatched(ds)) &&
      ds.map(d => d.field) == [@protocoltests.Method],
    )
  })
}

///|
async test "HTTP protocol tests feature" {
  @moonspec.run_or_fail(
    ProtocolTestsWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/protocol-tests.feature"),
    ]),
  )
  |> ignore
}

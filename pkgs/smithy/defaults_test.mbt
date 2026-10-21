///|
test "explicit provider definitions override defaults regardless of call order" {
  let provider = @smithy.Loader::new()
  .add_idl(
    "provider.smithy",
    (
      #|$version: "2"
      #|metadata provider = "ignored"
      #|namespace example.provider
      #|structure Settings { fallback: String }
      #|structure Extra {}
    ),
  )
  .assemble().model.unwrap()
  for defaults_first in [true, false] {
    let loader = @smithy.Loader::new()
    if defaults_first {
      ignore(loader.add_defaults(provider))
    }
    ignore(
      loader.add_idl(
        "explicit.smithy",
        (
          #|$version: "2"
          #|namespace example.provider
          #|structure Settings { explicit: Integer }
          #|structure Consumer { value: Settings, extra: Extra }
        ),
      ),
    )
    if !defaults_first {
      ignore(loader.add_defaults(provider))
    }
    let result = loader.assemble()
    assert_false(result.has_errors())
    let model = result.model.unwrap()
    assert_true(model.get("example.provider#Settings$explicit") is Some(_))
    assert_eq(model.get("example.provider#Settings$fallback"), None)
    assert_true(model.get("example.provider#Extra") is Some(_))
    assert_false(model.metadata.contains("provider"))
    assert_eq(loader.assemble().model, result.model)
  }
}

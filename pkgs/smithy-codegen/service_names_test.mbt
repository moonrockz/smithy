///|
fn load_models(texts : Array[String]) -> @smithy.Model {
  let mut loader = @smithy.Loader::new()
  for index, text in texts {
    loader = loader.add_idl("m\{index}.smithy", text)
  }
  loader.assemble().model.unwrap()
}

///|
test "a renamed shape takes the name of the service rename map" {
  let model = load_models([
    (
      #|$version: "2"
      #|namespace example
      #|service Shop {
      #|  version: "1"
      #|  operations: [Buy]
      #|  rename: { "other#Item": "OtherItem" }
      #|}
      #|operation Buy { input: BuyInput }
      #|structure BuyInput { item: Item, other: other#Item }
      #|structure Item {}
      #|
    ),
    (
      #|$version: "2"
      #|namespace other
      #|structure Item {}
      #|
    ),
  ])
  let names = @codegen.ServiceNames::new(model, id_of("example#Shop"))
  assert_eq(names.shape_name(id_of("other#Item")), "OtherItem")
  assert_eq(names.shape_name(id_of("example#Item")), "Item")
  assert_eq(names.shape_name(id_of("example#BuyInput")), "BuyInput")
  // A member keeps its member name.
  assert_eq(names.shape_name(id_of("example#BuyInput$other")), "other")
}

///|
test "a missing service raises MissingService" {
  let model = load_model("$version: \"2\"\nnamespace example\nstructure A {}\n")
  try @codegen.ServiceNames::new(model, id_of("example#Missing")) catch {
    @codegen.MissingService(id) => assert_eq(id.to_string(), "example#Missing")
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected MissingService")
  }
}

///|
test "two services merge their rename maps" {
  let model = load_model(
    (
      #|$version: "2"
      #|namespace example
      #|service A { version: "1", operations: [One], rename: { "example#Shared": "Common" } }
      #|service B { version: "1", operations: [Two] }
      #|operation One { input: OneInput }
      #|operation Two { input: TwoInput }
      #|structure OneInput { s: Shared }
      #|structure TwoInput { s: Shared }
      #|structure Shared {}
      #|
    ),
  )
  let names = @codegen.ServiceNames::for_services(model, [
    id_of("example#A"),
    id_of("example#B"),
  ])
  assert_eq(names.shape_name(id_of("example#Shared")), "Common")
  assert_eq(names.shape_name(id_of("example#TwoInput")), "TwoInput")
}

///|
test "one shape with two renames is refused" {
  let model = load_model(
    (
      #|$version: "2"
      #|namespace example
      #|service A { version: "1", operations: [One], rename: { "example#Shared": "Common" } }
      #|service B { version: "1", operations: [Two], rename: { "example#Shared": "Joint" } }
      #|operation One { input: OneInput }
      #|operation Two { input: TwoInput }
      #|structure OneInput { s: Shared }
      #|structure TwoInput { s: Shared }
      #|structure Shared {}
      #|
    ),
  )
  try
    @codegen.ServiceNames::for_services(model, [
      id_of("example#A"),
      id_of("example#B"),
    ])
  catch {
    @codegen.InvalidSettings(text) =>
      assert_eq(
        text, "I found two names for shape `example#Shared` in the services: `Common` and `Joint`.",
      )
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected InvalidSettings")
  }
}

///|
test "two shapes with one contextual name are refused" {
  let model = load_models([
    (
      #|$version: "2"
      #|namespace example
      #|service A { version: "1", operations: [One] }
      #|service B { version: "1", operations: [Two] }
      #|operation One { input: OneInput }
      #|operation Two { input: TwoInput }
      #|structure OneInput { s: Item }
      #|structure TwoInput { s: other#ITEM }
      #|structure Item {}
      #|
    ),
    (
      #|$version: "2"
      #|namespace other
      #|structure ITEM {}
      #|
    ),
  ])
  try
    @codegen.ServiceNames::for_services(model, [
      id_of("example#A"),
      id_of("example#B"),
    ])
  catch {
    @codegen.InvalidSettings(text) =>
      assert_eq(
        text, "I found shapes `example#Item` and `other#ITEM` with the same name in the services. Add a rename to a service.",
      )
    e => fail("unexpected error: \{e.message()}")
  } noraise {
    _ => fail("expected InvalidSettings")
  }
}

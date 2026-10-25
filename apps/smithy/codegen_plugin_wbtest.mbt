///|
fn codegen_model(blocks : Array[String]) -> @smithy.Model {
  let loader = @smithy.Loader::new()
  loader.add_idl(
    "orders.smithy",
    "$version: \"2\"\nnamespace example\n\n" + blocks.join("\n\n") + "\n",
  )
  |> ignore
  loader.assemble().model.unwrap()
}

///|
test "codegenFixture build plugin writes deterministic outlines and fails a missing service" {
  let forward = codegen_model([
    "service Orders { version: \"1\", operations: [GetOrder] }", "operation GetOrder { input: GetOrderInput }",
    "structure GetOrderInput { id: String }",
  ])
  let reverse = codegen_model([
    "structure GetOrderInput { id: String }", "operation GetOrder { input: GetOrderInput }",
    "service Orders { version: \"1\", operations: [GetOrder] }",
  ])
  let settings = @json.parse(
    "{\"service\":\"example#Orders\",\"header\":\"generated\"}",
  )
  let first = @codegen_fixture.plugin(forward, settings)
  assert_true(first.contains("example/Orders.outline"))
  assert_true(first.contains("example/GetOrderInput.outline"))
  assert_true(first["example/GetOrderInput.outline"].contains("// generated"))
  assert_eq(first["example/GetOrderInput.outline"].contains("id: String"), true)
  let again = @codegen_fixture.plugin(reverse, settings)
  assert_eq(again.length(), first.length())
  for path, text in first {
    assert_eq(again[path], text)
  }
  let mut rejected = false
  ignore(
    @codegen_fixture.plugin(
      forward,
      @json.parse("{\"service\":\"example#Missing\"}"),
    ),
  ) catch {
    @build.InvalidBuildConfig(message) => {
      rejected = true
      assert_true(message.contains("example#Missing"))
    }
    _ => fail("Expected failing build plugin")
  }
  assert_true(rejected)
}

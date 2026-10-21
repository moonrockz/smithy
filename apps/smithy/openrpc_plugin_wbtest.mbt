///|
test "OpenRPC build plugin writes one deterministic artifact and fails invalid selection" {
  let loaded = @rpc.loader()
    .add_idl(
      "api.smithy",
      (
        #|$version: "2"
        #|namespace example
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named", nullResult: true)
        #|operation Op {}
      ),
    )
    .assemble()
  let model = loaded.model.unwrap()
  let settings = @json.parse("{\"service\":\"example#Api\"}")
  let first = openrpc_plugin(model, settings)
  assert_eq(first.length(), 1)
  assert_true(
    @json.parse(first["openrpc.json"])
    is { "openrpc": String("1.3.2"), "methods": Array(methods), .. } &&
    methods.length() == 1,
  )
  assert_eq(
    first["openrpc.json"],
    openrpc_plugin(model, settings)["openrpc.json"],
  )
  let mut rejected = false
  ignore(
    openrpc_plugin(model, @json.parse("{\"service\":\"example#Missing\"}")),
  ) catch {
    @build.InvalidBuildConfig(message) => {
      rejected = true
      assert_true(message.contains("example#Missing"))
    }
    _ => fail("Expected failing build plugin")
  }
  assert_true(rejected)
}

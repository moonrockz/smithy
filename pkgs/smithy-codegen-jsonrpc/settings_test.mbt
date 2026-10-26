///|
let payment_model : String =
  #|$version: "2"
  #|namespace example
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#jsonRpcProtocol
  #|use smithy.rpc#method
  #|@jsonRpcProtocol(versions: ["2.0"], peers: [{ name: "pos", accepts: Pos }, { name: "terminal", accepts: Terminal }])
  #|structure Protocol {}
  #|@jsonRpc(versions: ["2.0"])
  #|service Terminal { version: "1", operations: [Ping] }
  #|@jsonRpc(versions: ["2.0"])
  #|service Pos { version: "1", operations: [Show] }
  #|@method(name: "ping", params: "named", nullResult: true)
  #|operation Ping {}
  #|@method(name: "show", params: "named", kind: "notification")
  #|operation Show { input: ShowInput }
  #|structure ShowInput { @required text: String }

///|
fn plugin_context(
  settings : Json,
) -> @codegen.PluginContext raise @codegen.CodegenError {
  let loaded = @rpc.loader()
    .add_idl("contract.smithy", payment_model)
    .assemble()
  @codegen.PluginContext::from_build(loaded.model.unwrap(), settings)
}

///|
fn settings_error(settings : Json, extra? : Array[String]) -> String raise {
  try
    @jsonrpc.PeerSettings::from_context(
      plugin_context(settings),
      extra=extra.unwrap_or([]),
    )
  catch {
    error => error.message()
  } noraise {
    _ => fail("expected a settings error")
  }
}

///|
test "a protocol peer selects the service it accepts and the service it calls" {
  let settings = @jsonrpc.PeerSettings::from_context(
    plugin_context({
      "service": "example#Terminal",
      "protocol": "example#Protocol",
      "peer": "pos",
    }),
  )
  assert_eq(settings.peer.name.to_string(), "pos")
  assert_eq(settings.peer.accepts.unwrap().service, id("example#Pos"))
  assert_eq(settings.peer.calls.unwrap().service, id("example#Terminal"))
  assert_eq(settings.description.protocol, Some(id("example#Protocol")))
  assert_eq(settings.transports, [
    @jsonrpc.Stdio,
    @jsonrpc.Http,
    @jsonrpc.WebSocket,
  ])
  assert_eq(settings.services(), [id("example#Pos"), id("example#Terminal")])
}

///|
test "a plain service has the implicit client and server peers" {
  let server = @jsonrpc.PeerSettings::from_context(
    plugin_context({
      "service": "example#Terminal",
      "peer": "server",
      "transports": ["stdio"],
    }),
  )
  assert_eq(server.peer.accepts.unwrap().service, id("example#Terminal"))
  assert_eq(server.peer.calls, None)
  assert_eq(server.transports, [@jsonrpc.Stdio])
  let client = @jsonrpc.PeerSettings::from_context(
    plugin_context({ "service": "example#Terminal", "peer": "client" }),
  )
  assert_eq(client.peer.accepts, None)
  assert_eq(client.peer.calls.unwrap().service, id("example#Terminal"))
  assert_eq(client.services(), [id("example#Terminal")])
}

///|
test "bad settings give first-person messages" {
  assert_eq(
    settings_error({ "service": "example#Terminal" }),
    "I expected setting `peer`, the name of the peer to generate.",
  )
  assert_eq(
    settings_error({ "service": "example#Terminal", "peer": "pos" }),
    "I expected setting `peer` to be `client` or `server` for service `example#Terminal`, found `pos`.",
  )
  assert_eq(
    settings_error({
      "service": "example#Terminal",
      "protocol": "example#Protocol",
      "peer": "kiosk",
    }),
    "I expected setting `peer` to name a peer of protocol `example#Protocol` (pos, terminal), found `kiosk`.",
  )
  assert_eq(
    settings_error({
      "service": "example#Other",
      "protocol": "example#Protocol",
      "peer": "pos",
    }),
    "I could not find service shape `example#Other` in the model.",
  )
  assert_eq(
    settings_error({
      "service": "example#Terminal",
      "peer": "server",
      "transports": ["stdio", "carrier-pigeon"],
    }),
    "I expected each transport in setting `transports` to be `stdio`, `http` or `websocket`, found `carrier-pigeon`.",
  )
  assert_eq(
    settings_error({
      "service": "example#Terminal",
      "peer": "server",
      "transports": ["stdio", "stdio"],
    }),
    "I found transport `stdio` twice in setting `transports`.",
  )
  assert_eq(
    settings_error({ "service": "example#Terminal", "peer": "server", "x": 1 }),
    "I found unknown setting `x`.",
  )
  // A setting of the language generator is allowed when it names it.
  let _ = @jsonrpc.PeerSettings::from_context(
    plugin_context({
      "service": "example#Terminal",
      "peer": "server",
      "module": "example/terminal",
    }),
    extra=["module"],
  )
}

///|
test "a protocol that does not name the service is refused" {
  let source = payment_model +
    "\n@jsonRpc(versions: [\"2.0\"])\nservice Lone { version: \"1\" }\n"
  let ctx = @codegen.PluginContext::from_build(model(source), {
    "service": "example#Lone",
    "protocol": "example#Protocol",
    "peer": "pos",
  })
  try @jsonrpc.PeerSettings::from_context(ctx) catch {
    error =>
      assert_eq(
        error.message(),
        "I expected setting `service` to name a service of protocol `example#Protocol` (example#Pos, example#Terminal), found `example#Lone`.",
      )
  } noraise {
    _ => fail("expected a settings error")
  }
}

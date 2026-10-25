///|
fn model(source : String) -> @smithy.Model raise {
  let loaded = @rpc.loader().add_idl("contract.smithy", source).assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  model
}

///|
fn id(text : String) -> @smithy.ShapeId {
  @smithy.ShapeId::parse(text).unwrap()
}

///|
test "service description uses prepared methods and implicit peers" {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#method
    #|use smithy.rpc#rpcError
    #|@jsonRpc(versions: ["2.0"])
    #|service Api { version: "1", operations: [Z, A] }
    #|@method(name: "z", params: "named", nullResult: true)
    #|operation Z {}
    #|@method(name: "alpha", params: "either", positional: ["value"], resultMember: "value")
    #|operation A { input: Input, output: Output, errors: [Failed] }
    #|structure Input { @required value: BigDecimal }
    #|structure Output { @required value: BigDecimal }
    #|@error("client")
    #|@rpcError(code: 1001, dataMember: "reason")
    #|structure Failed { @required reason: String }
  let description = @jsonrpc.Description::for_service(
    model(source),
    id("example#Api"),
    @rpc.V2_0,
  )
  assert_eq(description.protocol, None)
  assert_eq(description.peers.map(p => p.name.to_string()), ["client", "server"])
  assert_eq(description.peers[0].accepts, None)
  let service = description.peers[1].accepts.unwrap()
  assert_eq(service.service, id("example#Api"))
  assert_eq(service.methods.map(m => m.name.to_string()), ["alpha", "z"])
  assert_eq(service.methods[0].positional, [id("example#Input$value")])
  assert_eq(
    service.methods[0].result,
    @rpc.OutputMember(id("example#Output$value")),
  )
  assert_eq(
    service.methods[0].errors[0].data,
    Some(id("example#Failed$reason")),
  )
  assert_eq(service.methods[0].errors[0].code.to_string(), "1001")
  assert_eq(service.methods[1].result, @rpc.NullResult)
  assert_true(service.shapes.contains(id("example#Input$value")))
}

///|
test "protocol description keeps peer direction and prepared session rules" {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#jsonRpcProtocol
    #|use smithy.rpc#jsonRpcSession
    #|use smithy.rpc#jsonRpcLifecycle
    #|use smithy.rpc#jsonRpcCancels
    #|use smithy.rpc#method
    #|@jsonRpcProtocol(versions: ["2.0"], peers: [{name: "terminal", accepts: Api}, {name: "pos", accepts: Pos}])
    #|@jsonRpcSession(states: ["starting", "ready"], capabilities: [{name: "tips", method: "init", pointer: "/tips"}], refusals: [{states: ["starting"], code: -32014}], capabilityRefusal: -32013)
    #|structure Link {}
    #|@jsonRpc(versions: ["2.0"])
    #|service Api { version: "1", operations: [Init, Pay, Cancel] }
    #|@jsonRpc(versions: ["2.0"])
    #|service Pos { version: "1", operations: [Display] }
    #|@method(name: "init", params: "named")
    #|@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "ready")
    #|operation Init { output: Capabilities }
    #|structure Capabilities { tips: Boolean }
    #|@method(name: "pay", params: "named")
    #|@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["tips"])
    #|operation Pay {}
    #|@method(name: "cancel", params: "either", positional: ["requestId"])
    #|@jsonRpcCancels(idMember: "requestId", code: 1009)
    #|operation Cancel { input: CancelInput }
    #|structure CancelInput { @jsonName("id") requestId: String }
    #|@method(name: "display", params: "named")
    #|operation Display {}
  let description = @jsonrpc.Description::for_protocol(
    model(source),
    id("example#Link"),
    @rpc.V2_0,
  )
  assert_eq(description.protocol, Some(id("example#Link")))
  assert_eq(description.peers.map(p => p.name.to_string()), ["pos", "terminal"])
  let terminal = description
    .peer(@rpc.PeerName::parse("terminal").unwrap())
    .unwrap()
  assert_eq(terminal.accepts.unwrap().service, id("example#Api"))
  assert_eq(terminal.calls.unwrap().service, id("example#Pos"))
  assert_eq(description.peer(@rpc.PeerName::parse("other").unwrap()), None)
  let session = description.session.unwrap()
  assert_eq(session.states.map(s => s.to_string()), ["starting", "ready"])
  assert_eq(session.capabilities[0].name, "tips")
  assert_eq(session.capabilities[0].pointer.to_string(), "/tips")
  assert_eq(session.refusals[0].state.to_string(), "starting")
  assert_eq(session.refusals[0].code.to_string(), "-32014")
  assert_eq(session.capability_refusal.unwrap().to_string(), "-32013")
  let pay = session.methods
    .iter()
    .find_first(m => m.method_name.to_string() == "pay")
    .unwrap()
  assert_eq(pay.allowed.unwrap().map(s => s.to_string()), ["ready"])
  assert_eq(pay.requires, ["tips"])
  let cancel = session.methods
  .iter()
  .find_first(m => m.method_name.to_string() == "cancel")
  .unwrap().cancels.unwrap()
  assert_eq(cancel.wire_name, "requestId")
  assert_eq(cancel.position, Some(0))
  assert_eq(cancel.code.unwrap().to_string(), "1009")
}

///|
test "generation keeps effective value policies and prepared wire member names" {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#method
    #|use smithy.rpc#unknownMembers
    #|@unknownMembers("ignore")
    #|@jsonRpc(versions: ["2.0"])
    #|service Api { version: "1", operations: [Op] }
    #|@method(name: "op", params: "named")
    #|operation Op { input: Input, output: Output }
    #|structure Input { @required @jsonName("wire") value: Nested }
    #|@unknownMembers("reject")
    #|structure Nested { child: String }
    #|structure Output { result: Nested }
  let description = @jsonrpc.Description::for_service(
    model(source),
    id("example#Api"),
    @rpc.V2_0,
    config=@validation.Config::new(member_names=@validation.JsonName),
  )
  let service = description.peers[1].accepts.unwrap()
  let input = service.values
    .iter()
    .find_first(s => s.shape == id("example#Input"))
    .unwrap()
  assert_eq(input.unknown_members, @validation.Ignore)
  assert_eq(input.members[0].wire_name, "wire")
  assert_eq(input.members[0].shape, id("example#Input$value"))
  assert_true(input.members[0].required)
  let nested = service.values
    .iter()
    .find_first(s => s.shape == id("example#Nested"))
    .unwrap()
  assert_eq(nested.unknown_members, @validation.Reject)
  assert_eq(service.values.map(s => s.shape.to_string()), [
    "example#Input", "example#Nested", "example#Output",
  ])
}

///|
test "generated peers ignore unknown fields unless the model or config sets a policy" {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#method
    #|@jsonRpc(versions: ["2.0"])
    #|service Api { version: "1", operations: [Op] }
    #|@method(name: "op", params: "named")
    #|operation Op { input: Input }
    #|structure Input { value: String }
  let model = model(source)
  let generated = @jsonrpc.Description::for_service(
    model,
    id("example#Api"),
    @rpc.V2_0,
  )
  assert_eq(
    generated.peers[1].accepts.unwrap().values[0].unknown_members,
    @validation.Ignore,
  )
  let explicit = @jsonrpc.Description::for_service(
    model,
    id("example#Api"),
    @rpc.V2_0,
    config=@validation.Config::new(),
  )
  assert_eq(
    explicit.peers[1].accepts.unwrap().values[0].unknown_members,
    @validation.Reject,
  )
}

///|
test "description keeps codec config for unions and timestamps" {
  let source =
    #|$version: "2"
    #|namespace example
    #|use smithy.rpc#jsonRpc
    #|use smithy.rpc#method
    #|@jsonRpc(versions: ["2.0"])
    #|service Api { version: "1", operations: [Op] }
    #|@method(name: "op", params: "named")
    #|operation Op { input: Input }
    #|structure Input { choice: Choice, time: Timestamp }
    #|union Choice { @jsonName("wire") original: String }
  let model = model(source)
  for mode in [@validation.Smithy, @validation.JsonName] {
    let generated = @jsonrpc.Description::for_service(
      model,
      id("example#Api"),
      @rpc.V2_0,
      config=@validation.Config::new(
        member_names=mode,
        timestamp_format=@validation.DateTime,
      ),
    )
    let service = generated.peers[1].accepts.unwrap()
    assert_eq(service.value_config.member_names, mode)
    assert_eq(service.value_config.timestamp_format, @validation.DateTime)
  }
}

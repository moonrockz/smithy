///|
test "modeled examples map positional names scalar null results and error data" {
  let model = api_model(
    extra=(
      #|apply Subtract @examples([
      #| {title: "subtract", input: {left: 7, right: 3}, output: {value: 4}},
      #| {title: "bad", input: {left: 7}, error: {shapeId: "demo#Problem", content: {detail: "bad input"}}}
      #|])
      #|apply Clear @examples([{title: "cleared", input: {}, output: {}}])
      #|apply List @examples([{title: "listed", input: {}, output: {items: [{name: "first"}]}}])
    ),
  )
  let document = @openrpc.convert(
    model,
    @openrpc.Config::new(
      @openrpc.ServiceId::parse("demo#Api").unwrap(),
      member_names=@validation.JsonName,
    ),
  )
  let subtract = method_(document, "subtract")
  assert_eq(
    subtract["examples"],
    @json.parse(
      "[{\"name\":\"subtract\",\"params\":[{\"name\":\"R\",\"value\":3},{\"name\":\"L\",\"value\":7}],\"result\":{\"name\":\"result\",\"value\":4}}]",
    ),
  )
  assert_true(
    subtract["x-smithy-error-examples"] is Array(values) && values.length() == 1,
  )
  guard method_(document, "clear")["examples"] is Array(examples) else {
    fail("Expected null result example")
  }
  assert_eq(object(object(examples[0])["result"])["value"], Json::null())
  guard method_(document, "list")["examples"] is Array(listed) else {
    fail("Expected array result example")
  }
  assert_eq(
    object(object(listed[0])["result"])["value"],
    @json.parse("[{\"N\":\"first\"}]"),
  )
}

///|
test "exported examples retain large exact integers rather than rounding through doubles" {
  let loaded = @rpc.loader()
    .add_idl(
      "exact.smithy",
      (
        #|$version: "2"
        #|namespace exact
        #|use smithy.rpc#jsonRpc
        #|use smithy.rpc#method
        #|@jsonRpc(versions: ["2.0"])
        #|service Api { version: "1", operations: [Op] }
        #|@method(name: "op", params: "named", resultMember: "value")
        #|@examples([{title:"exact",input:{},output:{value:9007199254740993}}])
        #|operation Op { output: Output }
        #|structure Output { value: BigInteger }
      ),
    )
    .assemble()
  guard loaded.model is Some(model) else {
    fail(loaded.diagnostics.map(d => d.message).join("\n"))
  }
  let document = @openrpc.convert(
    model,
    @openrpc.Config::new(@openrpc.ServiceId::parse("exact#Api").unwrap()),
  )
  guard method_(document, "op")["examples"] is Array(examples) else {
    fail("Expected exact result example")
  }
  assert_eq(
    object(object(examples[0])["result"])["value"].stringify(),
    "9007199254740993",
  )
}

///|
test "invalid modeled examples fail with the affected operation instead of publishing contradictions" {
  let model = api_model(
    extra=(
      #|apply Subtract @examples([{title: "bad", input: {left: -1}, output: {value: 4}}])
    ),
  )
  let mut rejected = false
  ignore(@openrpc.convert(model, config())) catch {
    @openrpc.InvalidContract(id, message) => {
      rejected = true
      assert_eq(id.to_string(), "demo#Subtract")
      assert_true(message.contains("example"))
    }
    _ => fail("Expected invalid example failure")
  }
  assert_true(rejected)
}

///|
test "unknown example members fail before positional selection or JSON name remapping" {
  for mode in ["positional", "named", "either"] {
    let loaded = @rpc.loader()
      .add_idl(
        "unknown.smithy",
        (
          #|$version: "2"
          #|namespace unknown
          #|use smithy.rpc#jsonRpc
          #|use smithy.rpc#method
          #|@jsonRpc(versions: ["2.0"])
          #|service Api { version: "1", operations: [Op] }
        ) +
        "\n@method(name: \"op\", params: \"" +
        mode +
        "\"" +
        (if mode == "named" { "" } else { ", positional: [\"value\"]" }) +
        ", nullResult: true)\n" +
        (
          #|@examples([{title:"unknown",input:{value:"hello",typo:"silently lost"}}])
          #|operation Op { input: Input }
          #|structure Input { @jsonName("typo") value: String }
        ),
      )
      .assemble()
    let model = loaded.model.unwrap()
    for naming in [@validation.Smithy, @validation.JsonName] {
      let mut rejected = false
      ignore(
        @openrpc.convert(
          model,
          @openrpc.Config::new(
            @openrpc.ServiceId::parse("unknown#Api").unwrap(),
            member_names=naming,
          ),
        ),
      ) catch {
        @openrpc.InvalidContract(_, message) => {
          rejected = true
          assert_true(message.contains("typo"))
        }
        _ => fail("Expected invalid modeled example")
      }
      assert_true(rejected)
    }
  }
}

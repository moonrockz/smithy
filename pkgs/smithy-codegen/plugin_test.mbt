///|
fn plugin_model() -> @smithy.Model {
  @smithy.Loader::new()
  .add_idl(
    "a.smithy", "$version: \"2\"\nnamespace example\nservice Weather {\n  version: \"1\"\n}\nstructure Plain {}\n",
  )
  .assemble().model.unwrap()
}

///|
fn plugin_error_message(model : @smithy.Model, settings : Json) -> String {
  try @codegen.PluginContext::from_build(model, settings) catch {
    error => error.message()
  } noraise {
    _ => ""
  }
}

///|
test "from_build reads the service" {
  let context = @codegen.PluginContext::from_build(
    plugin_model(),
    @json.parse("{\"service\":\"example#Weather\",\"flag\":true}"),
  )
  assert_eq(context.service.id.to_string(), "example#Weather")
  assert_eq(context.settings.get("flag"), Some(Json::boolean(true)))
  assert_true(context.closure().contains(context.service.id))
}

///|
test "from_build rejects a missing service" {
  assert_eq(
    plugin_error_message(
      plugin_model(),
      @json.parse("{\"service\":\"example#Missing\"}"),
    ),
    "I could not find service shape `example#Missing` in the model.",
  )
}

///|
test "from_build rejects a non-service shape" {
  assert_eq(
    plugin_error_message(
      plugin_model(),
      @json.parse("{\"service\":\"example#Plain\"}"),
    ),
    "I expected `example#Plain` to be a service shape.",
  )
}

///|
test "from_build rejects bad settings" {
  assert_eq(
    plugin_error_message(plugin_model(), @json.parse("[]")),
    "I expected the plugin settings to be an object.",
  )
  assert_eq(
    plugin_error_message(plugin_model(), @json.parse("{\"service\":42}")),
    "I expected a service shape ID in setting `service`.",
  )
  assert_eq(
    plugin_error_message(plugin_model(), @json.parse("{}")),
    "I expected a service shape ID in setting `service`.",
  )
  assert_eq(
    plugin_error_message(plugin_model(), @json.parse("{\"service\":\"bad\"}")),
    "I expected a service shape ID in setting `service`.",
  )
}

///|
test "check_settings rejects unknown keys" {
  let context = @codegen.PluginContext::from_build(
    plugin_model(),
    @json.parse(
      "{\"service\":\"example#Weather\",\"zeta\":1,\"alfa\":2,\"name\":\"x\",\"item\":3}",
    ),
  )
  context.check_settings(["alfa", "zeta", "name", "item"])
  let message = try context.check_settings(["name"]) catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(message, "I found unknown setting `alfa`.")
  assert_eq(context.setting_string("name"), Some("x"))
  assert_eq(context.setting_string("none"), None)
  let wrong = try context.setting_string("item") catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(wrong, "I expected a string for setting `item`.")
}

///|
test "build_plugin turns codegen errors into build errors" {
  let run = @codegen.build_plugin(_context => { "a.txt": "text" })
  let files = run(
    plugin_model(),
    @json.parse("{\"service\":\"example#Weather\"}"),
  )
  assert_eq(files.get("a.txt"), Some("text"))
  let message = try
    run(plugin_model(), @json.parse("{\"service\":\"example#Missing\"}"))
  catch {
    @build.InvalidBuildConfig(msg) => msg
    _ => "other"
  } noraise {
    _ => ""
  }
  assert_true(message.contains("example#Missing"))
  let inner = @codegen.build_plugin(_context => {
    raise @codegen.StateError("I stopped.")
  })
  let inner_message = try
    inner(plugin_model(), @json.parse("{\"service\":\"example#Weather\"}"))
  catch {
    @build.InvalidBuildConfig(msg) => msg
    _ => "other"
  } noraise {
    _ => ""
  }
  assert_eq(inner_message, "I stopped.")
}

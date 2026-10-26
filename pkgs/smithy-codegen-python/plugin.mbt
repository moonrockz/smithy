///|
/// The settings of the Python plugin, after the shared settings.
let python_settings : Array[String] = ["package", "integrations"]

///|
/// The pinned versions of the dependencies of the generated package. The
/// runtime in `runtimes/python` is tested with these versions.
let pydantic_version : String = "2.14.1"

///|
let httpx_version : String = "0.28.1"

///|
let websockets_version : String = "17.3"

///|
let fastapi_version : String = "0.162.0"

///|
let uvicorn_version : String = "0.54.0"

///|
let uv_build_version : String = "0.13.5"

///|
/// An integration that adds an optional module to the output.
priv enum PyIntegration {
  FastApi
} derive(Eq)

///|
fn read_integrations(
  plugin : @codegen.PluginContext,
) -> Array[PyIntegration] raise @codegen.CodegenError {
  guard plugin.settings.get("integrations") is Some(value) else { return [] }
  guard value is Array(items) else {
    raise @codegen.InvalidSettings(
      "I expected an array of integrations in setting `integrations`.",
    )
  }
  let out : Array[PyIntegration] = []
  for item in items {
    let integration = match item {
      String("fastapi") => FastApi
      String(text) =>
        raise @codegen.InvalidSettings(
          "I expected each integration in setting `integrations` to be `fastapi`, found `\{text}`.",
        )
      _ =>
        raise @codegen.InvalidSettings(
          "I expected each integration in setting `integrations` to be a string.",
        )
    }
    if out.contains(integration) {
      raise @codegen.InvalidSettings(
        "I found integration `fastapi` twice in setting `integrations`.",
      )
    }
    out.push(integration)
  }
  out
}

///|
/// The symbol of a shape: its class in `.models`, or its exception in
/// `.errors` for an error shape.
fn symbol_provider(names : @codegen.ServiceNames) -> @codegen.SymbolProvider {
  @codegen.SymbolProvider::new(shape => {
    let name = class_name(names.shape_name(shape.id))
    guard @codegen.SymbolName::parse(name) is Some(symbol_name) else {
      raise @codegen.InvalidSettings(
        "I could not make a Python class name for shape `\{shape.id}`.",
      )
    }
    let module_ = if shape.trait_value("smithy.api#error") is Some(_) {
      errors_module
    } else {
      models_module
    }
    @codegen.Symbol::new(symbol_name, ns=module_namespace(module_))
  })
}

///|
/// Generate a Python JSON-RPC peer. Settings: `service`, `protocol`, `peer`,
/// `transports` (see `PeerSettings`), `package`, the Python package name of
/// the output, such as `payment_terminal`, and `integrations` (optional),
/// such as `["fastapi"]`.
pub fn run(
  plugin : @codegen.PluginContext,
) -> Map[String, String] raise @codegen.CodegenError {
  let settings = @jsonrpc.PeerSettings::from_context(
    plugin,
    extra=python_settings,
  )
  guard plugin.setting_string("package") is Some(package_name) else {
    raise @codegen.InvalidSettings(
      "I expected setting `package`, the Python package name of the output.",
    )
  }
  check_package_name(package_name)
  let integrations = read_integrations(plugin)
  let names = settings.names(plugin.model)
  let values : Map[@smithy.ShapeId, @validation.StructureContract] = Map([])
  let mut value_config = @validation.Config::new()
  for service in [settings.peer.accepts, settings.peer.calls] {
    guard service is Some(description) else { continue }
    value_config = description.value_config
    for contract in description.values {
      if !values.contains(contract.shape) {
        values[contract.shape] = contract
      }
    }
  }
  let docs : Map[String, String] = Map([])
  let render = (writer : @codegen.CodeWriter) => {
    let module_ = writer.ns().text
    let doc = docs.get(module_).unwrap_or("A generated module.")
    let imports = render_imports(writer.imports(), package_name, true)
    let body = writer.to_string().trim_start(chars="\n").to_owned()
    // isort puts two blank lines before a class or a function, else one.
    let gap = if body.has_prefix("class ") ||
      body.has_prefix("def ") ||
      body.has_prefix("async def ") ||
      body.has_prefix("@") {
      "\n\n"
    } else {
      "\n"
    }
    tidy(
      generated_header +
      "\n\"\"\"" +
      doc_text(doc) +
      "\"\"\"\n\n" +
      imports +
      gap +
      body,
    )
  }
  let provider = symbol_provider(names)
  let director : @codegen.DirectedCodegen[Gen] = @codegen.DirectedCodegen::new(
    create_symbol_provider=(_, _) => provider,
    create_context=info => {
      model: info.model,
      settings,
      names,
      package_name,
      delegator: @codegen.WriterDelegator::new(
        info.provider,
        factory=(_, ns) => @codegen.CodeWriter::new(ns~, indent_text="    "),
        render~,
      ),
      values,
      value_config,
      written: Map([]),
      errors: [],
      structures: [],
      type_names: Map([]),
      docs,
    },
    delegator=gen => gen.delegator,
    generate_service=(_, _) => (),
    generate_structure=(gen, shape) => gen.write_shape(shape),
    generate_error=(gen, shape) => gen.write_shape(shape),
    generate_union=(gen, shape) => gen.write_shape(shape),
    generate_enum=(gen, shape) => gen.write_shape(shape),
    generate_int_enum=(gen, shape) => gen.write_shape(shape),
    customize_before_integrations=gen => {
      // The director walks the closure of the `service` setting. A protocol
      // peer also needs the shapes of the other service.
      for service in settings.services() {
        let order = @codegen.topological_order(
          gen.model,
          @codegen.service_closure(gen.model, service),
        )
        for id in order {
          if gen.model.shapes.get(id) is Some(shape) {
            gen.write_shape(shape)
          }
        }
      }
      gen.write_errors()
      gen.write_handler()
      gen.write_client()
      gen.write_session()
      gen.write_init()
      gen.write_test()
    },
  )
  let files = @codegen.run_codegen(plugin, director)
  files["pyproject.toml"] = pyproject_file(package_name, settings, integrations)
  files["\{package_name}/py.typed"] = ""
  for entry in runtime_files {
    files["\{package_name}/_runtime/" + entry.0] = entry.1
  }
  files
}

///|
/// The text of `pyproject.toml`, with the pinned dependencies of the runtime
/// and the checks of the generated code.
fn pyproject_file(
  package_name : String,
  settings : @jsonrpc.PeerSettings,
  integrations : Array[PyIntegration],
) -> String {
  let dependencies = ["pydantic==\{pydantic_version}"]
  if settings.transports.contains(Http) {
    dependencies.push("httpx==\{httpx_version}")
  }
  if settings.transports.contains(WebSocket) {
    dependencies.push("websockets==\{websockets_version}")
  }
  if integrations.contains(FastApi) {
    dependencies.push("fastapi==\{fastapi_version}")
    dependencies.push("uvicorn==\{uvicorn_version}")
  }
  dependencies.sort_by((a, b) => a.lexical_compare(b))
  let listed = dependencies.map(d => "    \{py_string(d)},\n").join("")
  let peer = settings.peer.name.to_string()
  (
    $|[project]
    $|name = "\{distribution_name(package_name)}"
    $|version = "0.0.0"
    $|description = "The generated JSON-RPC peer \{doc_text(peer)}."
    $|requires-python = ">=3.11"
    $|dependencies = [
    $|\{listed}]
    $|
    $|[dependency-groups]
    $|dev = [
    $|    "pyright==1.1.414",
    $|    "pytest==9.1.1",
    $|    "ruff==0.17.2",
    $|]
    $|
    $|[build-system]
    $|requires = ["uv_build==\{uv_build_version}"]
    $|build-backend = "uv_build"
    $|
    $|[tool.uv.build-backend]
    $|module-name = "\{package_name}"
    $|module-root = ""
    $|
    $|[tool.pyright]
    $|include = ["\{package_name}", "tests"]
    $|typeCheckingMode = "strict"
    $|pythonVersion = "3.11"
    $|
    $|[tool.ruff]
    $|target-version = "py311"
    $|line-length = 100
    $|
    $|[tool.ruff.lint]
    $|select = ["E", "F", "W", "I", "B", "UP", "ASYNC", "RUF", "SIM", "PL", "T20"]
    $|ignore = ["E501", "PLR0911", "PLR0912", "PLR0913", "PLR0915", "PLR2004"]
    $|
    $|[tool.pytest.ini_options]
    $|testpaths = ["tests"]
    $|pythonpath = ["."]
    $|
  )
}

///|
/// Write the package module: it gives the session functions.
fn Gen::write_init(self : Gen) -> Unit raise @codegen.CodegenError {
  let doc = "The generated JSON-RPC peer `\{self.settings.peer.name.to_string()}`."
  self.with_module(".__init__", doc, w => {
    let rules = use_name(w, ".session", "session_rules")
    let peer = use_name(w, ".session", "new_peer")
    w.blank_line()
    w.write("__all__ = [$L, $L]", args=[
      Text(py_string(peer)),
      Text(py_string(rules)),
    ])
  })
}

///|
/// A test that builds the session rules and a peer, and reads and writes a
/// model that has no required member.
fn Gen::write_test(self : Gen) -> Unit raise @codegen.CodegenError {
  let path = @codegen.OutputPath::parse("tests/test_generated.py").unwrap()
  let ns = module_namespace("tests.test_generated")
  let package_name = self.package_name
  self.docs[ns.text] = "The checks of the generated peer `\{self.settings.peer.name.to_string()}`."
  let peer_name = self.settings.peer.name.to_string()
  let mut sample : String? = None
  for id in self.structures {
    let fields = self.fields(self.shape(id))
    if fields.iter().all(field => !field.required) {
      sample = Some(self.class_of(id))
      break
    }
  }
  self.delegator.use_file_writer(path, ns, w => {
    let rules = use_name(w, "\{package_name}.session", "session_rules")
    let new_peer = use_name(w, "\{package_name}.session", "new_peer")
    w.blank_line()
    w.blank_line()
    w.write("def test_session_rules_and_peer() -> None:")
    w.indent()
    w.write("assert $L().states", args=[Text(rules)])
    w.write("assert $L().self_name == $L", args=[
      Text(new_peer),
      Text(py_string(peer_name)),
    ])
    w.dedent()
    if sample is Some(name) {
      let model = use_name(w, "\{package_name}.models", name)
      let to_wire = use_name(w, "\{package_name}._runtime", "to_wire")
      w.blank_line()
      w.blank_line()
      w.write("def test_model_round_trip() -> None:")
      w.indent()
      w.write("value = $L.model_validate({})", args=[Text(model)])
      w.write("assert $L(value) == {}", args=[Text(to_wire)])
      w.write("assert $L.model_validate($L(value)) == value", args=[
        Text(model),
        Text(to_wire),
      ])
      w.dedent()
    }
  })
}

///|
/// The plugin for the build runner. Register it as `python-jsonrpc-codegen`.
pub fn plugin(
  model : @smithy.Model,
  settings : Json,
) -> Map[String, String] raise @build.BuildError {
  @codegen.build_plugin(run)(model, settings)
}

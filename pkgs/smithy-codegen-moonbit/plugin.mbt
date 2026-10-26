///|
/// The settings of the MoonBit plugin, after the shared settings.
let moonbit_settings : Array[String] = ["module"]

///|
/// The symbol of the runtime package. Each generated file imports it.
fn runtime_symbol(module_name : String) -> @codegen.Symbol {
  @codegen.Symbol::new(
    @codegen.SymbolName::parse("Peer").unwrap(),
    ns=module_namespace(module_name + "/rpc"),
  )
}

///|
/// The import policy of MoonBit: a foreign symbol is `@pkg.Name`, and the
/// package goes into `moon.pkg`. The qualifier is the last path segment.
fn moonbit_imports() -> @codegen.ImportPolicy {
  @codegen.ImportPolicy::by_package(
    qualify=(qualifier, symbol) => {
      "@\{qualifier.to_string()}.\{symbol.name.to_string()}"
    },
    qualifier=ns => {
      let parts = ns.text.split("/").map(part => part.to_owned()).collect()
      @codegen.SymbolName::parse(parts[parts.length() - 1]).unwrap()
    },
    locals_block_qualifiers=false,
  )
}

///|
/// The symbol of a shape: its contextual type name in the root package of the
/// module. An error shape is in `errors.mbt`, another shape in `types.mbt`.
fn symbol_provider(
  names : @codegen.ServiceNames,
  module_name : String,
) -> @codegen.SymbolProvider {
  @codegen.SymbolProvider::new(shape => {
    let name = type_name(names.shape_name(shape.id))
    guard @codegen.SymbolName::parse(name) is Some(symbol_name) else {
      raise @codegen.InvalidSettings(
        "I could not make a MoonBit type name for shape `\{shape.id}`.",
      )
    }
    let path = if shape.trait_value("smithy.api#error") is Some(_) {
      errors_path()
    } else {
      types_path()
    }
    @codegen.Symbol::new(
      symbol_name,
      ns=module_namespace(module_name),
      definition=Some(path),
    )
  })
}

///|
/// Generate a MoonBit JSON-RPC peer. Settings: `service`, `protocol`, `peer`,
/// `transports` (see `PeerSettings`) and `module`, the MoonBit module name of
/// the output, such as `example/terminal`.
pub fn run(
  plugin : @codegen.PluginContext,
) -> Map[String, String] raise @codegen.CodegenError {
  let settings = @jsonrpc.PeerSettings::from_context(
    plugin,
    extra=moonbit_settings,
  )
  guard plugin.setting_string("module") is Some(module_name) else {
    raise @codegen.InvalidSettings(
      "I expected setting `module`, the MoonBit module name of the output.",
    )
  }
  check_module_name(module_name)
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
  let packages : Map[String, String] = Map([])
  let rpc = runtime_symbol(module_name)
  let render = (writer : @codegen.CodeWriter) => {
    for entry in writer.package_imports() {
      packages[entry.ns.text] = entry.qualifier.to_string()
    }
    generated_header + "\n\n" + tidy(writer.to_string())
  }
  let provider = symbol_provider(names, module_name)
  let director : @codegen.DirectedCodegen[Gen] = @codegen.DirectedCodegen::new(
    create_symbol_provider=(_, _) => provider,
    create_context=info => {
      model: info.model,
      settings,
      names,
      module_name,
      delegator: @codegen.WriterDelegator::new(
        info.provider,
        factory=(_, ns) => {
          let writer = @codegen.CodeWriter::new(
            ns~,
            indent_text="  ",
            imports=moonbit_imports(),
          )
          writer.add_import(rpc)
          writer
        },
        render~,
      ),
      values,
      value_config,
      written: Map([]),
      errors: [],
      type_names: Map([]),
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
      gen.write_test()
    },
  )
  let files = @codegen.run_codegen(plugin, director)
  files["moon.mod"] = module_file(module_name)
  files["moon.pkg"] = package_file(packages)
  for entry in runtime_files {
    files["rpc/" + entry.0] = entry.1
  }
  files
}

///|
/// The text with at most one blank line in a row and one newline at the end.
fn tidy(text : String) -> String {
  let out = StringBuilder()
  let mut blank = 0
  for line in text.split("\n") {
    if line.is_empty() {
      blank += 1
      continue
    }
    if out.to_string().length() > 0 {
      out.write_string(if blank > 0 { "\n\n" } else { "\n" })
    }
    blank = 0
    out.write_string(line.to_owned())
  }
  out.write_string("\n")
  out.to_string()
}

///|
/// The text of `moon.mod`, with the pinned dependencies of the runtime.
fn module_file(module_name : String) -> String {
  (
    $|name = "\{module_name}"
    $|
    $|version = "0.0.0"
    $|
    $|preferred_target = "native"
    $|
    $|warnings = "-implicit_impl_as_method"
    $|
    $|import {
    $|  "moonbitlang/async@\{async_version}",
    $|}
    $|
  )
}

///|
/// The text of the root `moon.pkg`: the packages that the files import, in
/// lexical order.
fn package_file(packages : Map[String, String]) -> String {
  let paths = packages.keys().collect()
  paths.sort_by((a, b) => a.lexical_compare(b))
  let out = StringBuilder()
  out.write_string("import {\n")
  for path in paths {
    out.write_string("  \"\{path}\" @\{packages[path]},\n")
  }
  out.write_string("}\n")
  out.to_string()
}

///|
/// A test that builds the session rules and a peer.
fn Gen::write_test(self : Gen) -> Unit raise @codegen.CodegenError {
  let path = @codegen.OutputPath::parse("session_wbtest.mbt").unwrap()
  self.with_file(path, w => {
    w.write("///|")
    w.write("test \"session rules and peer\" {")
    w.indent()
    w.write("let _ = session_rules()")
    w.write("let _ = new_peer()")
    w.dedent()
    w.write("}")
  })
}

///|
/// The plugin for the build runner. Register it as `moonbit-jsonrpc-codegen`.
pub fn plugin(
  model : @smithy.Model,
  settings : Json,
) -> Map[String, String] raise @build.BuildError {
  @codegen.build_plugin(run)(model, settings)
}

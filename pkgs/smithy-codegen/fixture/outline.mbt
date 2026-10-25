///|
/// The context of the outline generator: what the director gave and the
/// delegator that holds the writers.
priv struct OutlineCtx {
  info : @codegen.CreateContext
  delegator : @codegen.WriterDelegator
}

///|
/// Raise an error when a constant of this module is not valid.
fn[T] must(value : T?, what : String) -> T raise @codegen.CodegenError {
  match value {
    Some(value) => value
    None => raise @codegen.InvalidSettings("I could not make \{what}.")
  }
}

///|
fn collections_dependency() -> @codegen.SymbolDependency raise @codegen.CodegenError {
  {
    package: must(
      @codegen.PackageName::parse("outline-collections"),
      "package name `outline-collections`",
    ),
    version: "1.0.0",
    kind: Runtime,
  }
}

///|
/// The symbol of a shape. A shape of `smithy.api` has the root namespace and no
/// definition. Another shape is defined in a file of its namespace. A list or
/// a map needs the runtime package `outline-collections`.
fn outline_symbol(
  shape : @smithy.Shape,
) -> @codegen.Symbol raise @codegen.CodegenError {
  let name = must(
    @codegen.SymbolName::parse(shape.id.name()),
    "a symbol name for shape `\{shape.id}`",
  )
  let namespace = shape.id.namespace()
  if namespace == "smithy.api" {
    return @codegen.Symbol::new(name)
  }
  let path = namespace.replace_all(old=".", new="/") +
    "/" +
    shape.id.name() +
    ".outline"
  let symbol = @codegen.Symbol::new(
    name,
    namespace=must(
      @codegen.Namespace::parse(namespace, separator="."),
      "a namespace for shape `\{shape.id}`",
    ),
    definition=Some(
      must(@codegen.OutputPath::parse(path), "an output path `\{path}`"),
    ),
  )
  match shape.body {
    List(_) | Map(..) => symbol.with_dependency(collections_dependency())
    _ => symbol
  }
}

///|
fn outline_provider(
  _model : @smithy.Model,
  _plugin : @codegen.PluginContext,
) -> @codegen.SymbolProvider {
  @codegen.SymbolProvider::new(outline_symbol).with_reserved_words(
    symbols=@codegen.ReservedWords::new(["Outline"]),
    members=@codegen.ReservedWords::new(["type", "use", "error"]),
  )
}

///|
/// The text of a file: one `use` line for each import, a blank line when there
/// are imports, then the text of the writer.
fn render_outline(writer : @codegen.CodeWriter) -> String {
  let out = StringBuilder()
  let imports = writer.imports()
  for entry in imports {
    let full = @codegen.Symbol::new(entry.name, namespace=entry.namespace).full_name()
    match entry.alias {
      Some(alias) => out.write_string("use \{full} as \{alias.to_string()}\n")
      None => out.write_string("use \{full}\n")
    }
  }
  if !imports.is_empty() {
    out.write_char('\n')
  }
  out.write_string(writer.to_string())
  out.to_string()
}

///|
/// The symbol of the shape that a member or an operation refers to.
fn target_symbol(
  ctx : OutlineCtx,
  id : @smithy.ShapeId,
) -> @codegen.TemplateValue raise @codegen.CodegenError {
  guard ctx.info.model.shapes.get(id) is Some(shape) else {
    raise @codegen.StateError(
      "I could not find shape `\{id}` in the model of the outline generator.",
    )
  }
  Sym(ctx.info.provider.to_symbol(shape))
}

///|
/// The symbol of the target of a member shape, for the member of a list or of a map.
fn member_target_symbol(
  ctx : OutlineCtx,
  id : @smithy.ShapeId,
) -> @codegen.TemplateValue raise @codegen.CodegenError {
  guard ctx.info.model.shapes.get(id) is Some(member) &&
    member.body is Member(target~) else {
    raise @codegen.StateError(
      "I could not find member shape `\{id}` in the model of the outline generator.",
    )
  }
  target_symbol(ctx, target)
}

///|
/// Write the file of a shape: the header section first, then the body.
fn write_shape(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
  body : (@codegen.CodeWriter) -> Unit raise @codegen.CodegenError,
) -> Unit raise @codegen.CodegenError {
  ctx.delegator.use_shape_writer(shape, writer => {
    writer.inject_section(@codegen.Section::new("header"))
    writer.push_state()
    body(writer)
    writer.pop_state()
  })
}

///|
/// The members of a shape as a record: the member name and the symbol of its
/// target, in the order of the model.
fn member_record(
  ctx : OutlineCtx,
  members : Array[@smithy.ShapeId],
) -> @codegen.TemplateValue raise @codegen.CodegenError {
  let fields : Map[String, @codegen.TemplateValue] = Map([])
  for id in members {
    guard ctx.info.model.shapes.get(id) is Some(member) &&
      member.body is Member(target~) else {
      raise @codegen.StateError(
        "I could not find member shape `\{id}` in the model of the outline generator.",
      )
    }
    fields[ctx.info.provider.to_member_name(member)] = target_symbol(
      ctx, target,
    )
  }
  Record(fields)
}

///|
fn generate_record(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
  keyword : String,
) -> Unit raise @codegen.CodegenError {
  let members = match shape.body {
    Structure(ids) | Union(ids) => ids
    _ => []
  }
  let symbol = ctx.info.provider.to_symbol(shape)
  write_shape(ctx, shape, writer => {
    writer.put_context("members", member_record(ctx, members))
    writer.write(
      "\{keyword} $T {\n${#members}\n    ${key:L}: ${value:T}\n${/members}\n}",
      args=[Sym(symbol)],
    )
  })
}

///|
fn generate_enum_like(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
  keyword : String,
) -> Unit raise @codegen.CodegenError {
  let ids = match shape.body {
    Enum(ids) | IntEnum(ids) => ids
    _ => []
  }
  let names : Array[@codegen.TemplateValue] = []
  for id in ids {
    guard ctx.info.model.shapes.get(id) is Some(member) else {
      raise @codegen.StateError(
        "I could not find member shape `\{id}` in the model of the outline generator.",
      )
    }
    names.push(Text(ctx.info.provider.to_member_name(member)))
  }
  let symbol = ctx.info.provider.to_symbol(shape)
  write_shape(ctx, shape, writer => {
    writer.put_context("names", List(names))
    writer.write("\{keyword} $T {\n${#names}\n    ${value:L}\n${/names}\n}", args=[
      Sym(symbol),
    ])
  })
}

///|
fn generate_list(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
) -> Unit raise @codegen.CodegenError {
  guard shape.body is List(member) else { return }
  let symbol = ctx.info.provider.to_symbol(shape)
  let target = member_target_symbol(ctx, member)
  write_shape(ctx, shape, writer => {
    writer.write("list $T of $T", args=[Sym(symbol), target])
  })
}

///|
fn generate_map(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
) -> Unit raise @codegen.CodegenError {
  guard shape.body is Map(key~, value~) else { return }
  let symbol = ctx.info.provider.to_symbol(shape)
  let key_symbol = member_target_symbol(ctx, key)
  let value_symbol = member_target_symbol(ctx, value)
  write_shape(ctx, shape, writer => {
    writer.write("map $T of $T to $T", args=[
      Sym(symbol),
      key_symbol,
      value_symbol,
    ])
  })
}

///|
fn generate_operation(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
) -> Unit raise @codegen.CodegenError {
  guard shape.body is Operation(input~, output~, errors~) else { return }
  let symbol = ctx.info.provider.to_symbol(shape)
  let input_symbol = target_symbol(ctx, input)
  let output_symbol = target_symbol(ctx, output)
  let error_symbols : Array[@codegen.TemplateValue] = []
  for id in errors {
    error_symbols.push(target_symbol(ctx, id))
  }
  write_shape(ctx, shape, writer => {
    writer.put_context("errors", List(error_symbols))
    writer.write(
      "operation $T($T) -> $T\n${?errors}\n    errors: ${#errors}${value:T}${^key.last}, ${/key.last}${/errors}\n${/errors}",
      args=[Sym(symbol), input_symbol, output_symbol],
    )
  })
}

///|
fn generate_service(
  ctx : OutlineCtx,
  shape : @smithy.Shape,
) -> Unit raise @codegen.CodegenError {
  guard shape.body is Service(operations~, ..) else { return }
  let symbol = ctx.info.provider.to_symbol(shape)
  let operation_symbols : Array[@codegen.TemplateValue] = []
  for id in operations {
    operation_symbols.push(target_symbol(ctx, id))
  }
  write_shape(ctx, shape, writer => {
    writer.put_context("operations", List(operation_symbols))
    writer.write(
      "service $T {\n${#operations}\n    operation ${value:T}\n${/operations}\n}",
      args=[Sym(symbol)],
    )
  })
}

///|
fn kind_text(kind : @codegen.DependencyKind) -> String {
  match kind {
    Runtime => "runtime"
    Test => "test"
    Build => "build"
  }
}

///|
/// Write `dependencies.txt` with one line for each dependency of the generated
/// files. With no dependency, I write no file.
fn write_dependencies(ctx : OutlineCtx) -> Unit raise @codegen.CodegenError {
  let dependencies = ctx.delegator.dependencies()
  if dependencies.is_empty() {
    return
  }
  let path = must(
    @codegen.OutputPath::parse("dependencies.txt"),
    "the output path `dependencies.txt`",
  )
  ctx.delegator.use_file_writer(path, @codegen.Namespace::root(), writer => {
    for dependency in dependencies {
      writer.write("$L@$L ($L)", args=[
        Text(dependency.package.to_string()),
        Text(dependency.version),
        Text(kind_text(dependency.kind)),
      ])
    }
  })
}

///|
fn outline_director() -> @codegen.DirectedCodegen[OutlineCtx] {
  @codegen.DirectedCodegen::new(
    create_symbol_provider=outline_provider,
    create_context=info => {
      info,
      delegator: @codegen.WriterDelegator::new(
        info.provider,
        render=render_outline,
      ),
    },
    delegator=ctx => ctx.delegator,
    generate_service~,
    generate_structure=(ctx, shape) => generate_record(ctx, shape, "structure"),
    generate_error=(ctx, shape) => generate_record(ctx, shape, "error"),
    generate_union=(ctx, shape) => generate_record(ctx, shape, "union"),
    generate_enum=(ctx, shape) => generate_enum_like(ctx, shape, "enum"),
    generate_int_enum=(ctx, shape) => generate_enum_like(ctx, shape, "intEnum"),
    generate_operation~,
    generate_list~,
    generate_map~,
    customize_after_integrations=write_dependencies,
  )
}

///|
/// The integration `fixtureHeader`: it appends `// {header}` to the section
/// `header` of each file.
fn header_integration(header : String) -> @codegen.Integration[OutlineCtx] {
  @codegen.Integration::new("fixtureHeader", interceptors=_ => {
    [
      @codegen.Interceptor::appender("header", (writer, _) => {
        writer.write("// $L", args=[Text(header)])
      }),
    ]
  })
}

///|
/// Generate the outline files of a service. The settings are `service`
/// (required) and `header` (optional text for the first line of each file).
pub fn run(
  plugin : @codegen.PluginContext,
) -> Map[String, String] raise @codegen.CodegenError {
  plugin.check_settings(["header"])
  let integrations = match plugin.setting_string("header") {
    Some(header) => [header_integration(header)]
    None => []
  }
  @codegen.run_codegen(plugin, outline_director(), integrations~)
}

///|
/// The plugin for the build runner. Register it as `codegenFixture`.
pub fn plugin(
  model : @smithy.Model,
  settings : Json,
) -> Map[String, String] raise @build.BuildError {
  @codegen.build_plugin(run)(model, settings)
}

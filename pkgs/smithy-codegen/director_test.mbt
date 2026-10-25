///|
priv struct DirectorCtx {
  log : Array[String]
  delegator : @codegen.WriterDelegator
  info : @codegen.CreateContext
}

///|
fn director_load(source : String) -> @smithy.Model {
  @smithy.Loader::new()
  .add_idl("a.smithy", "$version: \"2\"\nnamespace example\n" + source)
  .assemble().model.unwrap()
}

///|
fn director_context(source : String) -> @codegen.PluginContext raise {
  @codegen.PluginContext::from_build(
    director_load(source),
    @json.parse("{\"service\":\"example#Svc\"}"),
  )
}

///|
fn director_provider(
  _model : @smithy.Model,
  _plugin : @codegen.PluginContext,
) -> @codegen.SymbolProvider {
  @codegen.SymbolProvider::new(shape => {
    let name = shape.id.name()
    @codegen.Symbol::new(
      @codegen.SymbolName::parse(name).unwrap(),
      ns=@codegen.Namespace::parse("example", separator=".").unwrap(),
      definition=@codegen.OutputPath::parse("gen/\{name}.txt"),
    )
  })
}

///|
fn director_recorder(
  log : Array[String],
  write~ : Bool = false,
) -> @codegen.DirectedCodegen[DirectorCtx] {
  let note = (kind : String) => {
    (ctx : DirectorCtx, shape : @smithy.Shape) => {
      let entry = "\{kind}:\{shape.id.name()}"
      ctx.log.push(entry)
      if write {
        let path = ctx.info.provider.to_symbol(shape).definition.unwrap()
        ctx.delegator.use_file_writer(
          path,
          ctx.info.provider.to_symbol(shape).ns,
          w => w.write(entry),
        )
      }
    }
  }
  @codegen.DirectedCodegen::new(
    create_symbol_provider=director_provider,
    create_context=info => {
      log,
      delegator: @codegen.WriterDelegator::new(info.provider),
      info,
    },
    delegator=ctx => ctx.delegator,
    generate_service=note("service"),
    generate_structure=note("structure"),
    generate_error=note("error"),
    generate_union=note("union"),
    generate_enum=note("enum"),
    generate_int_enum=note("intEnum"),
    generate_operation=note("operation"),
    generate_resource=note("resource"),
    generate_list=note("list"),
    generate_map=note("map"),
  )
}

///|
let director_basic : String =
  #|service Svc { version: "1", operations: [Op] }
  #|operation Op { input: In, output: Out, errors: [Oops] }
  #|structure In { name: String }
  #|structure Out { count: Integer }
  #|@error("client")
  #|structure Oops { message: String }

///|
test "shapes are generated in topological order, services last" {
  let log = []
  let _ = @codegen.run_codegen(
    director_context(director_basic),
    director_recorder(log),
  )
  assert_eq(log, [
    "structure:Out", "structure:In", "error:Oops", "operation:Op", "service:Svc",
  ])
}

///|
test "a service comes after every shape it refers to, also with a cycle" {
  let source =
    #|service Svc { version: "1", operations: [Op] }
    #|operation Op { input: Node, output: Other }
    #|structure Node { next: Node, other: Other }
    #|structure Other { back: Node }
  let log = []
  let _ = @codegen.run_codegen(director_context(source), director_recorder(log))
  assert_eq(log.length(), 4)
  assert_eq(log[3], "service:Svc")
  assert_eq(log[2], "operation:Op")
}

///|
test "errors go to generate_error" {
  let log = []
  let _ = @codegen.run_codegen(
    director_context(director_basic),
    director_recorder(log),
  )
  assert_true(log.contains("error:Oops"))
  assert_false(log.contains("structure:Oops"))
}

///|
test "prelude, member and simple shapes are skipped" {
  let source =
    #|service Svc { version: "1", operations: [Op], resources: [Thing] }
    #|operation Op { input: In }
    #|structure In { name: Label, tags: Tags, scores: Scores, kind: Kind, level: Level, choice: Choice }
    #|string Label
    #|list Tags { member: String }
    #|map Scores { key: String, value: Integer }
    #|enum Kind { A, B }
    #|intEnum Level {
    #|    LOW = 1
    #|}
    #|union Choice { text: String, number: Integer }
    #|resource Thing { identifiers: { id: String } }
  let log = []
  let _ = @codegen.run_codegen(director_context(source), director_recorder(log))
  let sorted = log.copy()
  sorted.sort_by((a, b) => a.lexical_compare(b))
  assert_eq(sorted, [
    "enum:Kind", "intEnum:Level", "list:Tags", "map:Scores", "operation:Op", "resource:Thing",
    "service:Svc", "structure:In", "union:Choice",
  ])
}

///|
test "integration hooks run in order" {
  let log = []
  let integration = (name : String, extra : Array[String]) => {
    @codegen.Integration::new(
      name,
      run_after=extra,
      preprocess_model=(model, _) => {
        log.push("preprocess \{name}")
        model
      },
      decorate_symbol_provider=(provider, _) => {
        log.push("decorate \{name}")
        provider
      },
      interceptors=_ => {
        log.push("interceptors \{name}")
        []
      },
      customize=_ => log.push("customize \{name}"),
    )
  }
  let director = @codegen.DirectedCodegen::new(
    create_symbol_provider=(model, plugin) => {
      log.push("provider")
      director_provider(model, plugin)
    },
    create_context=info => {
      log.push("context " + info.integrations.join(","))
      { log, delegator: @codegen.WriterDelegator::new(info.provider), info, }
    },
    delegator=ctx => ctx.delegator,
    generate_service=(ctx, _) => ctx.log.push("service"),
    generate_structure=(ctx, _) => ctx.log.push("structure"),
    generate_error=(ctx, _) => ctx.log.push("error"),
    generate_union=(ctx, _) => ctx.log.push("union"),
    generate_enum=(ctx, _) => ctx.log.push("enum"),
    generate_int_enum=(ctx, _) => ctx.log.push("intEnum"),
    customize_before_integrations=_ => log.push("before"),
    customize_after_integrations=_ => log.push("after"),
  )
  let _ = @codegen.run_codegen(
    director_context("service Svc { version: \"1\" }"),
    director,
    integrations=[integration("b", []), integration("a", [])],
  )
  assert_eq(log, [
    "preprocess a", "preprocess b", "provider", "decorate a", "decorate b", "context a,b",
    "interceptors a", "interceptors b", "service", "before", "customize a", "customize b",
    "after",
  ])
}

///|
test "interceptors from integrations reach the writers" {
  let log = []
  let marker = @codegen.Integration::new("a", interceptors=_ => {
    [@codegen.Interceptor::appender("tail", (w, _) => w.write("!"))]
  })
  let director = @codegen.DirectedCodegen::new(
    create_symbol_provider=director_provider,
    create_context=info => {
      log,
      delegator: @codegen.WriterDelegator::new(info.provider),
      info,
    },
    delegator=ctx => ctx.delegator,
    generate_service=(ctx, shape) => {
      let symbol = ctx.info.provider.to_symbol(shape)
      ctx.delegator.use_file_writer(symbol.definition.unwrap(), symbol.ns, w => {
        w.push_section(@codegen.Section::new("tail"))
        w.write("body")
        w.pop_section()
      })
    },
    generate_structure=(_, _) => (),
    generate_error=(_, _) => (),
    generate_union=(_, _) => (),
    generate_enum=(_, _) => (),
    generate_int_enum=(_, _) => (),
  )
  let files = @codegen.run_codegen(
    director_context("service Svc { version: \"1\" }"),
    director,
    integrations=[marker],
  )
  assert_eq(files["gen/Svc.txt"], "body\n!\n")
}

///|
test "a preprocess that removes the service raises MissingService" {
  let remove = @codegen.Integration::new("remove", preprocess_model=(
    model,
    plugin,
  ) => {
    let shapes = Map([])
    for id, shape in model.shapes {
      if id != plugin.service.id {
        shapes[id] = shape
      }
    }
    { shapes, metadata: model.metadata, }
  })
  let plugin = director_context(director_basic)
  let message = try
    @codegen.run_codegen(plugin, director_recorder([]), integrations=[remove])
  catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(
    message, "I could not find service shape `example#Svc` in the model.",
  )
}

///|
test "a preprocess that turns the service into a structure raises NotAService" {
  let change = @codegen.Integration::new("change", preprocess_model=(
    model,
    plugin,
  ) => {
    let shapes = Map([])
    for id, shape in model.shapes {
      shapes[id] = if id == plugin.service.id {
        { ..shape, body: Structure([]), }
      } else {
        shape
      }
    }
    { shapes, metadata: model.metadata, }
  })
  let plugin = director_context(director_basic)
  let message = try
    @codegen.run_codegen(plugin, director_recorder([]), integrations=[change])
  catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(message, "I expected `example#Svc` to be a service shape.")
}

///|
test "the result is the flushed delegator" {
  let log = []
  let files = @codegen.run_codegen(
    director_context(director_basic),
    director_recorder(log, write=true),
  )
  let names = files.keys().to_array()
  names.sort_by((a, b) => a.lexical_compare(b))
  assert_eq(names, [
    "gen/In.txt", "gen/Oops.txt", "gen/Op.txt", "gen/Out.txt", "gen/Svc.txt",
  ])
  assert_eq(files["gen/Oops.txt"], "error:Oops\n")
}

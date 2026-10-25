///|
/// What the director gives to `create_context`: the original plugin context,
/// the model and the service after the integrations changed the model, the
/// symbol provider and the names of the integrations in run order.
pub struct CreateContext {
  model : @smithy.Model
  plugin : PluginContext
  service : @smithy.Shape
  provider : SymbolProvider
  integrations : Array[String]
}

///|
/// The steps of a generator. `C` is the context type that `create_context`
/// makes. The director calls one `generate_*` step for each kind of shape.
pub struct DirectedCodegen[C] {
  priv create_symbol_provider : (@smithy.Model, PluginContext) -> SymbolProvider
  priv create_context : (CreateContext) -> C
  priv delegator : (C) -> WriterDelegator
  priv generate_service : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_structure : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_error : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_union : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_enum : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_int_enum : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_operation : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_resource : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_list : (C, @smithy.Shape) -> Unit raise CodegenError
  priv generate_map : (C, @smithy.Shape) -> Unit raise CodegenError
  priv customize_before_integrations : (C) -> Unit raise CodegenError
  priv customize_after_integrations : (C) -> Unit raise CodegenError
}

///|
/// Make a generator from its steps. The steps for operations, resources, lists
/// and maps, and the two customize steps, do nothing by default.
pub fn[C] DirectedCodegen::new(
  create_symbol_provider~ : (@smithy.Model, PluginContext) -> SymbolProvider,
  create_context~ : (CreateContext) -> C,
  delegator~ : (C) -> WriterDelegator,
  generate_service~ : (C, @smithy.Shape) -> Unit raise CodegenError,
  generate_structure~ : (C, @smithy.Shape) -> Unit raise CodegenError,
  generate_error~ : (C, @smithy.Shape) -> Unit raise CodegenError,
  generate_union~ : (C, @smithy.Shape) -> Unit raise CodegenError,
  generate_enum~ : (C, @smithy.Shape) -> Unit raise CodegenError,
  generate_int_enum~ : (C, @smithy.Shape) -> Unit raise CodegenError,
  generate_operation~ : (C, @smithy.Shape) -> Unit raise CodegenError = (_, _) => {
    ()
  },
  generate_resource~ : (C, @smithy.Shape) -> Unit raise CodegenError = (_, _) => {
    ()
  },
  generate_list~ : (C, @smithy.Shape) -> Unit raise CodegenError = (_, _) => (),
  generate_map~ : (C, @smithy.Shape) -> Unit raise CodegenError = (_, _) => (),
  customize_before_integrations~ : (C) -> Unit raise CodegenError = _ => (),
  customize_after_integrations~ : (C) -> Unit raise CodegenError = _ => (),
) -> DirectedCodegen[C] {
  {
    create_symbol_provider,
    create_context,
    delegator,
    generate_service,
    generate_structure,
    generate_error,
    generate_union,
    generate_enum,
    generate_int_enum,
    generate_operation,
    generate_resource,
    generate_list,
    generate_map,
    customize_before_integrations,
    customize_after_integrations,
  }
}

///|
/// Run a generator on the service of the plugin context.
///
/// 1. Sort the integrations.
/// 2. Let each integration change the model, in order. Find the service in the
///    new model. It raises `MissingService` when the service is gone, and
///    `NotAService` when it is not a service any more.
/// 3. Make the symbol provider, let each integration decorate it, and cache it.
/// 4. Make the context.
/// 5. Add the interceptors of the integrations to the delegator.
/// 6. Generate each shape of the service closure in topological order. I skip
///    prelude shapes, member shapes and simple shapes.
/// 7. Run `customize_before_integrations`, the `customize` step of each
///    integration, and `customize_after_integrations`.
/// 8. Return the files of the delegator.
pub fn[C] run_codegen(
  plugin : PluginContext,
  director : DirectedCodegen[C],
  integrations~ : Array[Integration[C]] = [],
) -> Map[String, String] raise CodegenError {
  let sorted = sort_integrations(integrations)
  let mut model = plugin.model
  for integration in sorted {
    model = (integration.preprocess_model)(model, plugin)
  }
  let service = match model.shapes.get(plugin.service.id) {
    None => raise MissingService(plugin.service.id)
    Some({ body: Service(..), .. } as shape) => shape
    Some(_) => raise NotAService(plugin.service.id)
  }
  let mut provider = (director.create_symbol_provider)(model, plugin)
  for integration in sorted {
    provider = (integration.decorate_symbol_provider)(provider, plugin)
  }
  provider = provider.cached()
  let ctx = (director.create_context)({
    model,
    plugin,
    service,
    provider,
    integrations: sorted.map(integration => integration.name),
  })
  let delegator = (director.delegator)(ctx)
  let interceptors : Array[Interceptor] = []
  for integration in sorted {
    interceptors.append((integration.interceptors)(ctx))
  }
  delegator.add_interceptors(interceptors)
  let error_trait = @smithy.ShapeId::parse("smithy.api#error").unwrap()
  for id in topological_order(model, service_closure(model, service.id)) {
    if id.namespace() == "smithy.api" {
      continue
    }
    guard model.shapes.get(id) is Some(shape) else { continue }
    match shape.body {
      Member(..) | Simple(_) => ()
      Structure(_) =>
        if shape.traits.contains(error_trait) {
          (director.generate_error)(ctx, shape)
        } else {
          (director.generate_structure)(ctx, shape)
        }
      Union(_) => (director.generate_union)(ctx, shape)
      Enum(_) => (director.generate_enum)(ctx, shape)
      IntEnum(_) => (director.generate_int_enum)(ctx, shape)
      Operation(..) => (director.generate_operation)(ctx, shape)
      Resource(..) => (director.generate_resource)(ctx, shape)
      List(_) => (director.generate_list)(ctx, shape)
      Map(..) => (director.generate_map)(ctx, shape)
      Service(..) => (director.generate_service)(ctx, shape)
    }
  }
  (director.customize_before_integrations)(ctx)
  for integration in sorted {
    (integration.customize)(ctx)
  }
  (director.customize_after_integrations)(ctx)
  delegator.flush()
}

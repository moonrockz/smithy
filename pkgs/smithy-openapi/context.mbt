///|
priv enum Protocol {
  RestJson1
  RpcV2Json
} derive(Eq)

///|
fn Protocol::id(self : Protocol) -> ProtocolId {
  ProtocolId::parse(
    match self {
      RestJson1 => "aws.protocols#restJson1"
      RpcV2Json => "smithy.protocols#rpcv2Json"
    },
  ).unwrap()
}

///|
fn protocol_implementation(id : ProtocolId) -> Protocol? {
  for protocol in [RestJson1, RpcV2Json] {
    if protocol.id() == id {
      return Some(protocol)
    }
  }
  None
}

///|
priv struct Context {
  model : @smithy.Model
  service : @smithy.Shape
  config : Config
  protocol : Protocol
  schema_config : @jsonschema.Config
  index : @jsonschema.SchemaIndex
  schemas : Map[String, Json]
  warnings : Array[ConversionWarning]
  auth_used : Set[AuthScheme]
  examples_cache : Map[@smithy.ShapeId, Array[ModeledExample]]
  error_groups : Map[@smithy.ShapeId, Array[@smithy.ShapeId]]
}

///|
fn Context::new(
  model : @smithy.Model,
  config : Config,
) -> Context raise OpenApiError {
  guard model.shapes.get(config.service.shape_id()) is Some(service) else {
    raise MissingService(config.service)
  }
  guard service.body is @smithy.Service(..) else {
    raise InvalidService(config.service)
  }
  if config.version == V3_0_2 && config.schema.add_reference_descriptions {
    raise InvalidConfiguration(
      "addReferenceDescriptions requires OpenAPI 3.1.0",
    )
  }
  let protocols : Array[ProtocolId] = []
  for id, _ in service.traits {
    if model.shapes.get(id) is Some(definition) &&
      definition.trait_value("smithy.api#protocolDefinition") is Some(_) {
      protocols.push(ProtocolId(id))
    }
  }
  let selected = match config.protocol {
    Some(id) => {
      if !service.traits.contains(id.shape_id()) {
        raise ProtocolResolution(
          config.service,
          "Configured protocol is not applied to the service",
        )
      }
      id
    }
    None => {
      guard protocols.length() == 1 else {
        raise ProtocolResolution(
          config.service,
          if protocols.is_empty() {
            "Service does not define any protocols"
          } else {
            "Service defines multiple protocols; configure protocol explicitly"
          },
        )
      }
      protocols[0]
    }
  }
  guard protocol_implementation(selected) is Some(protocol) else {
    raise UnsupportedProtocol(selected)
  }
  let (model, error_groups) = if config.combine_error_responses {
    deconflict_errors(model, service)
  } else {
    (model, Map([]))
  }
  let schema_config = {
    ..config.schema,
    definition_pointer: "#/components/schemas",
    use_json_name: if protocol == RestJson1 {
      true
    } else {
      config.schema.use_json_name
    },
    default_timestamp_format: if protocol == RestJson1 {
      "epoch-seconds"
    } else {
      config.schema.default_timestamp_format
    },
  }
  let index = @jsonschema.SchemaIndex::new(
    model,
    service=config.service.to_string(),
    config=schema_config,
  ) catch {
    error => raise SchemaConversion(error.to_string())
  }
  let context = {
    model,
    service,
    config,
    protocol,
    schema_config,
    index,
    schemas: Map([]),
    warnings: [],
    auth_used: Set([]),
    examples_cache: Map([]),
    error_groups,
  }
  context.check_unsupported()
  context
}

///|
fn Context::check_unsupported(self : Context) -> Unit raise OpenApiError {
  let containers : Set[@smithy.ShapeId] = Set([])
  let selected_operations : Set[@smithy.ShapeId] = Set([])
  for operation in self.operations() {
    selected_operations.add(operation.id)
  }
  let service_errors = match self.service.body {
    @smithy.Service(errors~, ..) => errors
    _ => []
  }
  for _, shape in self.model.shapes {
    if shape.body is @smithy.Operation(input~, output~, errors~) {
      containers.add(input)
      containers.add(output)
      for id in errors {
        containers.add(id)
      }
      if selected_operations.contains(shape.id) {
        for id in service_errors {
          containers.add(id)
        }
      }
    }
  }
  for id, shape in self.model.shapes {
    for trait_name in ["smithy.api#endpoint", "smithy.api#hostLabel"] {
      if shape.trait_value(trait_name) is Some(_) {
        let trait_id = @smithy.ShapeId::parse(trait_name).unwrap()
        if !self.config.ignore_unsupported_traits {
          raise UnsupportedTrait(id, trait_id)
        }
        self.warnings.push({
          code: OmittedUnsupportedTrait,
          shape: id,
          message: "OpenAPI omits unsupported trait `" + trait_name + "`",
        })
      }
    }
    if shape.trait_value("smithy.api#httpPrefixHeaders") is Some(_) &&
      containers.contains(id.root()) {
      if self.config.prefix_headers == Fail {
        raise PrefixHeaders(id)
      }
      self.warnings.push({
        code: OmittedPrefixHeaders,
        shape: id,
        message: "OpenAPI omits the unsupported httpPrefixHeaders binding",
      })
    }
  }
  for id, _ in self.service.traits {
    if self.model.shapes.get(id) is Some(definition) &&
      definition.trait_value("smithy.api#authDefinition") is Some(_) &&
      ![Basic, Bearer, Digest, ApiKey].any(scheme => scheme.id() == id) {
      self.warnings.push({
        code: OmittedAuthScheme,
        shape: self.service.id,
        message: "OpenAPI omits unsupported authentication scheme `" +
        id.to_string() +
        "`",
      })
    }
  }
}

///|
fn Context::name(self : Context, id : @smithy.ShapeId) -> String {
  match self.service.body {
    @smithy.Service(rename~, ..) => rename.get(id).unwrap_or(id.name())
    _ => id.name()
  }
}

///|
fn Context::operations(self : Context) -> Array[@smithy.Shape] {
  service_operations(self.model, self.service)
}

///|
fn service_operations(
  model : @smithy.Model,
  service : @smithy.Shape,
) -> Array[@smithy.Shape] {
  let pending : Array[@smithy.ShapeId] = [service.id]
  let visited : Set[@smithy.ShapeId] = Set([])
  let operations : Array[@smithy.Shape] = []
  while pending.pop() is Some(id) {
    if visited.contains(id) {
      continue
    }
    visited.add(id)
    guard model.shapes.get(id) is Some(shape) else { continue }
    match shape.body {
      @smithy.Service(operations~, resources~, ..) => {
        pending.append(operations)
        pending.append(resources)
      }
      @smithy.Resource(
        create~,
        put~,
        read~,
        update~,
        delete~,
        list~,
        operations~,
        collectionOperations~,
        resources~,
        ..
      ) => {
        for operation in [create, put, read, update, delete, list] {
          if operation is Some(operation_id) {
            pending.push(operation_id)
          }
        }
        pending.append(operations)
        pending.append(collectionOperations)
        pending.append(resources)
      }
      @smithy.Operation(..) => operations.push(shape)
      _ => ()
    }
  }
  operations.sort_by((a, b) => {
    a.id.to_string().lexical_compare(b.id.to_string())
  })
  operations
}

///|
fn Context::members(
  self : Context,
  id : @smithy.ShapeId,
) -> Array[@smithy.Shape] {
  guard self.model.shapes.get(id) is Some(shape) &&
    shape.body is @smithy.Structure(ids) else {
    return []
  }
  let members : Array[@smithy.Shape] = []
  for member_id in ids {
    if self.model.shapes.get(member_id) is Some(value) {
      members.push(value)
    }
  }
  members
}

///|
fn Context::target(self : Context, shape : @smithy.Shape) -> @smithy.Shape {
  match shape.body {
    @smithy.Member(target~) => self.model.shapes.get(target).unwrap_or(shape)
    _ => shape
  }
}

///|
fn trait_string(shape : @smithy.Shape, name : String) -> String? {
  match shape.trait_value(name) {
    Some(@smithy.String(value)) => Some(value)
    _ => None
  }
}

///|
fn trait_integer(shape : @smithy.Shape, name : String) -> Int32? {
  match shape.trait_value(name) {
    Some(@smithy.Number(value)) => {
      let node = value.to_json()
      match node {
        Number(number, ..) => Some(number.to_int())
        _ => None
      }
    }
    _ => None
  }
}

///|
fn fields(value : Json) -> Map[String, Json] {
  match value {
    Object(values) => values
    _ => Map([])
  }
}

///|
fn copy_fields(value : Json) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for key, item in fields(value) {
    out[key] = item
  }
  out
}

///|
priv struct BodyContent {
  content : Json
  required : Bool
}

///|
fn Context::body_content(
  self : Context,
  container : @smithy.ShapeId,
  subject : @smithy.Shape,
  response : Bool,
  operation : @smithy.Shape,
) -> BodyContent? raise OpenApiError {
  let bindings = self.bindings(container, response)
  let name = self.name(subject.id)
  let phase = if !response {
    RequestExample
  } else {
    self.response_phase(subject)
  }
  if self.protocol == RestJson1 {
    for binding in bindings {
      if binding.location == Payload {
        let suffix = if !response {
          "InputPayload"
        } else if subject.body is @smithy.Operation(..) {
          "OutputPayload"
        } else {
          "ErrorPayload"
        }
        return Some({
          content: content_examples(
            self.payload_content(binding, name + suffix),
            self.binding_examples(operation, binding, phase),
          ),
          required: binding.shape.trait_value("smithy.api#required") is Some(_),
        })
      }
    }
  }
  let documents = bindings
    .filter(binding => {
      self.protocol == RpcV2Json || binding.location == Document
    })
    .map(binding => binding.shape)
  if documents.is_empty() && self.protocol == RestJson1 {
    return None
  }
  let schema = if self.error_groups.get(subject.id) is Some(ids) &&
    self.protocol == RestJson1 {
    Json::object({
      "oneOf": Json::array(ids.map(id => self.schema_ref(self.index.name(id)))),
    })
  } else if documents.is_empty() {
    Json::object({ "type": Json::string("object") })
  } else {
    self.document_schema(container, documents)
  }
  let suffix = if !response {
    "RequestContent"
  } else if self.protocol == RpcV2Json &&
    subject.trait_value("smithy.api#error") is Some(_) {
    "ErrorContent"
  } else {
    "ResponseContent"
  }
  let reference = self.add_schema(name + suffix, schema)
  let content : Map[String, Json] = Map([])
  content[if self.protocol == RpcV2Json {
    "application/json"
  } else {
    self.config.json_content_type
  }] = Json::object({ "schema": reference })
  Some({
    content: if self.protocol == RpcV2Json {
      Json::object(content)
    } else {
      content_examples(
        Json::object(content),
        self.document_examples(operation, container, documents, phase),
      )
    },
    required: self.protocol == RestJson1 &&
    documents.any(shape => shape.trait_value("smithy.api#required") is Some(_)),
  })
}

///|
fn http_code(operation : @smithy.Shape) -> Int32 {
  if operation.trait_value("smithy.api#http")
    is Some(@smithy.Object(properties)) &&
    properties.get("code") is Some(@smithy.Number(value)) &&
    value.to_json() is Number(number, ..) {
    number.to_int()
  } else {
    200
  }
}

///|
fn error_code(error : @smithy.Shape) -> Int32 {
  trait_integer(error, "smithy.api#httpError").unwrap_or(
    if trait_string(error, "smithy.api#error") == Some("client") {
      400
    } else {
      500
    },
  )
}

///|
fn Context::response(
  self : Context,
  container : @smithy.ShapeId,
  subject : @smithy.Shape,
  status : Int32,
  operation : @smithy.Shape,
) -> Json raise OpenApiError {
  let response : Map[String, Json] = {
    "description": Json::string(
      if self.protocol == RpcV2Json {
        "Response Object"
      } else {
        self.component_name(self.name(subject.id)) +
        " " +
        status.to_string() +
        " response"
      },
    ),
  }
  let headers : Map[String, Json] = Map([])
  if self.protocol == RestJson1 {
    for binding in self.bindings(container, true) {
      if binding.location is Header(name) {
        let header = copy_fields(self.parameter(binding, name, "header", true))
        let examples = self.binding_examples(
          operation,
          binding,
          self.response_phase(subject),
        )
        if !examples.is_empty() {
          header["examples"] = Json::object(examples)
        }
        headers[name] = Json::object(header)
      }
    }
  }
  if !headers.is_empty() {
    response["headers"] = Json::object(headers)
  }
  if self.body_content(container, subject, true, operation) is Some(body) {
    response["content"] = body.content
  }
  Json::object(response)
}

///|
fn Context::operation(
  self : Context,
  operation : @smithy.Shape,
  template : UriTemplate,
) -> Json raise OpenApiError {
  guard operation.body is @smithy.Operation(input~, output~, errors~) else {
    raise InvalidConfiguration("Expected an operation")
  }
  let out : Map[String, Json] = {
    "operationId": Json::string(self.name(operation.id)),
  }
  self.operation_security(operation, out)
  if operation.trait_value("smithy.api#deprecated") is Some(_) {
    out["deprecated"] = Json::boolean(true)
  }
  if trait_string(operation, "smithy.api#documentation") is Some(description) {
    out["description"] = Json::string(description)
  }
  if self.external_docs(operation) is Some(docs) {
    out["externalDocs"] = docs
  }
  let parameters : Array[Json] = []
  if self.protocol == RestJson1 {
    let bindings = self.bindings(input, false)
    for binding in bindings {
      if binding.location == Label {
        let member_name = binding.shape.id.member_name().unwrap()
        guard template.label(member_name) is Some(label) else {
          raise InvalidConfiguration(
            "Missing URI label for `" + binding.shape.id.to_string() + "`",
          )
        }
        let name = label.name +
          (if label.greedy && !self.config.remove_greedy_parameter_suffix {
            "+"
          } else {
            ""
          })
        let parameter = copy_fields(
          self.parameter(binding, name, "path", false),
        )
        let examples = self.binding_examples(operation, binding, RequestExample)
        if !examples.is_empty() {
          parameter["examples"] = Json::object(examples)
        }
        parameters.push(Json::object(parameter))
      }
    }
    for binding in bindings {
      match binding.location {
        Query(name) =>
          parameters.push(
            self.parameter_with_examples(operation, binding, name, "query"),
          )
        QueryParams =>
          parameters.push(
            self.parameter_with_examples(
              operation,
              binding,
              binding.shape.id.member_name().unwrap(),
              "query",
            ),
          )
        _ => ()
      }
    }
    let header_bindings = bindings.filter(binding => {
      binding.location is Header(_)
    })
    header_bindings.sort_by((a, b) => {
      match (a.location, b.location) {
        (Header(a), Header(b)) => a.lexical_compare(b)
        _ => 0
      }
    })
    for binding in header_bindings {
      if binding.location is Header(name) {
        parameters.push(
          self.parameter_with_examples(operation, binding, name, "header"),
        )
      }
    }
  }
  if !parameters.is_empty() {
    out["parameters"] = Json::array(parameters)
  }
  let unit = "smithy.api#Unit"
  let rpc_unit_input = self.protocol == RpcV2Json && input.to_string() == unit
  let rpc_unit_output = self.protocol == RpcV2Json && output.to_string() == unit
  if !rpc_unit_input &&
    self.body_content(input, operation, false, operation) is Some(body) {
    let request : Map[String, Json] = { "content": body.content }
    if body.required {
      request["required"] = Json::boolean(true)
    }
    if self.protocol == RpcV2Json {
      request["description"] = Json::string("Request Object")
    }
    out["requestBody"] = Json::object(request)
  }
  if !rpc_unit_output {
    let responses : Map[String, Json] = Map([])
    let status = if self.protocol == RpcV2Json {
      200
    } else {
      http_code(operation)
    }
    responses[status.to_string()] = self.response(
      output, operation, status, operation,
    )
    let all_errors : Array[@smithy.ShapeId] = []
    let seen : Set[@smithy.ShapeId] = Set([])
    let service_errors = if self.config.combine_error_responses {
      []
    } else {
      match self.service.body {
        @smithy.Service(errors~, ..) => errors
        _ => []
      }
    }
    for error_id in errors + service_errors {
      if !seen.contains(error_id) {
        seen.add(error_id)
        all_errors.push(error_id)
      }
    }
    for error_id in all_errors {
      if self.model.shapes.get(error_id) is Some(error) {
        let status = error_code(error)
        responses[status.to_string()] = self.response(
          error_id, error, status, operation,
        )
      }
    }
    out["responses"] = Json::object(responses)
  }
  let tags = self.tags(operation)
  if !tags.is_empty() {
    out["tags"] = Json::array(tags.map(Json::string))
  }
  Json::object(out)
}

///|
fn Context::tags(self : Context, shape : @smithy.Shape) -> Array[String] {
  guard self.config.tags &&
    shape.trait_value("smithy.api#tags") is Some(@smithy.Array(tags)) else {
    return []
  }
  let result : Array[String] = []
  for tag in tags {
    if tag is @smithy.String(name) &&
      self.config.supported_tags
      .map(allowed => allowed.contains(name))
      .unwrap_or(true) {
      result.push(name)
    }
  }
  result
}

///|
fn Context::paths(self : Context) -> Json raise OpenApiError {
  let paths : Map[String, Json] = Map([])
  for operation in self.operations() {
    let (method_text, uri) = if self.protocol == RpcV2Json {
      (
        "POST",
        "/service/" +
        self.service.id.name() +
        "/operation/" +
        self.name(operation.id),
      )
    } else {
      guard operation.trait_value("smithy.api#http")
        is Some(@smithy.Object(http)) &&
        http.get("method") is Some(@smithy.String(verb)) &&
        http.get("uri") is Some(@smithy.String(uri)) else {
        continue
      }
      (verb, uri)
    }
    guard UriTemplate::parse(uri) is Some(template) else {
      raise InvalidConfiguration("Invalid operation URI `" + uri + "`")
    }
    if self.config.forbid_greedy_labels && template.has_greedy_label() {
      raise GreedyLabel(operation.id)
    }
    let path = template.path()
    let item = copy_fields(paths.get(path).unwrap_or(Json::object(Map([]))))
    if HttpMethod::parse(method_text) is Some(verb) {
      item[verb.key()] = self.operation(operation, template)
    } else {
      self.warnings.push({
        code: OmittedHttpMethod,
        shape: operation.id,
        message: "OpenAPI omits unsupported HTTP method `" + method_text + "`",
      })
    }
    paths[path] = Json::object(item)
  }
  Json::object(paths)
}

///|
fn referenced_schemas(value : Json) -> Array[String] {
  let pending = [value]
  let names : Array[String] = []
  let prefix = "#/components/schemas/"
  while pending.pop() is Some(node) {
    match node {
      Object(properties) => {
        if properties.get("$ref") is Some(String(reference)) &&
          reference.has_prefix(prefix) {
          names.push(reference[prefix.length():].to_owned())
        }
        for _, value in properties {
          pending.push(value)
        }
      }
      Array(values) => pending.append(values)
      _ => ()
    }
  }
  names
}

///|
fn Context::used_schemas(
  self : Context,
  paths : Json,
) -> Map[String, Json] raise OpenApiError {
  if self.config.keep_unused_components {
    return self.schemas
  }
  let selected : Map[String, Json] = Map([])
  let pending = referenced_schemas(paths)
  while pending.pop() is Some(name) {
    if selected.contains(name) {
      continue
    }
    guard self.schemas.get(name) is Some(schema) else {
      raise SchemaConversion("Dangling OpenAPI schema reference `" + name + "`")
    }
    selected[name] = schema
    pending.append(referenced_schemas(schema))
  }
  selected
}

///|
/// Convert one assembled service and retain warnings about omitted constructs.
pub fn convert_result(
  model : @smithy.Model,
  config : Config,
) -> Conversion raise OpenApiError {
  let context = Context::new(model, config)
  context.prepare_schemas()
  let service = context.service
  let version = match service.body {
    @smithy.Service(version~, ..) => version
    _ => ""
  }
  let info : Map[String, Json] = {
    "title": Json::string(
      trait_string(service, "smithy.api#title").unwrap_or(service.id.name()),
    ),
    "version": Json::string(version),
  }
  if trait_string(service, "smithy.api#documentation") is Some(description) {
    info["description"] = Json::string(description)
  }
  let paths = context.paths()
  let document : Map[String, Json] = {
    "openapi": Json::string(config.version.to_string()),
    "info": Json::object(info),
  }
  if !fields(paths).is_empty() {
    document["paths"] = paths
  }
  let schemas = context.used_schemas(paths)
  let security = context.effective_auth(service)
  if !security.is_empty() {
    document["security"] = context.security_requirements(security)
  }
  let security_schemes = context.security_schemes()
  let components : Map[String, Json] = Map([])
  if !schemas.is_empty() {
    components["schemas"] = Json::object(schemas)
  }
  if !security_schemes.is_empty() {
    components["securitySchemes"] = Json::object(security_schemes)
  }
  if !components.is_empty() {
    document["components"] = Json::object(components)
  }
  if context.external_docs(service) is Some(docs) {
    document["externalDocumentation"] = docs
  }
  let tags = context.tags(service)
  if !tags.is_empty() {
    document["tags"] = Json::array(
      tags.map(name => Json::object({ "name": Json::string(name) })),
    )
  }
  for key, value in fields(config.schema.schema_document_extensions) {
    document[key] = value
  }
  {
    document: apply_json_settings(Json::object(document), config),
    warnings: context.warnings,
  }
}

///|
pub fn convert(
  model : @smithy.Model,
  config : Config,
) -> Json raise OpenApiError {
  convert_result(model, config).document
}

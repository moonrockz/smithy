///|
priv struct ModeledErrorExample {
  shape : @smithy.ShapeId
  content : Map[String, @smithy.NodeValue]
}

///|
priv struct ModeledExample {
  ordinal : Int32
  title : String
  documentation : String
  input : Map[String, @smithy.NodeValue]
  output : Map[String, @smithy.NodeValue]
  error : ModeledErrorExample?
}

///|
priv enum ExamplePhase {
  RequestExample
  ResponseExample
  FailedExample(Array[@smithy.ShapeId])
}

///|
fn Context::modeled_examples(
  self : Context,
  operation : @smithy.Shape,
) -> Array[ModeledExample] raise OpenApiError {
  if self.examples_cache.get(operation.id) is Some(cached) {
    return cached
  }
  let out : Array[ModeledExample] = []
  guard operation.trait_value("smithy.api#examples")
    is Some(@smithy.Array(examples)) else {
    self.examples_cache[operation.id] = out
    return out
  }
  for i = 0; i < examples.length(); i = i + 1 {
    guard examples[i] is @smithy.Object(fields) &&
      fields.get("title") is Some(@smithy.String(title)) else {
      raise InvalidConfiguration(
        "Malformed example on `" + operation.id.to_string() + "`",
      )
    }
    let documentation = match fields.get("documentation") {
      Some(@smithy.String(value)) => value
      _ => ""
    }
    let input = match fields.get("input") {
      Some(@smithy.Object(value)) => value
      _ => Map([])
    }
    let output = match fields.get("output") {
      Some(@smithy.Object(value)) => value
      _ => Map([])
    }
    let error = match fields.get("error") {
      None => None
      Some(@smithy.Object(error)) => {
        guard error.get("shapeId") is Some(@smithy.String(name)) &&
          @smithy.ShapeId::parse(name) is Some(shape) else {
          raise InvalidConfiguration(
            "Example error requires an absolute shapeId",
          )
        }
        Some({
          shape,
          content: match error.get("content") {
            Some(@smithy.Object(value)) => value
            _ => Map([])
          },
        })
      }
      _ => raise InvalidConfiguration("Example error must be an object")
    }
    out.push({ ordinal: i + 1, title, documentation, input, output, error, })
  }
  self.examples_cache[operation.id] = out
  out
}

///|
fn Context::example_rows(
  self : Context,
  operation : @smithy.Shape,
  phase : ExamplePhase,
) -> Array[(ModeledExample, Map[String, @smithy.NodeValue])] raise OpenApiError {
  let out : Array[(ModeledExample, Map[String, @smithy.NodeValue])] = []
  for example in self.modeled_examples(operation) {
    match phase {
      RequestExample => out.push((example, example.input))
      ResponseExample if example.error is None =>
        out.push((example, example.output))
      FailedExample(ids) =>
        if example.error is Some(error) && ids.contains(error.shape) {
          out.push((example, error.content))
        }
      _ => ()
    }
  }
  out
}

///|
fn Context::example_value(
  self : Context,
  shape : @smithy.Shape,
  value : @smithy.NodeValue,
) -> @smithy.NodeValue {
  let target = self.target(shape)
  match (target.body, value) {
    (@smithy.Simple(Document), _) => value
    (@smithy.List(item), @smithy.Array(values)) => {
      guard self.model.shapes.get(item) is Some(element) else { return value }
      @smithy.Array(values.map(value => self.example_value(element, value)))
    }
    (@smithy.Map(value=element_id, ..), @smithy.Object(values)) => {
      guard self.model.shapes.get(element_id) is Some(element) else {
        return value
      }
      let out : Map[String, @smithy.NodeValue] = Map([])
      for key, value in values {
        out[key] = self.example_value(element, value)
      }
      @smithy.Object(out)
    }
    (@smithy.Structure(_) | @smithy.Union(_), @smithy.Object(values)) => {
      let out : Map[String, @smithy.NodeValue] = Map([])
      for key, value in values {
        if target.id.with_member(key) is Some(member_id) &&
          self.model.shapes.get(member_id) is Some(member_shape) {
          out[self.property_name(member_shape)] = self.example_value(
            member_shape, value,
          )
        } else {
          out[key] = value
        }
      }
      @smithy.Object(out)
    }
    _ => value
  }
}

///|
fn example_object(example : ModeledExample, value : @smithy.NodeValue) -> Json {
  Json::object({
    "summary": Json::string(example.title),
    "description": Json::string(example.documentation),
    "value": value.to_json(),
  })
}

///|
fn Context::binding_examples(
  self : Context,
  operation : @smithy.Shape,
  binding : Binding,
  phase : ExamplePhase,
) -> Map[String, Json] raise OpenApiError {
  let out : Map[String, Json] = Map([])
  let member_name = binding.shape.id.member_name().unwrap()
  for (example, values) in self.example_rows(operation, phase) {
    if values.get(member_name) is Some(value) {
      out[operation.id.name() + "_example" + example.ordinal.to_string()] = example_object(
        example,
        self.example_value(binding.shape, value),
      )
    }
  }
  out
}

///|
fn Context::document_examples(
  self : Context,
  operation : @smithy.Shape,
  container : @smithy.ShapeId,
  members : Array[@smithy.Shape],
  phase : ExamplePhase,
) -> Map[String, Json] raise OpenApiError {
  let out : Map[String, Json] = Map([])
  for (example, values) in self.example_rows(operation, phase) {
    let selected : Map[String, @smithy.NodeValue] = Map([])
    match phase {
      FailedExample(_) =>
        for key, value in values {
          selected[key] = value
        }
      _ =>
        for shape in members {
          let name = shape.id.member_name().unwrap()
          if values.get(name) is Some(value) {
            selected[name] = value
          }
        }
    }
    let value = match self.model.shapes.get(container) {
      Some(shape) => self.example_value(shape, @smithy.Object(selected))
      None => @smithy.Object(selected)
    }
    out[operation.id.name() + "_example" + example.ordinal.to_string()] = example_object(
      example, value,
    )
  }
  out
}

///|
fn content_examples(content : Json, examples : Map[String, Json]) -> Json {
  if examples.is_empty() {
    return content
  }
  let out : Map[String, Json] = Map([])
  for media_type, value in fields(content) {
    let item = copy_fields(value)
    item["examples"] = Json::object(examples)
    out[media_type] = Json::object(item)
  }
  Json::object(out)
}

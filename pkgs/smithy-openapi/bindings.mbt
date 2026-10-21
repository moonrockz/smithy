///|
priv enum BindingLocation {
  Label
  Query(String)
  QueryParams
  Header(String)
  Payload
  PrefixHeaders
  ResponseCode
  Document
} derive(Eq)

///|
priv struct Binding {
  shape : @smithy.Shape
  location : BindingLocation
}

///|
fn Context::bindings(
  self : Context,
  container : @smithy.ShapeId,
  response : Bool,
) -> Array[Binding] {
  self
  .members(container)
  .map(shape => {
    let location = if trait_string(shape, "smithy.api#httpHeader") is Some(name) {
      Header(name)
    } else if shape.trait_value("smithy.api#httpPayload") is Some(_) {
      Payload
    } else if shape.trait_value("smithy.api#httpPrefixHeaders") is Some(_) {
      PrefixHeaders
    } else if response &&
      shape.trait_value("smithy.api#httpResponseCode") is Some(_) {
      ResponseCode
    } else if !response && shape.trait_value("smithy.api#httpLabel") is Some(_) {
      Label
    } else if !response &&
      trait_string(shape, "smithy.api#httpQuery") is Some(name) {
      Query(name)
    } else if !response &&
      shape.trait_value("smithy.api#httpQueryParams") is Some(_) {
      QueryParams
    } else {
      Document
    }
    { shape, location, }
  })
}

///|
fn string_schema(schema : Json, format : String?) -> Json {
  let out = copy_fields(schema)
  for
    key in [
      "$ref", "maximum", "minimum", "exclusiveMaximum", "exclusiveMinimum", "multipleOf",
      "items", "properties", "required", "propertyNames", "oneOf", "anyOf", "not",
      "minProperties", "maxProperties", "minItems", "maxItems", "format",
    ] {
    ignore(out.remove(key))
  }
  out["type"] = Json::string("string")
  if format is Some(value) {
    out["format"] = Json::string(value)
  }
  Json::object(out)
}

///|
fn Context::parameter_schema(
  self : Context,
  shape : @smithy.Shape,
  header : Bool,
) -> Json raise OpenApiError {
  let schema = self.member_schema(shape)
  let target = self.target(shape)
  match target.body {
    @smithy.Simple(Timestamp) if shape.trait_value("smithy.api#timestampFormat")
      is None =>
      string_schema(schema, if header { None } else { Some("date-time") })
    @smithy.Simple(String) if header &&
      target.trait_value("smithy.api#mediaType") is Some(_) =>
      string_schema(schema, Some("byte"))
    @smithy.List(item) => {
      let out = copy_fields(schema)
      if self.model.shapes.get(item) is Some(item_shape) {
        ignore(out.remove("$ref"))
        out["type"] = Json::string("array")
        out["items"] = self.parameter_schema(item_shape, header)
      }
      Json::object(out)
    }
    _ => schema
  }
}

///|
fn Context::parameter(
  self : Context,
  binding : Binding,
  name : String,
  location : String,
  response : Bool,
) -> Json raise OpenApiError {
  let out : Map[String, Json] = Map([])
  let shape = binding.shape
  let target = self.target(shape)
  if !response {
    out["name"] = Json::string(name)
    out["in"] = Json::string(location)
  }
  if shape.trait_value("smithy.api#required") is Some(_) {
    out["required"] = Json::boolean(true)
  }
  let description = match trait_string(shape, "smithy.api#documentation") {
    Some(value) => Some(value)
    None => trait_string(target, "smithy.api#documentation")
  }
  if description is Some(value) {
    out["description"] = Json::string(value)
  }
  out["schema"] = self.parameter_schema(shape, location == "header")
  if binding.location is Query(_) && target.body is @smithy.List(_) {
    out["style"] = Json::string("form")
    out["explode"] = Json::boolean(true)
  }
  if binding.location == QueryParams {
    out["style"] = Json::string("form")
    if target.body is @smithy.Map(value~, ..) &&
      self.model.shapes.get(value) is Some(value_member) &&
      self.target(value_member).body is @smithy.List(_) {
      out["explode"] = Json::boolean(true)
    }
  }
  Json::object(out)
}

///|
fn Context::parameter_with_examples(
  self : Context,
  operation : @smithy.Shape,
  binding : Binding,
  name : String,
  location : String,
) -> Json raise OpenApiError {
  let parameter = copy_fields(self.parameter(binding, name, location, false))
  let examples = self.binding_examples(operation, binding, RequestExample)
  if !examples.is_empty() {
    parameter["examples"] = Json::object(examples)
  }
  Json::object(parameter)
}

///|
fn Context::payload_content(
  self : Context,
  binding : Binding,
  synthesized_name : String,
) -> Json raise OpenApiError {
  let target = self.target(binding.shape)
  let mut schema = self.member_schema(binding.shape)
  let media_type = match trait_string(target, "smithy.api#mediaType") {
    Some(value) => value
    None =>
      match target.body {
        @smithy.Simple(Blob) => "application/octet-stream"
        @smithy.Simple(String) => "text/plain"
        @smithy.Union(_) if target.trait_value("smithy.api#streaming")
          is Some(_) => "application/vnd.amazon.eventstream"
        _ => self.config.json_content_type
      }
  }
  if fields(schema).get("$ref") is None {
    schema = self.add_schema(synthesized_name, schema)
  }
  let content : Map[String, Json] = Map([])
  content[media_type] = Json::object({ "schema": schema })
  Json::object(content)
}

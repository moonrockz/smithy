///|
fn Context::external_docs(self : Context, shape : @smithy.Shape) -> Json? {
  guard shape.trait_value("smithy.api#externalDocumentation")
    is Some(@smithy.Object(urls)) else {
    return None
  }
  for preferred in self.config.external_docs {
    for name, value in urls {
      if name.to_lower() == preferred.to_lower() && value is @smithy.String(url) {
        return Some(
          Json::object({
            "description": Json::string(name),
            "url": Json::string(url),
          }),
        )
      }
    }
  }
  None
}

///|
fn Context::property_name(self : Context, shape : @smithy.Shape) -> String {
  if self.schema_config.use_json_name &&
    trait_string(shape, "smithy.api#jsonName") is Some(name) {
    name
  } else {
    shape.id.member_name().unwrap_or(shape.id.name())
  }
}

///|
fn Context::component_name(self : Context, name : String) -> String {
  if !self.config.alphanumeric_only_refs {
    return name
  }
  let out = StringBuilder()
  for ch in name {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') {
      out.write_char(ch)
    }
  }
  out.to_string()
}

///|
fn Context::schema_ref(self : Context, name : String) -> Json {
  Json::object({
    "$ref": Json::string("#/components/schemas/" + self.component_name(name)),
  })
}

///|
fn Context::add_schema(
  self : Context,
  name : String,
  schema : Json,
) -> Json raise OpenApiError {
  let name = self.component_name(name)
  if self.schemas.get(name) is Some(old) && old != schema {
    raise InvalidConfiguration(
      "Conflicting OpenAPI component name `" + name + "`",
    )
  }
  self.schemas[name] = schema
  self.schema_ref(name)
}

///|
fn Context::adapt_schema(
  self : Context,
  schema : Json,
  source : @smithy.Shape,
) -> Json {
  let out = copy_fields(schema)
  let target = self.target(source)
  if self.config.version == V3_0_2 {
    ignore(out.remove("propertyNames"))
    ignore(out.remove("contentMediaType"))
  }
  if out.get("$ref") is Some(String(_)) {
    return Json::object(out)
  }
  if source.trait_value("smithy.api#deprecated") is Some(_) ||
    target.trait_value("smithy.api#deprecated") is Some(_) {
    out["deprecated"] = Json::boolean(true)
  }
  let docs = match self.external_docs(source) {
    Some(docs) => Some(docs)
    None => self.external_docs(target)
  }
  if docs is Some(docs) {
    out["externalDocs"] = docs
  }
  match target.body {
    @smithy.Simple(Blob) =>
      if self.config.version == V3_1_0 {
        out["contentEncoding"] = Json::string(self.config.default_blob_format)
      } else {
        out["format"] = Json::string(self.config.default_blob_format)
      }
    @smithy.Simple(kind) => {
      let number_format = match kind {
        Float => Some("float")
        Double => Some("double")
        Integer if self.schema_config.use_integer_type &&
          !self.config.disable_integer_format => Some("int32")
        Long if self.schema_config.use_integer_type &&
          !self.config.disable_integer_format => Some("int64")
        Timestamp if out.get("type") == Some(Json::string("number")) &&
          source.trait_value("smithy.api#timestampFormat") is None =>
          Some("double")
        _ => None
      }
      if number_format is Some(format) && out.get("format") is None {
        if out.get("oneOf") is Some(Array(options)) {
          out["oneOf"] = Json::array(
            options.map(option => {
              let fields = copy_fields(option)
              if fields.get("type") == Some(Json::string("number")) {
                fields["format"] = Json::string(format)
              }
              Json::object(fields)
            }),
          )
        } else {
          out["format"] = Json::string(format)
        }
      }
      if (
          self.config.use_strings_for_arbitrary_precision ||
          self.protocol == RpcV2Json
        ) &&
        (kind == BigInteger || kind == BigDecimal) {
        out["type"] = Json::string("string")
        out["format"] = Json::string(
          if kind == BigInteger {
            "bigint"
          } else {
            "decimal"
          },
        )
      }
      if out.get("format") is None &&
        (
          source.trait_value("smithy.api#sensitive") is Some(_) ||
          target.trait_value("smithy.api#sensitive") is Some(_)
        ) {
        out["format"] = Json::string("password")
      }
    }
    @smithy.List(item) =>
      if out.get("items") is Some(items) &&
        self.model.shapes.get(item) is Some(shape) {
        out["items"] = self.adapt_schema(items, shape)
      }
    @smithy.Map(key~, value~) => {
      if out.get("propertyNames") is Some(value) &&
        self.model.shapes.get(key) is Some(shape) {
        out["propertyNames"] = self.adapt_schema(value, shape)
      }
      if out.get("additionalProperties") is Some(schema) &&
        self.model.shapes.get(value) is Some(shape) {
        out["additionalProperties"] = self.adapt_schema(schema, shape)
      }
      if out.get("patternProperties") is Some(Object(patterns)) &&
        self.model.shapes.get(value) is Some(shape) {
        let converted : Map[String, Json] = Map([])
        for pattern, schema in patterns {
          converted[pattern] = self.adapt_schema(schema, shape)
        }
        out["patternProperties"] = Json::object(converted)
      }
    }
    @smithy.Structure(members) | @smithy.Union(members) => {
      if out.get("properties") is Some(Object(properties)) {
        let converted : Map[String, Json] = Map([])
        for name, value in properties {
          converted[name] = value
        }
        for id in members {
          if self.model.shapes.get(id) is Some(shape) {
            let name = self.property_name(shape)
            if properties.get(name) is Some(value) {
              converted[name] = self.adapt_schema(value, shape)
            }
          }
        }
        out["properties"] = Json::object(converted)
      }
      if out.get("oneOf") is Some(Array(options)) {
        out["oneOf"] = Json::array(
          options.map(option => {
            let wrapper = copy_fields(option)
            if wrapper.get("properties") is Some(Object(properties)) {
              let converted : Map[String, Json] = Map([])
              for name, value in properties {
                converted[name] = value
              }
              for id in members {
                if self.model.shapes.get(id) is Some(shape) {
                  let name = self.property_name(shape)
                  if properties.get(name) is Some(value) {
                    converted[name] = self.adapt_schema(value, shape)
                  }
                }
              }
              wrapper["properties"] = Json::object(converted)
            }
            Json::object(wrapper)
          }),
        )
      }
    }
    _ => ()
  }
  Json::object(out)
}

///|
fn Context::prepare_schemas(self : Context) -> Unit {
  let document = self.index.document()
  guard document is { "components": { "schemas": Object(schemas), .. }, .. } else {
    return
  }
  for name, schema in schemas {
    self.schemas[name] = match
      self.index.definition(name).bind(id => self.model.shapes.get(id)) {
      Some(shape) => self.adapt_schema(schema, shape)
      None => schema
    }
  }
}

///|
fn Context::member_schema(
  self : Context,
  shape : @smithy.Shape,
) -> Json raise OpenApiError {
  let schema = self.index.schema_for_member(shape.id) catch {
    @jsonschema.InvalidConfiguration(message)
    | @jsonschema.ConflictingShapeName(message) =>
      raise SchemaConversion(message)
  }
  self.adapt_schema(schema, shape)
}

///|
fn Context::document_schema(
  self : Context,
  container : @smithy.ShapeId,
  members : Array[@smithy.Shape],
) -> Json raise OpenApiError {
  let schema = self.index.structure(container, members.map(shape => shape.id)) catch {
    @jsonschema.InvalidConfiguration(message)
    | @jsonschema.ConflictingShapeName(message) =>
      raise SchemaConversion(message)
  }
  guard self.model.shapes.get(container) is Some(shape) else { return schema }
  self.adapt_schema(schema, shape)
}

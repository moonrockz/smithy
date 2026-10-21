///|
pub fn convert_result(
  model : @smithy.Model,
  config : Config,
) -> Conversion raise OpenRpcError {
  let id = config.service.shape_id()
  guard config.protocol_version == @rpc.V2_0 else {
    raise InvalidConfiguration(
      id, "I can export only JSON-RPC wire version 2.0 as OpenRPC.",
    )
  }
  let prepared = @rpc.PreparedService::prepare(
    model,
    id,
    @rpc.V2_0,
    config=@validation.Config::new(
      member_names=config.member_names,
      timestamp_format=config.timestamp_format,
    ),
  ) catch {
    @rpc.InvalidContract(subject, message) =>
      raise InvalidContract(subject, message)
    @validation.InvalidTarget(subject, message)
    | @validation.InvalidModel(subject, message)
    | @validation.UnsupportedConstraint(subject, message) =>
      raise InvalidContract(subject, message)
    error => raise InvalidContract(id, error.to_string())
  }
  let root = model.shapes[id]
  let index = @jsonschema.SchemaIndex::for_values(
    model,
    service=id.to_string(),
    config=@jsonschema.Config::new(
      definition_pointer="#/components/schemas",
      use_json_name=config.member_names == @validation.JsonName,
      default_timestamp_format=if config.timestamp_format ==
        @validation.EpochSeconds {
        "epoch-seconds"
      } else {
        "date-time"
      },
      use_integer_type=true,
      disable_default_values=true,
    ),
  ) catch {
    @jsonschema.ConflictingShapeName(message)
    | @jsonschema.InvalidConfiguration(message) =>
      raise SchemaConversion(id, message)
    error => raise SchemaConversion(id, error.to_string())
  }
  let warnings : Array[ConversionWarning] = []
  let methods : Array[Json] = []
  for contract in prepared.contracts() {
    let operation = model.shapes[contract.operation]
    let members = if contract.mode == @rpc.Named {
      match model.shapes[contract.input].body {
        Structure(ids) => {
          let sorted = ids.copy()
          sorted.sort_by((a, b) => {
            member_name(model.shapes[a], config).lexical_compare(
              member_name(model.shapes[b], config),
            )
          })
          sorted
        }
        _ => []
      }
    } else {
      contract.positional
    }
    let params : Array[Json] = []
    for member_id in members {
      let member_ = model.shapes[member_id]
      params.push(
        descriptor(
          model,
          index,
          member_id,
          member_name(member_, config),
          member_.trait_value("smithy.api#required") is Some(_),
          config,
          warnings,
        ),
      )
    }
    let result = match contract.result {
      @rpc.OutputMember(target) =>
        descriptor(model, index, target, "result", true, config, warnings)
      @rpc.OutputStructure(target) =>
        descriptor(model, index, target, "result", true, config, warnings)
      @rpc.NullResult =>
        Json::object({
          "name": Json::string("result"),
          "required": Json::boolean(true),
          "schema": Json::object({ "type": Json::string("null") }),
        })
    }
    let method_ : Map[String, Json] = {
      "name": Json::string(contract.name.to_string()),
      "paramStructure": Json::string(
        match contract.mode {
          @rpc.Named => "by-name"
          @rpc.Positional => "by-position"
          @rpc.Either => "either"
        },
      ),
      "params": Json::array(params),
      "result": result,
    }
    if trait_text(operation, "smithy.api#documentation") is Some(text) {
      method_["description"] = Json::string(text)
    }
    if trait_text(operation, "smithy.api#title") is Some(text) {
      method_["summary"] = Json::string(text)
    }
    if operation.trait_value("smithy.api#deprecated") is Some(_) {
      method_["deprecated"] = Json::boolean(true)
    }
    let errors : Array[Json] = []
    let error_data : Array[Json] = []
    for error in contract.errors {
      errors.push(
        Json::object({
          "code": error.code.number().to_json(),
          "message": Json::string(
            trait_text(model.shapes[error.shape], "smithy.api#title").unwrap_or(
              error.shape.name(),
            ),
          ),
        }),
      )
      let mapping : Map[String, Json] = {
        "code": error.code.number().to_json(),
        "shape": Json::string(error.shape.to_string()),
        "required": Json::boolean(error.data_required),
      }
      mapping["schema"] = match error.data {
        Some(target) => value_schema(index, target, config, warnings)
        None => Json::boolean(false)
      }
      error_data.push(Json::object(mapping))
    }
    if !errors.is_empty() {
      method_["errors"] = Json::array(errors)
    }
    if !error_data.is_empty() {
      match config.extensions {
        Preserve => method_["x-smithy-error-data"] = Json::array(error_data)
        Omit =>
          warnings.push({
            code: OmittedErrorData,
            shape: contract.operation,
            message: "I omitted application error data schemas; use extensions=preserve to retain them.",
          })
        Fail =>
          raise UnsupportedMapping(
            contract.operation,
            "I need x-smithy-error-data to describe application error data; use extensions=preserve.",
          )
      }
    }
    add_examples(model, config, prepared, contract, method_, warnings)
    methods.push(Json::object(method_))
  }
  let version = match root.body {
    Service(version~, ..) => version
    _ => ""
  }
  let info : Map[String, Json] = {
    "title": Json::string(
      config.title.unwrap_or(
        trait_text(root, "smithy.api#title").unwrap_or(id.name()),
      ),
    ),
    "version": Json::string(config.api_version.unwrap_or(version)),
  }
  if trait_text(root, "smithy.api#documentation") is Some(text) {
    info["description"] = Json::string(text)
  }
  let document : Map[String, Json] = {
    "openrpc": Json::string(config.version.to_string()),
    "info": Json::object(info),
    "methods": Json::array(methods),
  }
  let schemas = used_schemas(index, methods, id)
  for name, schema in schemas {
    schema_policy(
      schema,
      index.definition(name).unwrap_or(id),
      config,
      warnings,
    )
  }
  if !schemas.is_empty() {
    document["components"] = Json::object({ "schemas": Json::object(schemas) })
  }
  match config.extensions {
    Preserve =>
      document["x-smithy-protocol"] = Json::object({
        "version": Json::string("2.0"),
        "schemaDialect": Json::string("http://json-schema.org/draft-07/schema#"),
        "notifications": Json::string(
          "An absent id is a notification; a null result does not mean notification-only.",
        ),
        "batches": Json::string(
          "JSON-RPC 2.0 batch and exchange rules apply outside method value schemas.",
        ),
      })
    Omit =>
      warnings.push({
        code: OmittedProtocolSemantics,
        shape: id,
        message: "I omitted notification, batch and exchange metadata; OpenRPC method schemas do not validate envelopes or exchanges.",
      })
    Fail =>
      raise UnsupportedMapping(
        id, "I need x-smithy-protocol to retain notification, batch and exchange boundaries; use extensions=preserve.",
      )
  }
  { document: Json::object(document), warnings, }
}

///|
pub fn convert(
  model : @smithy.Model,
  config : Config,
) -> Json raise OpenRpcError {
  convert_result(model, config).document
}

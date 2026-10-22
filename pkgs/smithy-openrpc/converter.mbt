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
  let methods : Array[@rpcdoc.InlineOrReference[@rpcdoc.Method]] = []
  let operations : Array[@smithy.ShapeId] = []
  // Schemas the document uses, in method order, for component selection.
  let roots : Array[Json] = []
  for contract in prepared.contracts() {
    let operation = model.shapes[contract.operation]
    let params : Array[@rpcdoc.InlineOrReference[@rpcdoc.ContentDescriptor]] = []
    for member_id in parameter_members(model, contract, config) {
      let member_ = model.shapes[member_id]
      params.push(
        @rpcdoc.Inline(
          descriptor(
            model,
            index,
            member_id,
            member_name(member_, config),
            member_.trait_value("smithy.api#required") is Some(_),
            config,
            warnings,
            roots,
          ),
        ),
      )
    }
    let result = match contract.result {
      @rpc.OutputMember(target) =>
        descriptor(
          model, index, target, "result", true, config, warnings, roots,
        )
      @rpc.OutputStructure(target) =>
        descriptor(
          model, index, target, "result", true, config, warnings, roots,
        )
      @rpc.NullResult => {
        let schema = Json::object({ "type": Json::string("null") })
        roots.push(schema)
        built(
          @rpcdoc.ContentDescriptor::new(
            "result",
            draft07_schema(schema, contract.operation),
            required=Some(true),
            limits=limits(),
          ),
          contract.operation,
        )
      }
    }
    let errors : Array[@rpcdoc.InlineOrReference[@rpcdoc.ErrorObject]] = []
    let error_data : Array[Json] = []
    for error in contract.errors {
      errors.push(
        @rpcdoc.Inline(
          built(
            @rpcdoc.ErrorObject::new(
              built(
                @rpcdoc.ErrorCode::parse(error.code.to_string()),
                error.shape,
              ),
              trait_text(model.shapes[error.shape], "smithy.api#title").unwrap_or(
                error.shape.name(),
              ),
              limits=limits(),
            ),
            error.shape,
          ),
        ),
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
    let method_extensions : Array[(String, Json)] = []
    if !error_data.is_empty() {
      match config.extensions {
        Preserve => {
          for mapping in error_data {
            roots.push(fields(mapping)["schema"])
          }
          method_extensions.push(
            ("x-smithy-error-data", Json::array(error_data)),
          )
        }
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
    let examples = method_examples(model, config, prepared, contract, warnings)
    if !examples.errors.is_empty() {
      method_extensions.push(
        ("x-smithy-error-examples", Json::array(examples.errors)),
      )
    }
    methods.push(
      @rpcdoc.Inline(
        built(
          @rpcdoc.Method::new(
            built(
              @rpcdoc.MethodName::parse(contract.name.to_string()),
              contract.operation,
            ),
            params,
            result=Some(@rpcdoc.Inline(result)),
            summary=trait_text(operation, "smithy.api#title"),
            description=trait_text(operation, "smithy.api#documentation"),
            deprecated=if operation.trait_value("smithy.api#deprecated")
              is Some(_) {
              Some(true)
            } else {
              None
            },
            errors=if errors.is_empty() { None } else { Some(errors) },
            param_structure=Some(
              match contract.mode {
                @rpc.Named => @rpcdoc.ByName
                @rpc.Positional => @rpcdoc.ByPosition
                @rpc.Either => @rpcdoc.Either
              },
            ),
            examples=if examples.successes.is_empty() {
              None
            } else {
              Some(examples.successes.map(pairing => @rpcdoc.Inline(pairing)))
            },
            extensions=extensions(method_extensions, contract.operation),
            limits=limits(),
          ),
          contract.operation,
        ),
      ),
    )
    operations.push(contract.operation)
  }
  let version = match root.body {
    Service(version~, ..) => version
    _ => ""
  }
  let info = built(
    @rpcdoc.Info::new(
      config.title.unwrap_or(
        trait_text(root, "smithy.api#title").unwrap_or(id.name()),
      ),
      config.api_version.unwrap_or(version),
      description=trait_text(root, "smithy.api#documentation"),
      limits=limits(),
    ),
    id,
  )
  let components : Array[(@rpcdoc.ComponentKey, @draft07.Schema)] = []
  for name, schema in used_schemas(index, roots, id) {
    let subject = index.definition(name).unwrap_or(id)
    schema_policy(schema, subject, config, warnings)
    components.push(
      (
        built(@rpcdoc.ComponentKey::parse(name), subject),
        draft07_schema(schema, subject),
      ),
    )
  }
  let document_extensions : Array[(String, Json)] = []
  match config.extensions {
    Preserve =>
      document_extensions.push(
        (
          "x-smithy-protocol",
          Json::object({
            "version": Json::string("2.0"),
            "schemaDialect": Json::string(
              "http://json-schema.org/draft-07/schema#",
            ),
            "notifications": Json::string(
              "An absent id is a notification; a null result does not mean notification-only.",
            ),
            "batches": Json::string(
              "JSON-RPC 2.0 batch and exchange rules apply outside method value schemas.",
            ),
          }),
        ),
      )
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
  let document = match
    @rpcdoc.Document::new(
      built(@rpcdoc.DocumentVersion::parse(config.version.to_string()), id),
      info,
      methods,
      components=if components.is_empty() {
        None
      } else {
        Some(
          built(
            @rpcdoc.Components::new(schemas=Some(components), limits=limits()),
            id,
          ),
        )
      },
      extensions=extensions(document_extensions, id),
      limits=limits(),
    ) {
    Ok(document) => document
    Err(diagnostics) =>
      raise UnsupportedMapping(
        id,
        "I could not build the OpenRPC document: " +
        diagnostics.map(d => d.message()).join("; "),
      )
  }
  { document: validated_json(document, id, operations), warnings, }
}

///|
/// Named-only descriptors sort by wire member name; positional and either
/// descriptors follow the explicit positional list.
fn parameter_members(
  model : @smithy.Model,
  contract : @rpc.MethodContract,
  config : Config,
) -> Array[@smithy.ShapeId] {
  guard contract.mode == @rpc.Named else { return contract.positional }
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
}

///|
pub fn convert(
  model : @smithy.Model,
  config : Config,
) -> Json raise OpenRpcError {
  convert_result(model, config).document
}

///|
fn example_value(
  model : @smithy.Model,
  id : @smithy.ShapeId,
  value : @smithy.NodeValue,
  config : Config,
  depth : Int32,
) -> @smithy.NodeValue raise OpenRpcError {
  if depth > 128 {
    raise InvalidContract(id, "I reached the modeled example nesting limit.")
  }
  guard model.shapes.get(id) is Some(shape) else {
    raise InvalidContract(id, "I could not resolve the example data shape.")
  }
  let target = match shape.body {
    Member(target~) => model.shapes[target]
    _ => shape
  }
  match (target.body, value) {
    (Structure(_) | Union(_), Object(values)) => {
      let out : Map[String, @smithy.NodeValue] = Map([])
      for name, value in values {
        if target.id.with_member(name) is Some(member_id) &&
          model.shapes.get(member_id) is Some(member_) {
          out[member_name(member_, config)] = example_value(
            model,
            member_id,
            value,
            config,
            depth + 1,
          )
        } else {
          raise InvalidContract(
            id,
            "I found unknown modeled example member `" +
            name +
            "` on `" +
            target.id.to_string() +
            "`.",
          )
        }
      }
      @smithy.Object(out)
    }
    (List(member_), Array(values)) =>
      @smithy.Array(
        values.map(v => example_value(model, member_, v, config, depth + 1)),
      )
    (Map(value=member_, ..), Object(values)) => {
      let out : Map[String, @smithy.NodeValue] = Map([])
      for key, value in values {
        out[key] = example_value(model, member_, value, config, depth + 1)
      }
      @smithy.Object(out)
    }
    _ => value
  }
}

///|
fn[T] example_error(
  id : @smithy.ShapeId,
  title : String,
  message : String,
) -> T raise OpenRpcError {
  raise InvalidContract(
    id,
    "I could not export example `" + title + "`: " + message,
  )
}

///|
fn validate_example_result(
  prepared : @rpc.PreparedService,
  contract : @rpc.MethodContract,
  response : Map[String, @smithy.NodeValue],
  title : String,
) -> Unit raise OpenRpcError {
  response["jsonrpc"] = @smithy.String("2.0")
  response["id"] = @smithy.Null
  let checked = prepared.validate_response(
    @smithy.Object(response).to_json().stringify(),
    context=Some(@rpc.Method(contract.name)),
  )
  if !checked.is_valid() {
    example_error(
      contract.operation,
      title,
      checked.findings.map(f => f.message).join(" "),
    )
  }
}

///|
/// Standard example pairings and the `x-smithy-error-examples` entries.
priv struct MethodExamples {
  successes : Array[@rpcdoc.ExamplePairing]
  errors : Array[Json]
}

///|
fn method_examples(
  model : @smithy.Model,
  config : Config,
  prepared : @rpc.PreparedService,
  contract : @rpc.MethodContract,
  warnings : Array[ConversionWarning],
) -> MethodExamples raise OpenRpcError {
  let successes : Array[@rpcdoc.ExamplePairing] = []
  let errors : Array[Json] = []
  let operation = model.shapes[contract.operation]
  guard operation.trait_value("smithy.api#examples")
    is Some(@smithy.Array(examples)) else {
    return { successes, errors, }
  }
  let titles : Set[String] = Set([])
  for example in examples {
    guard example is @smithy.Object(fields) &&
      fields.get("title") is Some(@smithy.String(title)) &&
      !title.is_empty() else {
      example_error(
        contract.operation,
        "",
        "I expected a nonempty example title.",
      )
    }
    if titles.contains(title) {
      example_error(
        contract.operation,
        title,
        "I expected unique example names.",
      )
    }
    titles.add(title)
    let input = fields.get("input").unwrap_or(@smithy.Object(Map([])))
    let wire = example_value(model, contract.input, input, config, 0)
    guard wire is @smithy.Object(values) else {
      example_error(contract.operation, title, "I expected a structure input.")
    }
    let ids = parameter_members(model, contract, config)
    let params : Array[@rpcdoc.InlineOrReference[@rpcdoc.Example]] = []
    let positional : Array[@smithy.NodeValue] = []
    let mut hole = false
    let mut interior = false
    for id in ids {
      let name = member_name(model.shapes[id], config)
      match values.get(name) {
        Some(value) => {
          if hole {
            interior = true
          }
          positional.push(value)
          params.push(
            literal_example(name, value.to_json(), contract.operation),
          )
        }
        None => hole = true
      }
    }
    if contract.mode == @rpc.Positional && interior {
      example_error(
        contract.operation,
        title,
        "I cannot omit an interior positional argument; provide an explicit valid value.",
      )
    }
    let request = @smithy.Object({
      "jsonrpc": @smithy.String("2.0"),
      "method": @smithy.String(contract.name.to_string()),
      "params": if contract.mode == @rpc.Positional {
        @smithy.Array(positional)
      } else {
        wire
      },
    })
    let checked = prepared.validate_request(request.to_json().stringify())
    if !checked.is_valid() {
      example_error(
        contract.operation,
        title,
        checked.findings.map(f => f.message).join(" "),
      )
    }
    let description = match fields.get("documentation") {
      Some(@smithy.String(text)) => Some(text)
      _ => None
    }
    let pairing_extensions : Array[(String, Json)] = []
    if interior && contract.mode == @rpc.Either {
      if config.extensions == Preserve {
        pairing_extensions.push(
          ("x-smithy-param-structure", Json::string("by-name")),
        )
      } else {
        if config.extensions == Fail {
          raise UnsupportedMapping(
            contract.operation,
            "I need x-smithy-param-structure for a named example omitting interior positional arguments.",
          )
        }
        warnings.push({
          code: OmittedExample,
          shape: contract.operation,
          message: "I omitted example `" +
          title +
          "` because it needs named parameter metadata.",
        })
        continue
      }
    }
    if fields.get("error") is Some(@smithy.Object(error)) {
      guard error.get("shapeId") is Some(@smithy.String(shape_id)) &&
        @smithy.ShapeId::parse(shape_id) is Some(error_id) else {
        example_error(
          contract.operation,
          title,
          "I expected a modeled application error shape.",
        )
      }
      let mut selected : @rpc.ErrorContract? = None
      for error in contract.errors {
        if error.shape == error_id {
          selected = Some(error)
        }
      }
      guard selected is Some(mapping) else {
        example_error(
          contract.operation,
          title,
          "I expected a modeled application error shape.",
        )
      }
      let content = error.get("content").unwrap_or(@smithy.Object(Map([])))
      let wire = example_value(model, error_id, content, config, 0)
      let error_value : Map[String, @smithy.NodeValue] = {
        "code": @smithy.Number(mapping.code.number()),
        "message": @smithy.String(error_id.name()),
      }
      match mapping.data {
        None => ()
        Some(target) if target.member_name() is Some(name) => {
          let member_ = model.shapes[target]
          if wire is @smithy.Object(content) &&
            content.get(member_name(member_, config)) is Some(value) {
            error_value["data"] = value
          } else if mapping.data_required {
            example_error(
              contract.operation,
              title,
              "I expected required error data member `" + name + "`.",
            )
          }
        }
        Some(_) => error_value["data"] = wire
      }
      validate_example_result(
        prepared,
        contract,
        { "error": @smithy.Object(error_value) },
        title,
      )
      match config.extensions {
        Preserve => {
          let pairing = built(
            @rpcdoc.ExamplePairing::new(
              title,
              params,
              description~,
              extensions=extensions(pairing_extensions, contract.operation),
              additional_fields=[
                (
                  "error",
                  exact(
                    @smithy.Object(error_value).to_json(),
                    contract.operation,
                  ),
                ),
              ],
              limits=limits(),
            ),
            contract.operation,
          )
          errors.push(
            built(
              @exact.to_core_json(pairing.to_json(), limits=limits()),
              contract.operation,
            ),
          )
        }
        Omit =>
          warnings.push({
            code: OmittedExample,
            shape: contract.operation,
            message: "I omitted error example `" +
            title +
            "`; OpenRPC example pairings have no standard error field.",
          })
        Fail =>
          raise UnsupportedMapping(
            contract.operation,
            "I need x-smithy-error-examples for modeled application error examples.",
          )
      }
    } else {
      let mut result = None
      if fields.get("output") is Some(output) {
        let value = match contract.result {
          @rpc.NullResult => @smithy.Null
          @rpc.OutputStructure(target) =>
            example_value(model, target, output, config, 0)
          @rpc.OutputMember(target) => {
            guard output is @smithy.Object(values) &&
              values.get(target.member_name().unwrap()) is Some(value) else {
              example_error(
                contract.operation,
                title,
                "I expected the selected result member in the example output.",
              )
            }
            example_value(model, target, value, config, 0)
          }
        }
        validate_example_result(prepared, contract, { "result": value }, title)
        result = Some(
          literal_example("result", value.to_json(), contract.operation),
        )
      }
      successes.push(
        built(
          @rpcdoc.ExamplePairing::new(
            title,
            params,
            description~,
            result~,
            extensions=extensions(pairing_extensions, contract.operation),
            limits=limits(),
          ),
          contract.operation,
        ),
      )
    }
  }
  { successes, errors, }
}

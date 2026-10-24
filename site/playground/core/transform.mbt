///|
/// A response for a request that did not run for a reason other than model errors.
fn blocked(seq~ : Int32, reason~ : String) -> Response {
  Blocked(seq~, reason~, kind=Other)
}

///|
/// The user services of the model, by shape ID.
fn user_services(model : @smithy.Model) -> Array[@smithy.Shape] {
  let services = []
  for _, shape in model.shapes {
    if !shape.source.is_builtin() && shape.body is Service(..) {
      services.push(shape)
    }
  }
  services.sort_by_key(shape => shape.id.to_string())
  services
}

///|
/// Whether the service has a `jsonRpc` trait that names wire version 2.0.
fn speaks_json_rpc_2(shape : @smithy.Shape) -> Bool {
  match shape.trait_value("smithy.rpc#jsonRpc") {
    Some(Object(fields)) =>
      match fields.get("versions") {
        Some(Array(versions)) => versions.contains(String("2.0"))
        _ => false
      }
    _ => false
  }
}

///|
/// Whether the service has a protocol trait: a trait whose definition has
/// `smithy.api#protocolDefinition`. The OpenAPI converter looks for the same.
fn has_protocol_trait(model : @smithy.Model, shape : @smithy.Shape) -> Bool {
  for id, _ in shape.traits {
    if model.shapes.get(id) is Some(definition) &&
      definition.trait_value("smithy.api#protocolDefinition") is Some(_) {
      return true
    }
  }
  false
}

///|
/// The first service by shape ID that the output can use. OpenRPC needs a
/// `jsonRpc` trait for version 2.0, as the CLI does. OpenAPI needs a protocol
/// trait.
fn pick_service(
  model : @smithy.Model,
  output : Output,
) -> Result[String, String] {
  let services = user_services(model)
  let usable = match output {
    OpenRpc => services.filter(speaks_json_rpc_2)
    OpenApi30 | OpenApi31 =>
      services.filter(service => has_protocol_trait(model, service))
    _ => services
  }
  match usable {
    [first, ..] => Ok(first.id.to_string())
    [] =>
      Err(
        if output == OpenRpc {
          "I found no service with a jsonRpc trait for version 2.0 in the model."
        } else if services.is_empty() {
          "I found no service in the model."
        } else {
          "I found no service with a protocol trait in the model."
        },
      )
  }
}

///|
/// A warning of a converter, as the CLI prints it.
fn warning_line(shape : @smithy.ShapeId, message : String) -> String {
  "WARNING: " + shape.to_string() + ": " + message
}

///|
fn json_ast_file(model : @smithy.Model) -> Array[(String, String)] raise {
  [
    (
      "model.json",
      @syntax.encode_json_ast(model.to_json_ast()).stringify(indent=4) + "\n",
    ),
  ]
}

///|
/// The IDL of each ns, in ns order.
fn idl_files(model : @smithy.Model) -> Array[(String, String)] raise {
  let files = model.to_idl()
  let nss = files.keys().to_array()
  nss.sort()
  nss.map(ns => {
    let name = if ns == "" { "model" } else { ns }
    (name + ".smithy", files.get(ns).unwrap())
  })
}

///|
fn selector_file(
  model : @smithy.Model,
  expression : String?,
) -> Result[Array[(String, String)], String] {
  guard expression is Some(text) && text.trim().to_owned() != "" else {
    return Err("I expected a selector. Write one, for example: structure")
  }
  let selector = @smithy.Selector::parse(text) catch {
    @smithy.InvalidSelector(message) => return Err(message)
  }
  let ids = selector.select_ids(model)
  Ok([("selector.txt", if ids.is_empty() { "" } else { ids.join("\n") + "\n" })])
}

///|
fn json_schema_file(
  model : @smithy.Model,
) -> Result[Array[(String, String)], String] {
  let document = @jsonschema.convert(model) catch {
    error => return Err("JSON Schema conversion failed: " + error.to_string())
  }
  Ok([("schema.json", document.stringify(indent=4) + "\n")])
}

///|
fn open_api_file(
  model : @smithy.Model,
  service : String,
  version : String,
) -> Result[(Array[(String, String)], Array[String], String?), String] {
  let settings : Json = { "service": service, "version": version }
  let config = @openapi.Config::from_json(settings) catch {
    error => return Err("OpenAPI conversion failed: " + error.message())
  }
  let result = @openapi.convert_result(model, config) catch {
    error => return Err("OpenAPI conversion failed: " + error.message())
  }
  let name = config.service().shape_id().name() + ".openapi.json"
  Ok(
    (
      [(name, result.document.stringify(indent=4) + "\n")],
      result.warnings.map(w => warning_line(w.shape, w.message)),
      Some(service),
    ),
  )
}

///|
fn open_rpc_file(
  model : @smithy.Model,
  service : String,
) -> Result[(Array[(String, String)], Array[String], String?), String] {
  let settings : Json = { "service": service }
  let config = @openrpc.Config::from_json(settings) catch {
    error => return Err("OpenRPC conversion failed: " + error.message())
  }
  let result = @openrpc.convert_result(model, config) catch {
    error => return Err("OpenRPC conversion failed: " + error.message())
  }
  Ok(
    (
      [("openrpc.json", result.document.stringify(indent=2) + "\n")],
      result.warnings.map(w => warning_line(w.shape, w.message)),
      Some(service),
    ),
  )
}

///|
/// The files of the output, the warnings of its converter and the service it used.
fn run_output(
  model : @smithy.Model,
  output : Output,
  selector : String?,
) -> Result[(Array[(String, String)], Array[String], String?), String] {
  match output {
    JsonAst =>
      try json_ast_file(model) catch {
        error => Err(error.to_string())
      } noraise {
        files => Ok((files, [], None))
      }
    Idl =>
      try idl_files(model) catch {
        error => Err(error.to_string())
      } noraise {
        files => Ok((files, [], None))
      }
    Selector => selector_file(model, selector).map(files => (files, [], None))
    JsonSchema => json_schema_file(model).map(files => (files, [], None))
    OpenApi30 | OpenApi31 | OpenRpc =>
      match pick_service(model, output) {
        Err(reason) => Err(reason)
        Ok(service) =>
          match output {
            OpenApi30 => open_api_file(model, service, "3.0.2")
            OpenApi31 => open_api_file(model, service, "3.1.0")
            _ => open_rpc_file(model, service)
          }
      }
  }
}

///|
/// The load of the files for `output`, as `TransformFiles` does it: the OpenAPI
/// outputs load with the bundled protocol definitions, the others without.
fn load_for(
  files : Array[(String, String)],
  output : Output,
) -> Result[@smithy.LoadResult, String] {
  match output {
    OpenApi30 | OpenApi31 => load_with_http_protocols(files)
    _ => Ok(load(files))
  }
}

///|
fn transform(
  seq : Int32,
  files : Array[(String, String)],
  output : Output,
  selector : String?,
) -> Response {
  let loaded = match load_for(files, output) {
    Ok(loaded) => loaded
    Err(reason) => return blocked(seq~, reason~)
  }
  match clean_model(loaded) {
    Err((reason, kind)) => Blocked(seq~, reason~, kind~)
    Ok(assembled) =>
      match run_output(assembled, output, selector) {
        Ok((files, warnings, service)) =>
          Transformed(seq~, files~, warnings~, service~)
        Err(reason) => blocked(seq~, reason~)
      }
  }
}

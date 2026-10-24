///|
/// The name that the model text gets in the loader. Diagnostics of the text
/// name this file.
const MODEL_FILE : String = "model.smithy"

///|
/// Load the model files, as (name, text), with the `smithy.rpc` traits, as the
/// CLI does.
fn load(files : Array[(String, String)]) -> @smithy.LoadResult {
  let loader = @rpc.loader()
  for file in files {
    ignore(loader.add_idl(file.0, file.1))
  }
  loader.assemble()
}

///|
/// The OpenAPI protocol definitions as an assembled model, built on first use.
/// `None` when they do not assemble.
let http_protocols : @lazy.Lazy[@smithy.Model?] = Lazy(() => {
  let provider = @smithy.Loader::new()
  for input in @openapi.protocol_definitions() {
    ignore(provider.add(input))
  }
  provider.assemble().model
})

///|
/// Load the model text with the OpenAPI protocol definitions as provider
/// defaults, as `smithy build` does for the openapi plugin. The model needs
/// them to name `aws.protocols#restJson1`.
fn load_with_http_protocols(
  files : Array[(String, String)],
) -> Result[@smithy.LoadResult, String] {
  let failure = "Could not load bundled OpenAPI protocol definitions"
  guard http_protocols.force() is Some(protocols) else { return Err(failure) }
  let loader = @rpc.loader()
  ignore(loader.add_defaults(protocols)) catch {
    _ => return Err(failure)
  }
  for file in files {
    ignore(loader.add_idl(file.0, file.1))
  }
  Ok(loader.assemble())
}

///|
fn is_error_event(event : @smithy.ValidationEvent) -> Bool {
  event.severity == "ERROR" || event.severity == "DANGER"
}

///|
/// The number of events that stop a transform.
fn error_count(loaded : @smithy.LoadResult) -> Int32 {
  loaded.validation_events().filter(is_error_event).length()
}

///|
/// The model of a load without errors, or the reason to stop and its kind.
fn clean_model(
  loaded : @smithy.LoadResult,
) -> Result[@smithy.Model, (String, BlockKind)] {
  let errors = error_count(loaded)
  match loaded.model {
    Some(model) if errors == 0 => Ok(model)
    None if errors == 0 =>
      Err(
        (
          "I could not build a model from the text, and I have no error to show.",
          Other,
        ),
      )
    _ =>
      Err(
        (
          if errors == 1 {
            "The model has 1 error. Fix it in the Validate tab, then run again."
          } else {
            "The model has \{errors} errors. Fix them in the Validate tab, then run again."
          },
          ModelErrors,
        ),
      )
  }
}

///|
fn diagnostic_of(
  event : @smithy.ValidationEvent,
  sources : Map[String, @syntax.SourceText],
) -> Diagnostic {
  let (file, start, end) = match event.source {
    None => ("", (0, 0), (0, 0))
    Some(location) =>
      match location.span {
        Some(span) =>
          match sources.get(location.file) {
            Some(source) => {
              let a = source.position(span.start)
              let b = source.position(span.end())
              (location.file, (a.line.0, a.column.0), (b.line.0, b.column.0))
            }
            None => (location.file, (0, 0), (0, 0))
          }
        None => (location.file, (0, 0), (0, 0))
      }
  }
  {
    severity: event.severity,
    code: event.id,
    message: event.message,
    file,
    start_line: start.0,
    start_column: start.1,
    end_line: end.0,
    end_column: end.1,
    shape: event.shape.map(id => id.to_string()),
  }
}

///|
/// The shapes that the model text defines, without members and built-ins.
fn shape_count(model : @smithy.Model) -> Int32 {
  let mut count = 0
  for _, shape in model.shapes {
    if !shape.source.is_builtin() && !(shape.body is Member(..)) {
      count += 1
    }
  }
  count
}

///|
/// The members of the `jsonRpcProtocol` trait of a shape, or `None` when the
/// shape does not have it.
fn protocol_trait(shape : @smithy.Shape) -> Map[String, @smithy.NodeValue]? {
  match shape.trait_value("smithy.rpc#jsonRpcProtocol") {
    Some(Object(fields)) => Some(fields)
    _ => None
  }
}

///|
/// The strings of the array `field` of a trait. With `name`, each item is an
/// object and the string is its member `name`; without it, each item is a
/// string.
fn trait_strings(
  fields : Map[String, @smithy.NodeValue],
  field : String,
  name? : String,
) -> Array[String] {
  guard fields.get(field) is Some(Array(items)) else { return [] }
  items.filter_map(item => {
    match (item, name) {
      (String(text), None) => Some(text)
      (Object(object), Some(key)) =>
        match object.get(key) {
          Some(String(text)) => Some(text)
          _ => None
        }
      _ => None
    }
  })
}

///|
/// The peer names of a protocol shape, in trait order.
fn protocol_peers(shape : @smithy.Shape) -> Array[String] {
  match protocol_trait(shape) {
    Some(fields) => trait_strings(fields, "peers", name="name")
    None => []
  }
}

///|
/// Compare two strings character by character, as a dictionary does.
/// `String::compare` puts a shorter string first.
fn text_compare(a : String, b : String) -> Int32 {
  let ai = a.iter()
  let bi = b.iter()
  while true {
    match (ai.next(), bi.next()) {
      (None, None) => return 0
      (None, _) => return -1
      (_, None) => return 1
      (Some(x), Some(y)) => if x != y { return x.compare(y) }
    }
  }
  0
}

///|
/// The structures with the `jsonRpcProtocol` trait, by shape ID: the version
/// strings and the peer names that the trait gives.
fn protocols_of(model : @smithy.Model) -> Array[ProtocolView] {
  let out = []
  for id, shape in model.shapes {
    guard protocol_trait(shape) is Some(fields) else { continue }
    out.push({
      id: id.to_string(),
      versions: trait_strings(fields, "versions"),
      peers: trait_strings(fields, "peers", name="name"),
    })
  }
  out.sort_by((a, b) => text_compare(a.id, b.id))
  out
}

///|
fn validate(seq : Int32, files : Array[(String, String)]) -> Response {
  let loaded = load(files)
  let sources : Map[String, @syntax.SourceText] = Map([])
  for file in files {
    sources[file.0] = @syntax.SourceText::new(file.1)
  }
  let items = loaded
    .validation_events()
    .map(event => diagnostic_of(event, sources))
  let (shapes, protocols) = match loaded.model {
    Some(model) => (shape_count(model), protocols_of(model))
    None => (0, [])
  }
  Diagnostics(seq~, items~, shapes~, protocols~)
}

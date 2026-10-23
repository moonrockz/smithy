///|
/// The name that the model text gets in the loader. Diagnostics of the text
/// name this file.
const MODEL_FILE : String = "model.smithy"

///|
/// Load the model text with the `smithy.rpc` traits, as the CLI does.
fn load(model : String) -> @smithy.LoadResult {
  @rpc.loader().add_idl(MODEL_FILE, model).assemble()
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
  model : String,
) -> Result[@smithy.LoadResult, String] {
  let failure = "Could not load bundled OpenAPI protocol definitions"
  guard http_protocols.force() is Some(protocols) else { return Err(failure) }
  let loader = @rpc.loader()
  ignore(loader.add_defaults(protocols)) catch {
    _ => return Err(failure)
  }
  Ok(loader.add_idl(MODEL_FILE, model).assemble())
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
  source : @syntax.SourceText,
) -> Diagnostic {
  let (file, start, end) = match event.source {
    None => ("", (0, 0), (0, 0))
    Some(location) =>
      match location.span {
        Some(span) if location.file == MODEL_FILE => {
          let a = source.position(span.start)
          let b = source.position(span.end())
          (location.file, (a.line.0, a.column.0), (b.line.0, b.column.0))
        }
        _ => (location.file, (0, 0), (0, 0))
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
fn validate(seq : Int32, model : String) -> Response {
  let loaded = load(model)
  let source = @syntax.SourceText::new(model)
  let items = loaded
    .validation_events()
    .map(event => diagnostic_of(event, source))
  let shapes = match loaded.model {
    Some(model) => shape_count(model)
    None => 0
  }
  Diagnostics(seq~, items~, shapes~)
}

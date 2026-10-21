///|
pub(all) suberror SuiteError {
  InvalidSuite(String)
} derive(Debug)

///|
pub struct CaseId(String) derive(Eq, Debug)

///|
/// Validate the pinned test trait's case-ID constraint independently of shape IDs.
pub fn CaseId::parse(text : String) -> CaseId? {
  guard text.length() >= 2 else { return None }
  let mut first = true
  for c in text.iter() {
    let alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    let digit = c >= '0' && c <= '9'
    guard alpha || c == '_' || (!first && digit) else { return None }
    first = false
  }
  Some(CaseId(text))
}

///|
pub fn CaseId::to_string(self : CaseId) -> String {
  self.0
}

///|
pub(all) enum Side {
  Client
  Server
} derive(Eq, Debug)

///|
pub(all) enum Subject {
  Request(operation~ : @smithy.ShapeId, input~ : @smithy.ShapeId)
  Response(operation~ : @smithy.ShapeId, output~ : @smithy.ShapeId)
  ErrorResponse(error~ : @smithy.ShapeId)
} derive(Eq, Debug)

///|
pub struct Case {
  id : CaseId
  protocol : @smithy.ShapeId
  subject : Subject
  side : Side?
  definition : @smithy.NodeValue
}

///|
pub fn Case::id(self : Case) -> CaseId {
  self.id
}

///|
pub fn Case::protocol(self : Case) -> @smithy.ShapeId {
  self.protocol
}

///|
pub fn Case::subject(self : Case) -> Subject {
  self.subject
}

///|
pub fn Case::applies_to(self : Case, side : Side) -> Bool {
  self.side is None || self.side == Some(side)
}

///|
fn field(value : @smithy.NodeValue, name : String) -> @smithy.NodeValue? {
  match value {
    Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn text(value : @smithy.NodeValue, name : String) -> String? {
  match field(value, name) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn strings(value : @smithy.NodeValue, name : String) -> Array[String] {
  match field(value, name) {
    Some(Array(entries)) =>
      entries
      .iter()
      .filter_map(v => {
        match v {
          String(s) => Some(s)
          _ => None
        }
      })
      .collect()
    _ => []
  }
}

///|
/// A fresh native-value snapshot, including exact numbers and plain-text blobs.
pub fn Case::params(self : Case) -> @smithy.NodeValue {
  @smithy.NodeValue::from_json(
    field(self.definition, "params").unwrap_or(Object(Map([]))).to_json(),
  ) catch {
    _ => abort("validated params")
  }
}

///|
/// All protocol metadata, including authScheme, vendor params, host, tags and documentation.
/// Returning a fresh snapshot prevents callers from mutating a prepared case.
pub fn Case::definition(self : Case) -> @smithy.NodeValue {
  @smithy.NodeValue::from_json(self.definition.to_json()) catch {
    _ => abort("validated case")
  }
}

///|
pub struct Suite {
  cases : Array[Case]
}

///|
pub fn loader() -> @smithy.Loader {
  @smithy.Loader::new(protocol_tests=true)
}

///|
pub fn Suite::from_model(model : @smithy.Model) -> Suite raise SuiteError {
  // Re-establish the standard trait contract even for manually supplied models.
  // Explicit incompatible smithy.test definitions cannot weaken case validation.
  let checked = loader()
    .add_ast("protocol-suite.json", model.to_json_ast())
    .assemble() catch {
      error => raise InvalidSuite(error.to_string())
    }
  if checked
    .validation_events()
    .iter()
    .any(e => e.severity == "ERROR" || e.severity == "DANGER") {
    raise InvalidSuite(
      "Protocol cases require a model without error or danger validation events.",
    )
  }
  guard checked.model is Some(model) else {
    raise InvalidSuite("Protocol model assembly failed.")
  }
  let cases : Array[Case] = []
  let shapes = model.shapes.keys().to_array()
  shapes.sort_by((a, b) => a.to_string().compare(b.to_string()))
  for id in shapes {
    let owner = model.shapes.get(id).unwrap()
    for name in ["httpRequestTests", "httpResponseTests"] {
      let subject = match (name, owner.body) {
        ("httpRequestTests", Operation(input~, ..)) =>
          Subject::Request(operation=id, input~)
        ("httpResponseTests", Operation(output~, ..)) =>
          Subject::Response(operation=id, output~)
        ("httpResponseTests", Structure(_)) if owner.trait_value(
            "smithy.api#error",
          )
          is Some(_) => ErrorResponse(error=id)
        _ => continue
      }
      guard owner.trait_value("smithy.test#" + name) is Some(Array(entries)) else {
        continue
      }
      for entry in entries {
        guard text(entry, "id").bind(CaseId::parse) is Some(case_id) &&
          text(entry, "protocol").bind(@smithy.ShapeId::parse) is Some(protocol) else {
          raise InvalidSuite(
            "Protocol test case is missing a valid ID or protocol.",
          )
        }
        let side = match text(entry, "appliesTo") {
          Some("client") => Some(Client)
          Some("server") => Some(Server)
          None => None
          _ => raise InvalidSuite("Invalid appliesTo.")
        }
        let definition = @smithy.NodeValue::from_json(entry.to_json()) catch {
          _ => raise InvalidSuite("Invalid case value.")
        }
        cases.push({ id: case_id, protocol, subject, side, definition, })
      }
    }
  }
  { cases, }
}

///|
pub fn Suite::cases(self : Suite) -> Array[Case] {
  self.cases.copy()
}

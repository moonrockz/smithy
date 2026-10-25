///|
/// An error that the code generation core raises.
pub(all) suberror CodegenError {
  InvalidSettings(String)
  MissingService(@smithy.ShapeId)
  NotAService(@smithy.ShapeId)
  InvalidTemplate(String)
  WriterConflict(String)
  MissingDefinition(@smithy.ShapeId)
  DuplicateIntegration(String)
  IntegrationCycle(Array[String])
  StateError(String)
} derive(Debug)

///|
/// The first-person message of an error. It names the construct.
pub fn CodegenError::message(self : CodegenError) -> String {
  match self {
    InvalidSettings(text) => text
    MissingService(id) => "I could not find service shape `\{id}` in the model."
    NotAService(id) => "I expected `\{id}` to be a service shape."
    InvalidTemplate(text) => text
    WriterConflict(text) => text
    MissingDefinition(id) =>
      "I could not write shape `\{id}`: its symbol has no definition file."
    DuplicateIntegration(name) =>
      "I found two integrations with the name `\{name}`."
    IntegrationCycle(names) =>
      "I found a cycle in the order of integrations: \{names.join(", ")}."
    StateError(text) => text
  }
}

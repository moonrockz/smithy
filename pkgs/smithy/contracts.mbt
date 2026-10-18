///|
fn valid_condition_name(name : String) -> Bool {
  let mut first = true
  for c in name.iter() {
    let upper = c >= 'A' && c <= 'Z'
    if first {
      if !upper {
        return false
      }
      first = false
    } else if !upper && !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') {
      return false
    }
  }
  !first
}

///|
/// Check the contract-specific rules that are not covered by schema validation.
fn Assembly::validate_conditions(
  self : Assembly,
  model : Model,
  owner : Shape,
  value : NodeValue,
) -> Unit {
  if owner.body is Service(..) ||
    owner.body is Operation(..) ||
    owner.body is Resource(..) {
    self.problem(
      "SM-MODEL-011",
      "I cannot apply smithy.contracts#conditions to \{owner.body.keyword()} \{owner.id}.",
      owner.source,
      shape=owner.id.to_string(),
    )
    return
  }
  guard value is Object(conditions) else { return }
  for name, condition in conditions {
    if !valid_condition_name(name) {
      self.problem(
        "SM-MODEL-011",
        "I expected a condition name matching ^[A-Z]+[A-Za-z0-9]*$ in smithy.contracts#conditions on \{owner.id}, but found \{Json::string(name).stringify()}.",
        owner.source,
        shape=owner.id.to_string(),
      )
    }
    if condition is Object(fields) &&
      fields.get("expression") is Some(String(expression)) {
      self.analyze_condition(model, owner, name, expression)
    }
  }
}

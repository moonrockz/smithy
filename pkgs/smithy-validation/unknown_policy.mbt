///|
fn prepare_unknown_members(
  shape : @smithy.Shape,
  default_ : UnknownMembers,
) -> UnknownMembers raise PreparationError {
  match shape.trait_value("smithy.rpc#unknownMembers") {
    None => default_
    Some(String("ignore")) if shape.body is Structure(_) => Ignore
    Some(String("reject")) if shape.body is Structure(_) => Reject
    _ =>
      raise InvalidModel(
        shape.id,
        "I expected unknownMembers to be reject or ignore on a structure.",
      )
  }
}

///|
/// Set the default policy. A structure trait overrides this policy.
pub fn Config::with_unknown_members(
  self : Config,
  policy : UnknownMembers,
) -> Config {
  { ..self, unknown_members: policy, }
}

///|
/// Get the config used to prepare this validator.
pub fn PreparedValidator::config(self : PreparedValidator) -> Config {
  self.config
}

///|
/// Get the effective policy for a prepared shape or member target.
pub fn PreparedValidator::unknown_members(
  self : PreparedValidator,
  target : @smithy.ShapeId,
) -> UnknownMembers? {
  self.shapes.get(target).map(shape => shape.unknown_members)
}

///|
fn prepare_critical_paths(
  model : @smithy.Model,
  shape : @smithy.Shape,
  body : @smithy.ShapeBody,
) -> String? raise PreparationError {
  guard shape.trait_value("smithy.rpc#criticalPaths") is Some(value) else {
    return None
  }
  guard shape.body is Member(_) &&
    model.shapes.get(shape.id.root()) is Some(parent) &&
    parent.body is Structure(ids) &&
    ids.contains(shape.id) &&
    body is List(element) &&
    model.shapes.get(element) is Some(element_shape) &&
    element_shape.body is Member(target~) &&
    model.shapes.get(target) is Some(target_shape) &&
    target_shape.body is Simple(String) else {
    raise InvalidModel(
      shape.id,
      "I expected criticalPaths on a structure member with a list-of-string target.",
    )
  }
  guard value is Object(fields) &&
    fields.get("separator") is Some(String(separator)) &&
    !separator.is_empty() else {
    raise InvalidModel(
      shape.id,
      "I expected criticalPaths to have a nonempty string separator.",
    )
  }
  Some(separator)
}

///|
fn PreparedValidator::critical_path_known(
  self : PreparedValidator,
  enclosing : @smithy.ShapeId,
  text : String,
  separator : String,
  budget : Budget,
  path : InstancePath,
) -> Bool {
  let mut current = enclosing
  for part in text.split(separator) {
    if !budget.charge(path, enclosing) {
      return true
    }
    guard !part.is_empty() &&
      self.shapes.get(current) is Some(shape) &&
      shape.body is Structure(_) &&
      shape.by_name.get(part.to_owned()) is Some(member_) else {
      return false
    }
    current = member_.id
  }
  true
}

///|
/// Get the separator for a prepared critical-path list member.
pub fn PreparedValidator::critical_paths(
  self : PreparedValidator,
  target : @smithy.ShapeId,
) -> String? {
  self.shapes.get(target).bind(shape => shape.critical_separator)
}

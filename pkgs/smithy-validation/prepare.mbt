///|
pub(all) suberror PreparationError {
  InvalidTarget(@smithy.ShapeId, String)
  InvalidConfiguration(String)
  InvalidModel(@smithy.ShapeId, String)
  UnsupportedConstraint(@smithy.ShapeId, String)
} derive(Debug)

///|
priv struct PreparedMember {
  name : String
  id : @smithy.ShapeId
  required : Bool
} derive(Debug)

///|
priv struct PreparedShape {
  id : @smithy.ShapeId
  body : @smithy.ShapeBody
  constraints : Constraints
  members : Array[PreparedMember]
  by_name : Map[String, PreparedMember]
  enum_values : Array[@smithy.NodeValue]
  sparse : Bool
} derive(Debug)

///|
/// A private snapshot of the reachable semantic contract, reusable across values.
pub struct PreparedValidator {
  priv target : @smithy.ShapeId
  priv shapes : Map[@smithy.ShapeId, PreparedShape]
  priv config : Config
} derive(Debug)

///|
fn data_shape(shape : @smithy.Shape) -> Bool {
  match shape.body {
    Operation(..) | Service(..) | Resource(..) => false
    _ => shape.trait_value("smithy.api#mixin") is None
  }
}

///|
fn collection_member(
  model : @smithy.Model,
  container : @smithy.ShapeId,
  member_id : @smithy.ShapeId,
  name : String,
) -> Unit raise PreparationError {
  guard container.with_member(name) == Some(member_id) &&
    model.shapes.get(member_id) is Some(member_) &&
    member_.body is Member(_) else {
    raise InvalidModel(
      container, "I expected a declared collection member belonging to its containing shape.",
    )
  }
}

///|
pub fn PreparedValidator::prepare(
  model : @smithy.Model,
  target : @smithy.ShapeId,
  config~ : Config = Config::new(),
) -> PreparedValidator raise PreparationError {
  guard model.shapes.get(target) is Some(root) && data_shape(root) else {
    raise InvalidTarget(
      target, "I expected an existing data shape or data member as the validation target.",
    )
  }
  let shapes : Map[@smithy.ShapeId, PreparedShape] = Map([])
  let stack = [target]
  while stack.pop() is Some(id) {
    if shapes.contains(id) {
      continue
    }
    if shapes.length() >= config.limits.work {
      raise InvalidModel(id, "I reached the preparation work limit.")
    }
    guard model.shapes.get(id) is Some(shape) && data_shape(shape) else {
      raise InvalidModel(
        id, "I expected a reachable data shape, but found a missing or nondata target.",
      )
    }
    let effective = match shape.body {
      Member(target=member_target) => {
        guard member_target.member_name() is None &&
          model.shapes.get(member_target) is Some(resolved) &&
          data_shape(resolved) &&
          !(resolved.body is Member(_)) else {
          raise InvalidModel(
            id, "I expected the member to target an existing data shape.",
          )
        }
        resolved
      }
      _ => shape
    }
    let body = match effective.body {
      Structure(ids) => @smithy.Structure(ids.copy())
      Union(ids) => @smithy.Union(ids.copy())
      Enum(ids) => @smithy.Enum(ids.copy())
      IntEnum(ids) => @smithy.IntEnum(ids.copy())
      other => other
    }
    let members : Array[PreparedMember] = []
    let enum_values : Array[@smithy.NodeValue] = []
    match body {
      Structure(ids) | Union(ids) => {
        let names : Set[String] = Set([])
        for member_id in ids {
          guard member_id.root() == effective.id &&
            member_id.member_name() is Some(name) &&
            model.shapes.get(member_id) is Some(member_shape) &&
            member_shape.body is Member(_) else {
            raise InvalidModel(
              id, "I expected a declared member belonging to its containing shape.",
            )
          }
          let name = if config.member_names == JsonName {
            match member_shape.trait_value("smithy.api#jsonName") {
              None => name
              Some(String(wire)) => wire
              _ =>
                raise InvalidModel(
                  member_id, "I expected a string JSON member name.",
                )
            }
          } else {
            name
          }
          guard !names.contains(name) else {
            raise InvalidModel(
              id, "I found conflicting serialized member names.",
            )
          }
          names.add(name)
          members.push({
            name,
            id: member_id,
            required: annotation(
              member_shape.trait_value("smithy.api#required"),
              member_id,
            ),
          })
          stack.push(member_id)
        }
      }
      List(member_id) => {
        collection_member(model, effective.id, member_id, "member")
        stack.push(member_id)
      }
      Map(key~, value~) => {
        collection_member(model, effective.id, key, "key")
        collection_member(model, effective.id, value, "value")
        stack.push(key)
        stack.push(value)
      }
      Enum(ids) | IntEnum(ids) => {
        guard !ids.is_empty() else {
          raise InvalidModel(
            id, "I expected at least one declared enum member.",
          )
        }
        for member_id in ids {
          guard member_id.root() == effective.id &&
            member_id.member_name() is Some(_) &&
            model.shapes.get(member_id) is Some(member_shape) else {
            raise InvalidModel(id, "I expected a declared enum member.")
          }
          let value = member_shape.trait_value("smithy.api#enumValue")
          match (body, value) {
            (Enum(_), Some(String(value))) =>
              enum_values.push(@smithy.String(value))
            (IntEnum(_), Some(Number(value))) if value.is_integer() =>
              enum_values.push(@smithy.Number(value))
            _ =>
              raise InvalidModel(
                member_id, "I expected a scalar enum value of the declared enum kind.",
              )
          }
        }
      }
      _ => ()
    }
    if effective_trait(shape, effective, "smithy.api#enum") is Some(value) {
      guard body is Simple(String) && value is Array(entries) else {
        raise InvalidModel(id, "I expected string enum entries.")
      }
      for entry in entries {
        guard entry is Object(fields) &&
          fields.get("value") is Some(String(text)) else {
          raise InvalidModel(id, "I expected a string enum entry value.")
        }
        enum_values.push(@smithy.String(text))
      }
    }
    let by_name : Map[String, PreparedMember] = Map([])
    for member_ in members {
      by_name[member_.name] = member_
    }
    shapes[id] = {
      id,
      body,
      members,
      by_name,
      enum_values,
      constraints: prepare_constraints(shape, effective, config),
      sparse: annotation(
        effective_trait(shape, effective, "smithy.api#sparse"),
        id,
      ),
    }
  }
  { target, shapes, config, }
}

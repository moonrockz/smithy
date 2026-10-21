///|
fn enum_values(
  model : @smithy.Model,
  shape : @smithy.Shape,
) -> Array[@smithy.NodeValue]? {
  if shape.trait_value("smithy.api#enum") is Some(Array(values)) {
    return Some(values)
  }
  if shape.body is Enum(ids) {
    let values = []
    for id in ids {
      if model.shapes.get(id) is Some(member_shape) &&
        member_shape.trait_value("smithy.api#enumValue") is Some(value) {
        let definition : Map[String, @smithy.NodeValue] = {
          "value": value,
          "name": String(id.member_name().unwrap()),
        }
        values.push(@smithy.NodeValue::Object(definition))
      }
    }
    return Some(values)
  }
  None
}

///|
fn enum_changes(
  d : Differences,
  change : ShapeChange,
  events : Array[ValidationEvent],
) -> Unit {
  let a = change.old_shape
  let b = change.new_shape
  guard enum_values(d.old_model, a) is Some(old_values) &&
    enum_values(d.new_model, b) is Some(new_values) &&
    old_values != new_values else {
    return
  }
  let mut old_end = old_values.length() - 1
  for index, value in old_values {
    let new_value = new_values
      .iter()
      .find_first(v => field(Some(v), "value") == field(Some(value), "value"))
    let text = string(field(Some(value), "value")).unwrap_or("")
    if new_value == None {
      emit(
        events,
        "ChangedEnumTrait.Removed." + index.to_string(),
        "ERROR",
        b,
        "Enum value " + tick(text) + " was removed",
      )
      old_end = old_end - 1
    } else if field(Some(value), "name") != field(new_value, "name") {
      emit(
        events,
        "ChangedEnumTrait.NameChanged." + index.to_string(),
        "ERROR",
        b,
        "Enum `name` changed from " +
        tick(string(field(Some(value), "name")).unwrap_or("null")) +
        " to " +
        tick(string(field(new_value, "name")).unwrap_or("null")) +
        " for the " +
        tick(text) +
        " value",
      )
    }
  }
  for index, value in new_values {
    if !old_values
      .iter()
      .any(v => field(Some(v), "value") == field(Some(value), "value")) {
      let text = string(field(Some(value), "value")).unwrap_or("")
      if index <= old_end {
        emit(
          events,
          "ChangedEnumTrait.OrderChanged." + index.to_string(),
          "ERROR",
          b,
          "Enum value " +
          tick(text) +
          " was inserted before the end of the list of existing values. This can cause compatibility issues when ordinal values are used for iteration, serialization, etc.",
        )
        old_end = old_end + 1
      } else {
        emit(
          events,
          "ChangedEnumTrait.Appended." + index.to_string(),
          "NOTE",
          b,
          "Enum value " + tick(text) + " was appended",
        )
      }
    }
  }
}

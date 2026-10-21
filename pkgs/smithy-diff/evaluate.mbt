///|
fn evaluate(
  d : Differences,
  context : ComparisonContext,
  include_targets~ : Bool = true,
) -> Array[ValidationEvent] {
  let events = []
  for shape in d.added {
    if shape.id.member_name() == None ||
      d.old_model.shapes.contains(shape.id.root()) {
      let migrated_enum = d.old_model.shapes
        .get(shape.id.root())
        .map(s => has(s, "enum"))
        .unwrap_or(false) &&
        d.new_model.shapes
        .get(shape.id.root())
        .map(s => s.body is Enum(_))
        .unwrap_or(false)
      if !migrated_enum || shape.id.member_name() == None {
        emit(
          events,
          "AddedShape",
          "NOTE",
          shape,
          "Added " + kind(shape) + " " + tick(shape.id.to_string()),
        )
      }
    }
    if has(shape, "trait") {
      emit(
        events,
        "AddedTraitDefinition",
        "NOTE",
        shape,
        "Trait definition " + tick(shape.id.to_string()) + " was added",
      )
    }
  }
  for shape in d.removed {
    if !has(shape, "private") &&
      (
        shape.id.member_name() == None ||
        d.new_model.shapes.contains(shape.id.root())
      ) {
      let scalar = match shape.body {
        Simple(Document) => false
        Simple(String) => !has(shape, "enum")
        Simple(_) => true
        _ => false
      }
      emit(
        events,
        if scalar {
          "RemovedShape.ScalarShape"
        } else {
          "RemovedShape"
        },
        if scalar {
          "WARNING"
        } else {
          "ERROR"
        },
        shape,
        "Removed " + kind(shape) + " " + tick(shape.id.to_string()),
      )
    }
    if has(shape, "trait") {
      emit(
        events,
        "RemovedTraitDefinition",
        "ERROR",
        shape,
        "Trait definition " + tick(shape.id.to_string()) + " was removed",
      )
    }
  }
  for change in d.metadata {
    let (id, severity, message) = match (change.old_value, change.new_value) {
      (None, Some(value)) =>
        (
          "AddedMetadata",
          "NOTE",
          "Metadata key " +
          tick(change.key) +
          " was added with the following value: " +
          pretty(value),
        )
      (Some(value), None) =>
        (
          "RemovedMetadata." + change.key,
          "DANGER",
          "Metadata key " +
          tick(change.key) +
          " was removed with the following value: " +
          pretty(value),
        )
      (Some(a), Some(b)) =>
        (
          "ChangedMetadata",
          "WARNING",
          "Metadata key " +
          tick(change.key) +
          " was changed from " +
          pretty(a) +
          " to " +
          pretty(b),
        )
      _ => continue
    }
    events.push({
      id,
      severity,
      message,
      shape: None,
      source: None,
      suppression_reason: None,
    })
  }
  for change in d.changed {
    let a = change.old_shape
    let b = change.new_shape
    if kind(a) != kind(b) &&
      !(a.is_legacy_set() && b.body is List(_) && has(b, "uniqueItems")) &&
      !(has(a, "enum") && b.body is Enum(_)) {
      emit(
        events,
        "ChangedShapeType",
        "ERROR",
        b,
        "Shape " +
        tick(b.id.to_string()) +
        " type was changed from " +
        tick(kind(a)) +
        " to " +
        tick(kind(b)) +
        ".",
      )
    }
    match (a.body, b.body) {
      (
        Operation(input=old_input, output=old_output, errors=old_errors),
        Operation(input=new_input, output=new_output, errors=new_errors),
      ) => {
        for
          (label, old_id, new_id) in [
            ("Input", old_input, new_input),
            ("Output", old_output, new_output),
          ] {
          if old_id != new_id {
            emit(
              events,
              "ChangedOperation" +
              label +
              ".From." +
              old_id.to_string() +
              ".To." +
              new_id.to_string(),
              "ERROR",
              b,
              "Changed operation " +
              label.to_lower() +
              " of " +
              tick(b.id.to_string()) +
              " from " +
              tick(old_id.to_string()) +
              " to " +
              tick(new_id.to_string()),
            )
          }
        }
        error_changes(events, b, old_errors, new_errors, false)
      }
      (
        Service(errors=old_errors, rename=old_rename, ..),
        Service(errors=new_errors, rename=new_rename, ..),
      ) => {
        error_changes(events, b, old_errors, new_errors, true)
        let old_closure = closure(d.old_model, a.id)
        for id, name in old_rename {
          match new_rename.get(id) {
            None =>
              emit(
                events,
                "ServiceRename",
                "ERROR",
                b,
                "Service rename of " +
                tick(id.to_string()) +
                " to " +
                tick(name) +
                " was removed",
              )
            Some(new_name) =>
              if name != new_name {
                emit(
                  events,
                  "ServiceRename",
                  "ERROR",
                  b,
                  "Service rename of " +
                  tick(id.to_string()) +
                  " was changed from " +
                  tick(name) +
                  " to " +
                  tick(new_name),
                )
              }
          }
        }
        for id, name in new_rename {
          if !old_rename.contains(id) && old_closure.contains(id) {
            emit(
              events,
              "ServiceRename",
              "ERROR",
              b,
              "Service rename of " +
              tick(id.to_string()) +
              " to " +
              tick(name) +
              " was added to an old shape",
            )
          }
        }
      }
      (Resource(identifiers=old_ids, ..), Resource(identifiers=new_ids, ..)) =>
        if old_ids != new_ids {
          emit(
            events,
            "ChangedResourceIdentifiers",
            "ERROR",
            b,
            "Identifiers of resource " +
            tick(b.id.to_string()) +
            " changed from " +
            identifier_map(old_ids) +
            " to " +
            identifier_map(new_ids) +
            ".",
          )
        }
      (Structure(old_ids), Structure(new_ids)) => {
        for id in new_ids {
          if !old_ids.contains(id) &&
            d.new_model.shapes.get(id) is Some(member_shape) &&
            has(member_shape, "required") &&
            !has(member_shape, "default") &&
            !has(member_shape, "clientOptional") {
            emit(
              events, "AddedRequiredMember", "ERROR", member_shape, "Adding a new member with the `required` trait but not the `default` trait or the `clientOptional` trait is backwards-incompatible.",
            )
          }
        }
        member_order(events, b, old_ids, new_ids)
      }
      (Union(old_ids), Union(new_ids)) =>
        member_order(events, b, old_ids, new_ids)
      _ => ()
    }
    entity_bindings(d, change, events)
    constraint_changes(change, events)
    default_changes(d, change, events)
    enum_changes(d, change, events)
    trait_changes(d, change, events)
  }
  nullability_changes(d, events)
  if include_targets {
    member_target_changes(d, events, context)
  }
  events
}

///|
fn member_order(
  events : Array[ValidationEvent],
  shape : @smithy.Shape,
  old_ids : Array[@smithy.ShapeId],
  new_ids : Array[@smithy.ShapeId],
) -> Unit {
  let mut reordered = false
  for i = 0; i < old_ids.length() && i < new_ids.length(); i = i + 1 {
    reordered = reordered ||
      old_ids[i].member_name() != new_ids[i].member_name()
  }
  if reordered {
    emit(
      events,
      "ChangedMemberOrder",
      "DANGER",
      shape,
      kind(shape) +
      " shape members were reordered. This can cause ABI compatibility issues in languages like C and C++ where the layout and alignment of a data structure matters.",
    )
  }
}

///|
fn error_changes(
  events : Array[ValidationEvent],
  shape : @smithy.Shape,
  old_ids : Array[@smithy.ShapeId],
  new_ids : Array[@smithy.ShapeId],
  service : Bool,
) -> Unit {
  let category = if service { "Service" } else { "Operation" }
  let noun = category.to_lower()
  for id in old_ids {
    if !new_ids.contains(id) {
      emit(
        events,
        "Removed" +
        category +
        "Error" +
        (if service { "" } else { "." + id.name() }),
        "WARNING",
        shape,
        "The " +
        tick(id.to_string()) +
        " error was removed from the " +
        tick(shape.id.to_string()) +
        " " +
        noun +
        "." +
        (if service {
          " This means that it is no longer considered an error common to all operations within the service."
        } else {
          ""
        }),
      )
    }
  }
  for id in new_ids {
    if !old_ids.contains(id) {
      emit(
        events,
        "Added" +
        category +
        "Error" +
        (if service { "" } else { "." + id.name() }),
        "WARNING",
        shape,
        "The " +
        tick(id.to_string()) +
        " error was added to the " +
        tick(shape.id.to_string()) +
        " " +
        noun +
        (if service {
          ", making this error common to all operations within the service."
        } else {
          "."
        }) +
        " This is backward-compatible if the error is only encountered as a result of a change in behavior of the client (for example, the client sends a new parameter to an operation).",
      )
    }
  }
}

///|
fn identifier_map(ids : Map[String, @smithy.ShapeId]) -> String {
  "{" +
  ids.to_array().map(pair => pair.0 + "=" + pair.1.to_string()).join(", ") +
  "}"
}

///|
fn constraint_changes(
  change : ShapeChange,
  events : Array[ValidationEvent],
) -> Unit {
  for
    (name, event_id) in [
      ("length", "ChangedLengthTrait"),
      ("range", "ChangedRangeTrait"),
    ] {
    let a = change.old_shape.trait_value("smithy.api#" + name)
    let b = change.new_shape.trait_value("smithy.api#" + name)
    if a == None || b == None || a == b {
      continue
    }
    let zero = @smithy.NodeValue::Number(
      @smithy.NodeNumber::parse("0").unwrap(),
    )
    let old_min = field(a, "min").unwrap_or(zero)
    let new_min = field(b, "min").unwrap_or(zero)
    if old_min is Number(old_number) &&
      new_min is Number(new_number) &&
      new_number.numeric_compare(old_number) > 0 {
      emit(
        events,
        event_id,
        "ERROR",
        change.new_shape,
        "smithy.api#" +
        name +
        " trait value `min` was made more restrictive by raising from " +
        json(old_min) +
        " to " +
        json(new_min),
      )
    }
    if field(b, "max") is Some(Number(new_number)) {
      let old_max = field(a, "max")
      let restricted = match old_max {
        Some(Number(old_number)) => old_number.numeric_compare(new_number) > 0
        None => true
        _ => false
      }
      if restricted {
        emit(
          events,
          event_id,
          "ERROR",
          change.new_shape,
          "smithy.api#" +
          name +
          " trait value `max` was made more restrictive by lowering from " +
          old_max.map(json).unwrap_or("null") +
          " to " +
          new_number.to_json().stringify(),
        )
      }
    }
  }
}

///|
fn pretty(value : @smithy.NodeValue) -> String {
  value.to_json().stringify(indent=4)
}

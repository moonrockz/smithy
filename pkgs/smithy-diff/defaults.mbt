///|
fn zero_default(value : @smithy.NodeValue, target : @smithy.Shape?) -> Bool {
  guard target is Some(target) else { return false }
  match (target.body, value) {
    (Simple(Boolean), Boolean(false)) => true
    (
      Simple(Byte | Short | Integer | Long | Float | Double)
      | IntEnum(_),
      Number(n),
    ) => n == @smithy.NodeNumber::parse("0").unwrap()
    _ => false
  }
}

///|
fn target(model : @smithy.Model, shape : @smithy.Shape) -> @smithy.Shape? {
  match shape.body {
    Member(target~) => model.shapes.get(target)
    _ => None
  }
}

///|
fn default_changes(
  d : Differences,
  change : ShapeChange,
  events : Array[ValidationEvent],
) -> Unit {
  let a = change.old_shape
  let b = change.new_shape
  let old_value = a.trait_value("smithy.api#default")
  let new_value = b.trait_value("smithy.api#default")
  if old_value == new_value {
    return
  }
  let member_shape = b.body is Member(..)
  match (old_value, new_value) {
    (Some(old_value), None) => {
      let target_default = target(d.new_model, b).bind(s => {
        s.trait_value("smithy.api#default")
      })
      if member_shape &&
        old_value == Null &&
        (target_default == None || target_default == Some(Null)) {
        return
      }
      emit(
        events, "ChangedDefault", "ERROR", b, "@default trait was removed. This will break previously generated code.",
      )
    }
    (None, Some(value)) =>
      if !member_shape {
        emit(
          events,
          "ChangedDefault",
          "ERROR",
          b,
          "Adding the @default trait to a root-level shape will break previously generated code. Added @default: " +
          json(value),
        )
      } else if !has(b, "addedDefault") && value != Null {
        emit(
          events,
          "ChangedDefault",
          "ERROR",
          b,
          "Adding the @default trait to a member without also adding the @addedDefault trait will break previously generated code. Added @default: " +
          json(value),
        )
      }
    (Some(old_value), Some(new_value)) =>
      if !member_shape {
        emit(
          events,
          "ChangedDefault",
          "ERROR",
          b,
          "Changing the @default value of a root-level shape will break previously generated code. Old value: " +
          json(old_value) +
          ". New value: " +
          json(new_value),
        )
      } else {
        let old_zero = zero_default(old_value, target(d.old_model, a))
        let new_zero = zero_default(new_value, target(d.new_model, b))
        if old_zero == new_zero {
          emit(
            events,
            "ChangedDefault",
            "DANGER",
            b,
            "Changing the @default value of a member is dangerous and could break previously generated code or lead to subtle errors. Do this only when strictly necessary. Old value: " +
            json(old_value) +
            ". New value: " +
            json(new_value),
          )
        } else {
          emit(
            events,
            "ChangedDefault",
            "ERROR",
            b,
            "The @default trait of this member changed from " +
            (if old_zero {
              "the zero value of the target shape, "
            } else {
              "something other than the zero value of the target shape, "
            }) +
            tick(json(old_value)) +
            ", to " +
            (if new_zero {
              "the zero value, "
            } else {
              "a value that is not the zero value, "
            }) +
            tick(json(new_value)) +
            ". This will break previously generated code.",
          )
        }
      }
    _ => ()
  }
}

///|
fn nullable(model : @smithy.Model, member_shape : @smithy.Shape) -> Bool {
  guard model.shapes.get(member_shape.id.root()) is Some(container) else {
    return false
  }
  match container.body {
    Structure(_) =>
      has(member_shape, "clientOptional") ||
      has(container, "input") ||
      (
        !has(member_shape, "required") &&
        (
          member_shape.trait_value("smithy.api#default") == None ||
          member_shape.trait_value("smithy.api#default") == Some(Null)
        )
      )
    List(_) => !container.is_legacy_set() && has(container, "sparse")
    Map(..) =>
      member_shape.id.member_name() != Some("key") && has(container, "sparse")
    _ => false
  }
}

///|
fn nullability_changes(
  d : Differences,
  events : Array[ValidationEvent],
) -> Unit {
  let candidates : Map[@smithy.ShapeId, ShapeChange] = Map([])
  for change in d.changed {
    if change.old_shape.body is Member(..) &&
      change.new_shape.body is Member(..) {
      candidates[change.new_shape.id] = change
    }
    if change.old_shape.body is Structure(_) &&
      change.new_shape.body is Structure(ids) &&
      has(change.old_shape, "input") != has(change.new_shape, "input") {
      for id in ids {
        if d.old_model.shapes.get(id) is Some(a) &&
          d.new_model.shapes.get(id) is Some(b) {
          candidates[id] = shape_change(a, b)
        }
      }
    }
  }
  for _, change in candidates {
    let a = change.old_shape
    let b = change.new_shape
    let was_nullable = nullable(d.old_model, a)
    if was_nullable == nullable(d.new_model, b) {
      continue
    }
    let prefix = "Member " +
      tick(b.id.member_name().unwrap()) +
      " changed from " +
      (if was_nullable {
        "nullable to non-nullable"
      } else {
        "non-nullable to nullable"
      })
    let old_input = d.old_model.shapes
      .get(a.id.root())
      .map(s => has(s, "input"))
      .unwrap_or(false)
    let new_input = d.new_model.shapes
      .get(b.id.root())
      .map(s => has(s, "input"))
      .unwrap_or(false)
    let initial = events.length()
    let add = fn(suffix : String, severity : String, message : String) {
      emit(
        events,
        "ChangedNullability." + suffix,
        severity,
        a,
        prefix + ": " + message,
      )
    }
    if old_input && !new_input {
      add(
        "RemovedInputTrait",
        "ERROR",
        "The `@input` trait was removed from " + b.id.root().to_string(),
      )
    } else if !old_input && new_input {
      add(
        "AddedInputTrait",
        "DANGER",
        "The `@input` trait was added to " + b.id.root().to_string(),
      )
    } else if !old_input && !new_input {
      if !has(a, "clientOptional") &&
        has(b, "clientOptional") &&
        has(a, "required") &&
        has(b, "required") {
        add(
          "AddedClientOptionalTrait", "ERROR", "The `@clientOptional` trait was added to a `@required` member.",
        )
      } else if has(a, "clientOptional") &&
        !has(b, "clientOptional") &&
        has(a, "required") &&
        has(b, "required") {
        add(
          "RemovedClientOptionalTrait", "ERROR", "The `@clientOptional` trait was removed from a `@required` member.",
        )
      } else if !has(a, "required") &&
        has(b, "required") &&
        !has(b, "clientOptional") {
        let target = target(d.new_model, b)
        if target is Some({ body: Structure(_) | Union(_), .. }) {
          add(
            "AddedRequiredTrait.StructureOrUnion",
            "WARNING",
            "The `@required` trait was added to a member that targets a " +
            target.map(kind).unwrap() +
            ". This is backward compatible in generators that always treat structures and unions as optional (e.g., AWS generators)",
          )
        } else {
          add(
            "AddedRequiredTrait", "ERROR", "The `@required` trait was added to a member.",
          )
        }
      }
      if !has(a, "default") &&
        has(b, "default") &&
        !(has(a, "required") && !has(b, "required")) {
        add(
          "AddedDefaultTrait", "ERROR", "The `@default` trait was added to a member that was not previously `@required`.",
        )
      }
      if has(a, "required") &&
        !has(b, "required") &&
        !has(b, "default") &&
        !has(a, "clientOptional") {
        let target = target(d.new_model, b)
        if target is Some({ body: Structure(_) | Union(_), .. }) {
          add(
            "RemovedRequiredTrait.StructureOrUnion",
            "WARNING",
            "The @required trait was removed from a member that targets a " +
            target.map(kind).unwrap() +
            ". This is backward compatible in generators that always treat structures and unions as optional (e.g., AWS generators)",
          )
        } else {
          add(
            "RemovedRequiredTrait", "ERROR", "The @required trait was removed and not replaced with the @default trait and @addedDefault trait.",
          )
        }
      }
    }
    match
      (a.trait_value("smithy.api#default"), b.trait_value("smithy.api#default")) {
      (Some(old_value), Some(new_value)) =>
        if old_value != Null && new_value == Null {
          add(
            "AddedNullDefault",
            "ERROR",
            "The `@default` trait was changed from " +
            tick(json(old_value)) +
            " to `null`.",
          )
        } else if old_value == Null && new_value != Null {
          add(
            "RemovedNullDefault",
            "ERROR",
            "The `@default` trait was changed from `null` to " +
            tick(json(new_value)) +
            ".",
          )
        }
      _ => ()
    }
    if events.length() == initial {
      emit(events, "ChangedNullability", "ERROR", a, prefix)
    }
  }
}

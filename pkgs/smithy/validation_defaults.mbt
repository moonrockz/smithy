///|
fn Model::default_trait_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let id_refs = IdRefSelections::new(self)
  let updates : Set[ShapeId] = Set([])
  for _, shape in self.shapes {
    if shape.body is Resource(update~, ..) && update is Some(id) {
      updates.add(id)
    }
  }
  for _, shape in self.shapes {
    if shape.body is Operation(input=input_id, ..) &&
      (
        shape.id.name.to_lower().has_prefix("update") ||
        shape.id.name.to_lower().has_prefix("patch") ||
        updates.contains(shape.id)
      ) &&
      self.shapes.get(input_id) is Some({ body: Structure(members), .. }) {
      let defaults = members.filter(id => {
        self.shapes.get(id).bind(s => s.trait_value("smithy.api#default"))
        is Some(_)
      })
      if !defaults.is_empty() {
        events.push(
          validation_event(
            "DefaultValueInUpdate",
            "WARNING",
            Some(shape),
            "This update style operation has top-level input members marked with the @default trait: " +
            defaults.map(id => id.member.unwrap_or("")).join(", "),
          ),
        )
      }
    }
    if shape.body is Union(members) {
      for id in members {
        guard self.shapes.get(id) is Some(member_) &&
          member_.body is Member(target~) &&
          self.shapes.get(target) is Some(target_shape) else {
          continue
        }
        if target_shape.trait_value("smithy.api#default") is Some(_) {
          events.push(
            validation_event(
              "Union",
              "NOTE",
              Some(member_),
              "This union member targets `" +
              target.to_string() +
              "`, a shape with a default value. Default values are ignored in tagged unions.",
            ),
          )
        }
        if member_.trait_value("smithy.api#box") is Some(_) {
          events.push(
            validation_event(
              "Union",
              "WARNING",
              Some(member_),
              "Invalid box trait found on a union member. The box trait on union members has no effect because union members are implicitly nullable.",
            ),
          )
        }
      }
    }
    guard shape.trait_value("smithy.api#default") is Some(value) else {
      continue
    }
    let target = match shape.body {
      Member(target~) => self.shapes.get(target).unwrap_or(shape)
      _ => shape
    }
    if value is Null {
      if !(shape.body is Member(..)) {
        events.push(
          validation_event(
            "DefaultTrait",
            "ERROR",
            Some(shape),
            "The @default trait can be set to null only on members",
          ),
        )
      }
    } else {
      events.append(
        self.node_validation_events(
          value,
          shape.id,
          Some(shape),
          "DefaultTrait",
          "ERROR",
          id_refs~,
        ),
      )
      match (target.body, value) {
        (Simple(Blob), String(text)) => {
          let valid = try {
            ignore(@base64.decode(text))
            true
          } catch {
            _ => false
          }
          if !valid {
            events.push(
              validation_event(
                "DefaultTrait",
                "WARNING",
                Some(shape),
                "The @default value of a blob should be a valid base64 string.",
              ),
            )
          }
        }
        (Map(..), Object(values)) | (Simple(Document), Object(values)) =>
          if !values.is_empty() {
            events.push(
              validation_event(
                "DefaultTrait",
                "ERROR",
                Some(shape),
                "The @default object must be empty.",
              ),
            )
          }
        (List(_), Array(values)) | (Simple(Document), Array(values)) =>
          if !values.is_empty() {
            events.push(
              validation_event(
                "DefaultTrait",
                "ERROR",
                Some(shape),
                "The @default array must be empty.",
              ),
            )
          }
        _ => ()
      }
    }
    if shape.id.member is None {
      for _, member_ in self.shapes {
        guard member_.body is Member(target~) &&
          target == shape.id &&
          self.shapes.get(member_.id.root()) is Some({ body: Structure(_), .. }) else {
          continue
        }
        let member_default = member_.trait_value("smithy.api#default")
        if member_default != Some(Null) && member_default != Some(value) {
          events.push(
            validation_event(
              "DefaultTrait",
              "ERROR",
              Some(member_),
              "Member targets `" +
              shape.id.to_string() +
              "`, which requires that the member defines the same default or null.",
            ),
          )
        }
      }
    }
  }
  events
}

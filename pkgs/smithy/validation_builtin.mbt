///|
fn Model::basic_trait_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    if shape.source.is_builtin() {
      continue
    }
    if shape.body is Member(target~) &&
      shape.trait_value("smithy.api#xmlFlattened") is Some(_) &&
      shape.trait_value("smithy.api#xmlName") is None &&
      self.shapes.get(target) is Some({ body: List(item), .. }) &&
      self.shapes.get(item) is Some(item_shape) &&
      item_shape.trait_value("smithy.api#xmlName") is Some(String(xml_name)) &&
      shape.id.member != Some(xml_name) {
      events.push(
        validation_event(
          "XmlFlattenedTrait",
          "WARNING",
          Some(shape),
          "The flattened list member uses a different name from the list item xmlName; apply xmlName explicitly.",
        ),
      )
    }
    if shape.trait_value("smithy.api#pattern") is Some(String(pattern)) {
      let missing : Array[String] = []
      if !pattern.has_prefix("^") {
        missing.push("leading '^'")
      }
      if !pattern.has_suffix("$") {
        missing.push("trailing '$'")
      }
      if !missing.is_empty() {
        events.push(
          validation_event(
            "PatternTrait",
            "WARNING",
            Some(shape),
            "A pattern trait is applied without a " +
            missing.join(" and ") +
            ", meaning only part of the string must match the regular expression. Explicitly anchoring regular expressions is preferable because it is more restrictive by default and does not require modelers to understand that Smithy patterns are not automatically anchored.",
          ),
        )
      }
    }
    if shape.body is Service(..) &&
      shape.trait_value("smithy.api#cors") is Some(cors) &&
      validation_field(cors, "origin") is Some(_) &&
      validation_field(cors, "origins") is Some(Object(origins)) &&
      !origins.is_empty() {
      events.push(
        validation_event(
          "CorsTrait",
          "ERROR",
          Some(shape),
          "The `origin` and `origins` members of the `cors` trait are mutually exclusive.",
        ),
      )
    }
    if shape.body is Member(target~) &&
      self.shapes.get(shape.id.root()) is Some(container) {
      if target.to_string() == "smithy.api#Unit" &&
        !["union", "enum", "intEnum"].contains(container.body.keyword()) {
        events.push(
          validation_event(
            "UnitType",
            "ERROR",
            Some(shape),
            "Only members of a union, enum, or intEnum can reference smithy.api#Unit",
          ),
        )
      }
      if shape.trait_value("smithy.api#private") is Some(_) &&
        is_mixin(container) {
        events.push(
          validation_event(
            "PrivateMixinMember",
            "WARNING",
            Some(shape),
            "The `@private` trait does not prevent a mixin member from being inherited by shapes in other namespaces, nor does it prevent new traits from being added to the inherited member. Apply `@private` to the mixin shape or target shape instead if cross-namespace access should be restricted.",
          ),
        )
      }
    }
  }
  for edge in selector_edges(self) {
    guard ["", "input", "output", "error", "mixin"].contains(edge.label) &&
      self.shapes.get(edge.from) is Some(shape) &&
      self.shapes.get(edge.to) is Some(target) &&
      !shape.source.is_builtin() &&
      target.trait_value("smithy.api#deprecated") is Some(config) else {
      continue
    }
    let since = validation_string(config, "since")
      .map(value => " since " + value)
      .unwrap_or("")
    let message = validation_string(config, "message")
      .map(value => ": " + value)
      .unwrap_or("")
    events.push(
      validation_event(
        "DeprecatedShape." + target.id.to_string(),
        "WARNING",
        Some(shape),
        "References deprecated shape `" +
        target.id.to_string() +
        "`" +
        since +
        message,
      ),
    )
  }
  events
}

///|
fn Model::constraint_trait_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let zero = NodeNumber::parse("0").unwrap()
  for _, shape in self.shapes {
    if shape.source.is_builtin() {
      continue
    }
    if shape.trait_value("smithy.api#range") is Some(config) {
      for key in ["min", "max"] {
        guard validation_field(config, key) is Some(Number(value)) else {
          continue
        }
        if value.is_integer() {
          continue
        }
        let target = match shape.body {
          Member(target~) => self.shapes.get(target).unwrap_or(shape)
          _ => shape
        }
        if !["float", "double", "bigDecimal"].contains(target.body.keyword()) {
          let message = if shape.body is Member(..) {
            "Member `" +
            shape.id.to_string() +
            "` is marked with the `range` trait, but its `" +
            key +
            "` property is a decimal (" +
            @json.to_json(value).stringify() +
            ") when its target (`" +
            target.id.to_string() +
            "`) does not support decimals."
          } else {
            "Shape `" +
            shape.id.to_string() +
            "` is marked with the `range` trait, but its `" +
            key +
            "` property is a decimal (" +
            @json.to_json(value).stringify() +
            ") when its shape (`" +
            shape.body.keyword() +
            "`) does not support decimals."
          }
          events.push(
            validation_event("RangeTrait", "ERROR", Some(shape), message),
          )
        }
      }
      if validation_field(config, "min") is Some(Number(min)) &&
        validation_field(config, "max") is Some(Number(max)) &&
        min.numeric_compare(max) > 0 {
        events.push(
          validation_event(
            "RangeTrait",
            "ERROR",
            Some(shape),
            "A range trait is applied with a `min` value greater than its `max` value.",
          ),
        )
      }
    }
    if shape.trait_value("smithy.api#length") is Some(config) {
      for key in ["min", "max"] {
        if validation_field(config, key) is Some(Number(value)) &&
          value.numeric_compare(zero) < 0 {
          events.push(
            validation_event(
              "LengthTrait",
              "ERROR",
              Some(shape),
              "A length trait is applied with a negative `" + key + "` value.",
            ),
          )
        }
      }
      if validation_field(config, "min") is Some(Number(min)) &&
        validation_field(config, "max") is Some(Number(max)) &&
        min.numeric_compare(max) > 0 {
        events.push(
          validation_event(
            "LengthTrait",
            "ERROR",
            Some(shape),
            "A length trait is applied with a `min` value greater than its `max` value.",
          ),
        )
      }
    }
  }
  events
}

///|
fn validation_trait_name(id : ShapeId) -> String {
  if id.namespace == "smithy.api" {
    id.name
  } else {
    id.to_string()
  }
}

///|
fn Model::trait_conflict_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    if shape.source.is_builtin() {
      continue
    }
    let conflicts : Array[String] = []
    for trait_id, _ in shape.traits {
      guard self.shapes.get(trait_id) is Some(definition) &&
        definition.trait_value("smithy.api#trait") is Some(config) else {
        continue
      }
      for conflict in validation_array(validation_field(config, "conflicts")) {
        guard conflict is String(name) else { continue }
        let id = if name.contains("#") {
          name
        } else {
          trait_id.namespace + "#" + name
        }
        if shape.trait_value(id) is Some(_) &&
          ShapeId::parse(id) is Some(conflict_id) {
          conflicts.push(
            "`" +
            validation_trait_name(trait_id) +
            "` conflicts with `" +
            validation_trait_name(conflict_id) +
            "`",
          )
        }
      }
    }
    if !conflicts.is_empty() {
      conflicts.sort()
      events.push(
        validation_event(
          "TraitConflict",
          "ERROR",
          Some(shape),
          "Found conflicting traits on " +
          shape.body.keyword() +
          " shape: " +
          conflicts.join(", "),
        ),
      )
    }
  }
  events
}

///|
fn Model::exclusive_trait_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for trait_id, definition in self.shapes {
    guard definition.trait_value("smithy.api#trait") is Some(config) &&
      validation_string(config, "structurallyExclusive") is Some(exclusive) else {
      continue
    }
    for _, shape in self.shapes {
      guard !shape.source.is_builtin() && shape.body is Structure(members) else {
        continue
      }
      let matches : Array[String] = []
      for member_id in members {
        guard self.shapes.get(member_id) is Some(member_) else { continue }
        let matches_trait = if exclusive == "member" {
          member_.traits.get(trait_id) is Some(_)
        } else if exclusive == "target" &&
          member_.body is Member(target~) &&
          self.shapes.get(target) is Some(target_shape) {
          target_shape.traits.get(trait_id) is Some(_)
        } else {
          false
        }
        if matches_trait && member_id.member is Some(name) {
          matches.push("`" + name + "`")
        }
      }
      if matches.length() > 1 {
        matches.sort()
        let message = if exclusive == "member" {
          "The `" +
          validation_trait_name(trait_id) +
          "` trait can be applied to only a single member of a shape, but it was found on the following members: "
        } else {
          "Only a single member of a structure can target a shape marked with the `" +
          validation_trait_name(trait_id) +
          "` trait, but it was found on the following members: "
        }
        events.push(
          validation_event(
            "ExclusiveStructureMemberTrait",
            "ERROR",
            Some(shape),
            message + matches.join(", "),
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::json_name_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    guard !shape.source.is_builtin() &&
      shape.body is (Structure(members) | Union(members)) else {
      continue
    }
    let names : Map[String, Array[String]] = Map([])
    for member_id in members {
      guard self.shapes.get(member_id) is Some(member_) &&
        member_id.member is Some(name) else {
        continue
      }
      let json_name = match member_.trait_value("smithy.api#jsonName") {
        Some(String(value)) => value
        _ => name
      }
      let group = names.get(json_name).unwrap_or([])
      group.push(name)
      names[json_name] = group
    }
    for name, members in names {
      if members.length() > 1 {
        members.sort()
        events.push(
          validation_event(
            "JsonName",
            "ERROR",
            Some(shape),
            "This shape contains members with conflicting JSON names that resolve to '" +
            name +
            "': " +
            members.join(", "),
          ),
        )
      }
    }
  }
  events
}

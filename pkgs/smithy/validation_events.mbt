///|
/// A Smithy validation finding after configured severity and suppression rules.
pub(all) struct ValidationEvent {
  id : String
  severity : String
  shape : ShapeId?
  message : String
  source : SourceLocation?
  suppression_reason : String?
} derive(Eq, Debug)

///|
/// Event IDs form a dot-delimited hierarchy.
pub fn suppression_matches(rule_id : String, event_id : String) -> Bool {
  event_id == rule_id || event_id.has_prefix(rule_id + ".")
}

///|
fn validation_field(value : NodeValue, name : String) -> NodeValue? {
  match value {
    Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn validation_string(value : NodeValue, name : String) -> String? {
  match validation_field(value, name) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn validation_array(value : NodeValue?) -> Array[NodeValue] {
  match value {
    Some(Array(values)) => values
    _ => []
  }
}

///|
fn validation_event(
  id : String,
  severity : String,
  shape : Shape?,
  message : String,
) -> ValidationEvent {
  {
    id,
    severity,
    shape: shape.map(s => s.id),
    message,
    source: shape.map(s => s.source),
    suppression_reason: None,
  }
}

///|
fn validation_namespace_matches(rule : String, event : ValidationEvent) -> Bool {
  rule == "*" ||
  (match event.shape {
    Some(shape) => shape.namespace == rule
    None => false
  })
}

///|
fn validation_severity_rank(severity : String) -> Int32 {
  match severity {
    "WARNING" => 2
    "DANGER" => 3
    "ERROR" => 4
    _ => 1
  }
}

///|
fn Model::decorate_validation_event(
  self : Model,
  event : ValidationEvent,
) -> ValidationEvent {
  if event.severity == "ERROR" || event.severity == "SUPPRESSED" {
    return event
  }
  if event.shape is Some(id) &&
    self.shapes.get(id) is Some(shape) &&
    shape.trait_value("smithy.api#suppress") is Some(Array(rules)) {
    for rule in rules {
      if rule is String(rule_id) && suppression_matches(rule_id, event.id) {
        return { ..event, severity: "SUPPRESSED", }
      }
    }
  }
  for rule in validation_array(self.metadata.get("suppressions")) {
    if validation_string(rule, "id") is Some(rule_id) &&
      validation_string(rule, "namespace") is Some(namespace) &&
      suppression_matches(rule_id, event.id) &&
      validation_namespace_matches(namespace, event) {
      return {
        ..event,
        severity: "SUPPRESSED",
        suppression_reason: validation_string(rule, "reason"),
      }
    }
  }
  let mut severity = event.severity
  for rule in validation_array(self.metadata.get("severityOverrides")) {
    if validation_string(rule, "id") is Some(rule_id) &&
      validation_string(rule, "namespace") is Some(namespace) &&
      validation_string(rule, "severity") is Some(override) &&
      suppression_matches(rule_id, event.id) &&
      validation_namespace_matches(namespace, event) &&
      (override == "WARNING" || override == "DANGER") &&
      validation_severity_rank(override) > validation_severity_rank(severity) {
      severity = override
    }
  }
  { ..event, severity, }
}

///|
fn Model::configured_validation_events(
  self : Model,
  definition : NodeValue,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  guard validation_string(definition, "name") is Some(name) else {
    return events
  }
  let id = validation_string(definition, "id").unwrap_or(name)
  let configuration = validation_field(definition, "configuration").unwrap_or(
    Object(Map([])),
  )
  let selector_text = validation_string(configuration, "selector")
  if name == "UnreferencedShape" {
    let expression = validation_string(configuration, "rootShapeSelector").unwrap_or(
      "service",
    )
    let selector = Selector::parse(expression) catch { _ => return events }
    let reachable : Map[String, Bool] = Map([])
    let pending = selector.select_ids(self)
    for shape_id, shape in self.shapes {
      if shape.trait_value("smithy.api#trait") is Some(_) ||
        shape.trait_value("smithy.api#metadata") is Some(_) {
        pending.push(shape_id.to_string())
      }
    }
    let edges = selector_edges(self)
    while !pending.is_empty() {
      let current = pending.pop().unwrap()
      if reachable.contains(current) {
        continue
      }
      reachable[current] = true
      for edge in edges {
        if edge.from.to_string() == current {
          pending.push(edge.to.to_string())
        }
      }
    }
    for shape_id, shape in self.shapes {
      if shape.source.file != "<contracts>" &&
        !shape_id.to_string().has_prefix("smithy.api#") &&
        !(shape.body is Member(..)) &&
        !reachable.contains(shape_id.to_string()) {
        events.push(
          validation_event(
            name,
            "NOTE",
            Some(shape),
            "This shape is unreferenced. It has no modeled connections to shapes that match the following selector: `" +
            expression +
            "`",
          ),
        )
      }
    }
  } else if name == "EmitEachSelector" || name == "EmitNoneSelector" {
    guard selector_text is Some(expression) else { return events }
    let selector = Selector::parse(expression) catch { _ => return events }
    let mut matches = selector.select_ids(self)
    // The reference ignores prelude matches when deciding whether EmitNone fires.
    if name == "EmitNoneSelector" {
      matches = matches.filter(shape_id => !shape_id.has_prefix("smithy.api#"))
      if matches.is_empty() {
        events.push(
          validation_event(
            name,
            "DANGER",
            None,
            "Expected at least one shape to match selector: " + expression,
          ),
        )
      }
    } else {
      let bound = validation_string(configuration, "bindToTrait")
      for shape_id in matches {
        guard self.get(shape_id) is Some(shape) else { continue }
        if bound is Some(trait_id) && shape.trait_value(trait_id) is None {
          continue
        }
        let message = validation_string(configuration, "messageTemplate").unwrap_or(
          "Selector capture matched selector: " + expression,
        )
        events.push(validation_event(name, "DANGER", Some(shape), message))
      }
    }
  } else {
    events.push(
      validation_event(
        "UnknownValidator_" + name,
        "WARNING",
        None,
        "Unable to locate a validator named `" + name + "`",
      ),
    )
    return events
  }
  let candidate_ids = match validation_string(definition, "selector") {
    Some(expression) => {
      let selector = Selector::parse(expression) catch { _ => return [] }
      Some(selector.select_ids(self))
    }
    None => None
  }
  let namespaces = validation_array(validation_field(definition, "namespaces"))
  let configured_severity = validation_string(definition, "severity")
  let configured_message = validation_string(definition, "message")
  let result : Array[ValidationEvent] = []
  for event in events {
    if event.shape is Some(shape) {
      if !namespaces.is_empty() &&
        !namespaces.iter().any(ns => ns == String(shape.namespace)) {
        continue
      }
      if candidate_ids is Some(ids) && !ids.contains(shape.to_string()) {
        continue
      }
    }
    let suffix = match event.id.find(".") {
      Some(at) => event.id[at:].to_owned()
      None => ""
    }
    let severity = match configured_severity {
      Some("WARNING") => "WARNING"
      Some("NOTE") => "NOTE"
      Some("DANGER") => "DANGER"
      _ => event.severity
    }
    let message = match configured_message {
      Some(template) => template.replace_all(old="{super}", new=event.message)
      None => event.message
    }
    result.push({ ..event, id: id + suffix, severity, message, })
  }
  result
}

///|
fn Model::trait_target_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    if shape.source.file == "<contracts>" || shape.id.namespace == "smithy.api" {
      continue
    }
    for trait_id, _ in shape.traits {
      guard self.shapes.get(trait_id) is Some(definition) else { continue }
      let trait_name = if trait_id.namespace == "smithy.api" {
        trait_id.name
      } else {
        trait_id.to_string()
      }
      if definition.trait_value("smithy.api#mixin") is Some(_) {
        events.push(
          validation_event(
            "TraitTarget",
            "ERROR",
            Some(shape),
            "Trait `" +
            trait_name +
            "` is a mixin and cannot be applied to `" +
            shape.id.to_string() +
            "`.",
          ),
        )
      }
      guard definition.trait_value("smithy.api#trait") is Some(config) &&
        validation_string(config, "selector") is Some(expression) &&
        expression != "*" else {
        continue
      }
      let selector = Selector::parse(expression) catch { _ => continue }
      if !selector.select_ids(self).contains(shape.id.to_string()) {
        events.push(
          validation_event(
            "TraitTarget",
            "ERROR",
            Some(shape),
            "Trait `" +
            trait_name +
            "` cannot be applied to `" +
            shape.id.to_string() +
            "`. This trait may only be applied to shapes that match the following selector: " +
            expression,
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::trait_validator_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for trait_id, trait_shape in self.shapes {
    guard trait_shape.trait_value("smithy.api#traitValidators")
      is Some(Object(validators)) else {
      continue
    }
    for _, applied in self.shapes {
      if applied.traits.get(trait_id) is None {
        continue
      }
      for event_id, definition in validators {
        guard validation_string(definition, "selector") is Some(expression) else {
          continue
        }
        let selector = Selector::parse(expression) catch { _ => continue }
        for shape_id in selector.select_ids_from(self, applied.id.to_string()) {
          guard self.get(shape_id) is Some(shape) else { continue }
          let suffix = match validation_string(definition, "message") {
            Some(message) => ": " + message
            None => ""
          }
          let severity = validation_string(definition, "severity").unwrap_or(
            "ERROR",
          )
          events.push(
            validation_event(
              event_id,
              severity,
              Some(shape),
              "Found an incompatible shape when validating the constraints of the `" +
              trait_id.to_string() +
              "` trait attached to `" +
              applied.id.to_string() +
              "`" +
              suffix,
            ),
          )
        }
      }
    }
  }
  events
}

///|
/// Run validators configured in model metadata and apply event decoration.
pub fn Model::validation_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  events.append(self.trait_target_events())
  events.append(self.trait_validator_events())
  for definition in validation_array(self.metadata.get("validators")) {
    events.append(self.configured_validation_events(definition))
  }
  events.map(event => self.decorate_validation_event(event))
}

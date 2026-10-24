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
fn validator_config_error(name : String, detail : String) -> ValidationEvent {
  validation_event(
    "Model",
    "ERROR",
    None,
    "Error creating `" + name + "` validator: " + detail,
  )
}

///|
fn validation_node_type(value : NodeValue) -> String {
  match value {
    Null => "null"
    Boolean(_) => "boolean"
    Number(_) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn Model::validation_metadata_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  if self.metadata.get("validators") is Some(value) {
    match value {
      Array(definitions) =>
        for definition in definitions {
          if !(definition is Object(_)) {
            events.push(
              validation_event(
                "Model",
                "ERROR",
                None,
                "Each element of `validators` must be an object. Found " +
                validation_node_type(definition) +
                ".",
              ),
            )
          }
        }
      _ =>
        events.push(
          validation_event(
            "Model",
            "ERROR",
            None,
            "validators must be an array. Found " +
            validation_node_type(value) +
            ".",
          ),
        )
    }
  }
  for name in ["suppressions", "severityOverrides"] {
    guard self.metadata.get(name) is Some(value) else { continue }
    guard value is Array(rules) else {
      events.push(
        validation_event(
          "Model",
          "ERROR",
          None,
          "Expected array, but found " + validation_node_type(value) + ".",
        ),
      )
      continue
    }
    let mut invalid_array = false
    for i = 0; i < rules.length(); i = i + 1 {
      if !(rules[i] is Object(_)) {
        events.push(
          validation_event(
            "Model",
            "ERROR",
            None,
            "Expected array element " +
            i.to_string() +
            " to be a object but found " +
            validation_node_type(rules[i]) +
            ".",
          ),
        )
        invalid_array = true
        break
      }
    }
    if invalid_array {
      continue
    }
    let required = if name == "severityOverrides" {
      ["id", "namespace", "severity"]
    } else {
      ["id", "namespace"]
    }
    for rule in rules {
      let mut invalid_rule = false
      for key in required {
        let detail = match validation_field(rule, key) {
          None => Some("Missing expected member `" + key + "`.")
          Some(String(_)) => None
          Some(value) =>
            Some(
              "Expected string, but found " + validation_node_type(value) + ".",
            )
        }
        if detail is Some(message) {
          events.push(validation_event("Model", "ERROR", None, message))
          invalid_rule = true
          break
        }
      }
      if invalid_rule {
        continue
      }
      if name == "severityOverrides" &&
        validation_string(rule, "severity") is Some(severity) &&
        severity != "WARNING" &&
        severity != "DANGER" {
        events.push(
          validation_event(
            "Model",
            "ERROR",
            None,
            "Expected one of `DANGER`, `WARNING`; got `" + severity + "`.",
          ),
        )
      }
    }
  }
  events
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
priv enum ValidationTemplatePart {
  TemplateText(String)
  TemplateAttribute(Array[String])
}

///|
fn validation_template_parts(
  template : String,
) -> Array[ValidationTemplatePart] raise SelectorError {
  let parser : SelectorParser = {
    chars: template.to_array(),
    pos: 0,
    depth: 0,
  }
  let parts : Array[ValidationTemplatePart] = []
  let mut literal = ""
  while parser.peek() != '\u{0}' {
    if parser.peek() != '@' {
      literal += parser.take().to_string()
    } else if parser.pos + 1 < parser.chars.length() &&
      parser.chars[parser.pos + 1] == '@' {
      parser.pos += 2
      literal += "@"
    } else {
      if !literal.is_empty() {
        parts.push(TemplateText(literal))
        literal = ""
      }
      guard parser.scoped_value() is Path(path) else {
        raise InvalidSelector("I expected a message template attribute.")
      }
      parts.push(TemplateAttribute(path))
    }
  }
  if !literal.is_empty() {
    parts.push(TemplateText(literal))
  }
  parts
}

///|
fn validation_template_value(
  path : Array[String],
  shape : Shape,
  variables : Map[String, Array[String]],
  model : Model,
) -> String {
  if path[0] == "var" && path.length() >= 2 {
    let values : Array[String] = []
    for id in variables.get(path[1]).unwrap_or([]) {
      if path.length() == 2 {
        values.push(id)
      } else if model.get(id) is Some(captured) {
        values.append(selector_attribute(captured, path[2:].to_owned()))
      }
    }
    return "[" + values.join(", ") + "]"
  }
  if path[0] == "trait" &&
    path.length() >= 2 &&
    selector_trait(shape, path[1]) is Some(initial) {
    let values = selector_node_path([initial], path, 2).map(v => {
      @json.to_json(v).stringify()
    })
    return if values.length() == 1 {
      values[0]
    } else {
      "[" + values.join(", ") + "]"
    }
  }
  selector_attribute(shape, path).join(", ")
}

///|
fn validation_template(
  parts : Array[ValidationTemplatePart],
  shape : Shape,
  variables : Map[String, Array[String]],
  model : Model,
) -> String {
  let out = StringBuilder()
  for part in parts {
    match part {
      TemplateText(text) => out.write_string(text)
      TemplateAttribute(path) =>
        out.write_string(
          validation_template_value(path, shape, variables, model),
        )
    }
  }
  out.to_string()
}

///|
/// Apply this model's suppressions and severity overrides to an event. ERROR
/// and already-suppressed events retain their severity, as in Smithy validation.
pub fn Model::decorate_validation_event(
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
fn validator_definition_error(definition : NodeValue) -> String? {
  match validation_field(definition, "name") {
    None => return Some("Missing expected member `name`.")
    Some(String(_)) => ()
    Some(value) =>
      return Some(
        "Expected `name` to be a string; found " + validation_node_type(value),
      )
  }
  for key in ["id", "message", "severity"] {
    if validation_field(definition, key) is Some(value) && !(value is String(_)) {
      return Some(
        "Expected `" +
        key +
        "` to be a string; found " +
        validation_node_type(value),
      )
    }
  }
  if validation_string(definition, "severity") is Some(severity) &&
    !["DANGER", "WARNING", "NOTE"].contains(severity) {
    return Some(
      "Expected one of `DANGER`, `WARNING`, `NOTE`; got `" + severity + "`.",
    )
  }
  if validation_field(definition, "namespaces") is Some(value) {
    guard value is Array(namespaces) else {
      return Some(
        "Expected `namespaces` to be an array of strings. Found " +
        validation_node_type(value) +
        ".",
      )
    }
    for namespace in namespaces {
      if !(namespace is String(_)) {
        return Some(
          "Expected string, but found " + validation_node_type(namespace) + ".",
        )
      }
    }
  }
  if validation_field(definition, "configuration") is Some(value) &&
    !(value is Object(_)) {
    return Some(
      "Expected `configuration` to be an object; found " +
      validation_node_type(value),
    )
  }
  if validation_field(definition, "selector") is Some(value) {
    guard value is String(selector) else {
      return Some(
        "Expected `selector` to be a string; found " +
        validation_node_type(value),
      )
    }
    ignore(Selector::parse(selector)) catch {
      InvalidSelector(message) => return Some(message)
    }
  }
  None
}

///|
fn validator_factory_configuration_error(
  name : String,
  configuration : NodeValue,
) -> String? {
  if name == "UnreferencedShape" {
    if configuration is Object(fields) &&
      fields.keys().any(key => key != "rootShapeSelector") {
      return Some(
        "Unexpected property in UnreferencedShape configuration; expected only `rootShapeSelector`.",
      )
    }
    if validation_field(configuration, "rootShapeSelector") is Some(value) &&
      !(value is String(_)) {
      return Some(
        "Expected `rootShapeSelector` to be a string; found " +
        validation_node_type(value),
      )
    }
  }
  if name == "EmitEachSelector" || name == "EmitNoneSelector" {
    if validation_field(configuration, "selector") is Some(value) &&
      !(value is String(_)) {
      return Some(
        "Expected `selector` to be a string; found " +
        validation_node_type(value),
      )
    }
  }
  if name == "EmitEachSelector" {
    if validation_field(configuration, "bindToTrait") is Some(value) &&
      value != Null {
      guard value is String(id) else {
        return Some(
          "Expected `bindToTrait` to be a string; found " +
          validation_node_type(value),
        )
      }
      if ShapeId::parse(id) is None {
        return Some("Invalid shape ID: " + id)
      }
    }
    if validation_field(configuration, "messageTemplate") is Some(value) &&
      !(value is String(_)) {
      return Some(
        "Expected `messageTemplate` to be a string; found " +
        validation_node_type(value),
      )
    }
  }
  None
}

///|
fn Model::configured_validation_events(
  self : Model,
  definition : NodeValue,
  graph : SelectorGraph,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  if !(definition is Object(_)) {
    return events
  }
  if validator_definition_error(definition) is Some(message) {
    events.push(validation_event("Model", "ERROR", None, message))
    return events
  }
  guard validation_string(definition, "name") is Some(name) else {
    return events
  }
  let id = validation_string(definition, "id").unwrap_or(name)
  let configuration = validation_field(definition, "configuration").unwrap_or(
    Object(Map([])),
  )
  if validator_factory_configuration_error(name, configuration) is Some(message) {
    events.push(validator_config_error(name, message))
    return events
  }
  let selector_text = validation_string(configuration, "selector")
  if name == "UnreferencedShape" {
    let expression = validation_string(configuration, "rootShapeSelector").unwrap_or(
      "service",
    )
    let selector = Selector::parse(expression) catch {
      _ => {
        events.push(
          validator_config_error(name, "Error parsing rootShapeSelector"),
        )
        return events
      }
    }
    let reachable : Map[String, Bool] = Map([])
    let pending = selector.select_ids_in(graph)
    for shape_id, shape in self.shapes {
      if shape.trait_value("smithy.api#trait") is Some(_) ||
        shape.trait_value("smithy.api#metadata") is Some(_) {
        pending.push(shape_id.to_string())
      }
    }
    while !pending.is_empty() {
      let current = pending.pop().unwrap()
      if reachable.contains(current) {
        continue
      }
      reachable[current] = true
      guard ShapeId::parse(current) is Some(id) else { continue }
      for edge in graph.outgoing(id) {
        pending.push(edge.to.to_string())
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
    guard selector_text is Some(expression) else {
      events.push(validator_config_error(name, "selector is required"))
      return events
    }
    let selector = Selector::parse(expression) catch {
      _ => {
        events.push(validator_config_error(name, "Error parsing selector"))
        return events
      }
    }
    let mut matches = selector.select_ids_in(graph)
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
      match validation_string(configuration, "messageTemplate") {
        Some(template) => {
          let parts = validation_template_parts(template) catch {
            InvalidSelector(message) => {
              events.push(
                validator_config_error(
                  name,
                  "Invalid message template: " + message,
                ),
              )
              return events
            }
          }
          for selection in selector.select_matches_in(graph) {
            guard self.get(selection.id) is Some(shape) else { continue }
            if bound is Some(trait_id) && shape.trait_value(trait_id) is None {
              continue
            }
            events.push(
              validation_event(
                name,
                "DANGER",
                Some(shape),
                validation_template(parts, shape, selection.variables, self),
              ),
            )
          }
        }
        None =>
          for shape_id in matches {
            guard self.get(shape_id) is Some(shape) else { continue }
            if bound is Some(trait_id) && shape.trait_value(trait_id) is None {
              continue
            }
            events.push(
              validation_event(
                name,
                "DANGER",
                Some(shape),
                "Selector capture matched selector: " + expression,
              ),
            )
          }
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
      Some(Set::from_array(selector.select_ids_in(graph)))
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
fn Model::trait_target_events(
  self : Model,
  graph : SelectorGraph,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  // The shapes that each trait selector matches, computed once per trait.
  // `None` marks a selector that does not parse.
  let targets : Map[ShapeId, Set[ShapeId]?] = Map([])
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
      let matched = match targets.get(trait_id) {
        Some(matched) => matched
        None => {
          let matched = Some(Selector::parse(expression).select_set_in(graph)) catch {
            _ => None
          }
          targets[trait_id] = matched
          matched
        }
      }
      guard matched is Some(matched) else { continue }
      if !matched.contains(shape.id) {
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
fn Model::trait_validator_events(
  self : Model,
  graph : SelectorGraph,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for trait_id, trait_shape in self.shapes {
    guard trait_shape.trait_value("smithy.api#traitValidators")
      is Some(Object(validators)) else {
      continue
    }
    let mut valid = true
    for event_id, _ in validators {
      if ShapeId::parse(event_id + "#Event") is None {
        valid = false
        events.push(
          validation_event(
            "TraitValidators",
            "ERROR",
            Some(trait_shape),
            "`smithy.api#traitValidators` key is not a valid event ID: `" +
            event_id +
            "`",
          ),
        )
      }
    }
    if !valid {
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
        for
          shape_id in selector.select_ids_from_in(graph, applied.id.to_string()) {
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
  let assembly = Assembly::new()
  assembly.validate(self, check_trait_definitions=false)
  self.collect_validation_events(
    assembly.diagnostics
    .filter(d => d.report != CoveredBySelector)
    .map(diagnostic_event),
  )
}

///|
fn validation_is_correctness(event : ValidationEvent) -> Bool {
  suppression_matches("Target", event.id) ||
  suppression_matches("ResourceCycle", event.id) ||
  suppression_matches("DeprecatedShape", event.id)
}

///|
fn validation_is_critical(event : ValidationEvent) -> Bool {
  [
    "EnumShape", "ExclusiveStructureMemberTrait", "TraitTarget", "TraitValue", "TraitConflict",
    "DefaultTrait", "ShapeIdConflict", "SingleOperationBinding", "SingleResourceBinding",
  ]
  .iter()
  .any(id => suppression_matches(id, event.id))
}

///|
fn validation_is_loading_event(event : ValidationEvent) -> Bool {
  event.id == "Model" ||
  event.id == "Model.BadDocumentationComment" ||
  event.id == "ModelDeprecation" ||
  event.id.has_prefix("UnknownValidator_") ||
  event.id.has_prefix("SM-")
}

///|
fn Model::collect_validation_events(
  self : Model,
  initial : Array[ValidationEvent],
) -> Array[ValidationEvent] {
  if initial.iter().any(e => e.severity == "ERROR" && e.id == "Model") {
    return initial
      .filter(validation_is_loading_event)
      .map(e => self.decorate_validation_event(e))
  }
  let events : Array[ValidationEvent] = []
  let graph = SelectorGraph::new(self)
  events.append(initial)
  events.append(self.validation_metadata_events())
  events.append(self.trait_target_events(graph))
  events.append(self.trait_validator_events(graph))
  events.append(self.constraint_trait_events())
  events.append(self.basic_trait_events())
  events.append(self.default_trait_events())
  events.append(self.trait_conflict_events())
  events.append(self.exclusive_trait_events())
  events.append(self.json_name_events())
  events.append(self.service_events())
  events.append(self.operation_events())
  events.append(self.resource_events())
  events.append(self.http_events())
  events.append(self.protocol_events())
  events.append(self.metadata_trait_events())
  events.append(self.semantic_trait_events())
  events.append(self.examples_events())
  events.append(self.protocol_test_events())
  events.append(self.recursion_and_format_events())
  for definition in validation_array(self.metadata.get("validators")) {
    events.append(self.configured_validation_events(definition, graph))
  }
  let decorated = events
    .filter(event => {
      event.severity == "ERROR" ||
      event.shape.map(id => id.namespace != "smithy.api").unwrap_or(true)
    })
    .map(event => self.decorate_validation_event(event))
  if decorated.iter().any(e => e.severity == "ERROR" && e.id == "Model") {
    return decorated.filter(e => {
      validation_is_loading_event(e) || validation_is_correctness(e)
    })
  }
  if decorated
    .iter()
    .any(e => e.severity == "ERROR" && validation_is_correctness(e)) {
    return decorated.filter(e => {
      validation_is_correctness(e) || validation_is_loading_event(e)
    })
  }
  if decorated
    .iter()
    .any(e => e.severity == "ERROR" && validation_is_critical(e)) {
    return decorated.filter(e => {
      validation_is_correctness(e) ||
      validation_is_critical(e) ||
      validation_is_loading_event(e)
    })
  }
  decorated
}

///|
/// Include assembly findings even when no complete model could be returned.
pub fn LoadResult::validation_events(
  self : LoadResult,
) -> Array[ValidationEvent] {
  self.validation_findings
}

///|
fn diagnostic_event(d : ModelDiagnostic) -> ValidationEvent {
  {
    id: d.event_id,
    severity: if d.severity == Error {
      if d.report == DangerEvent {
        "DANGER"
      } else {
        "ERROR"
      }
    } else {
      "WARNING"
    },
    shape: d.shape,
    message: d.message,
    source: Some(d.source),
    suppression_reason: None,
  }
}

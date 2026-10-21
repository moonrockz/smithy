///|
priv enum ChangeKind {
  Add
  Remove
  Update
} derive(Eq)

///|
priv struct TraitPath {
  segments : Array[String]
} derive(Eq)

///|
fn TraitPath::render(self : TraitPath) -> String {
  if self.segments.is_empty() {
    ""
  } else {
    "/" + self.segments.join("/")
  }
}

///|
fn TraitPath::child(self : TraitPath, name : String) -> TraitPath {
  { segments: self.segments + [name], }
}

///|
fn change_kind(a : @smithy.NodeValue?, b : @smithy.NodeValue?) -> ChangeKind? {
  match (a, b) {
    (None, Some(_)) => Some(Add)
    (Some(_), None) => Some(Remove)
    (Some(a), Some(b)) => if a == b { None } else { Some(Update) }
    _ => None
  }
}

///|
fn change_name(change : ChangeKind) -> String {
  match change {
    Add => "Add"
    Remove => "Remove"
    Update => "Update"
  }
}

///|
fn ticked_node(value : @smithy.NodeValue) -> String {
  let text = pretty(value)
  if text.contains("\n") {
    "\n```\n" + text + "\n```\n"
  } else if value is String(_) {
    tick(text[1:text.length() - 1].to_owned())
  } else {
    tick(text)
  }
}

///|
fn trait_message(
  id : @smithy.ShapeId,
  path : TraitPath,
  a : @smithy.NodeValue?,
  b : @smithy.NodeValue?,
  breaking : Bool,
) -> String {
  let name = tick(id.to_string())
  let location = path.render()
  match change_kind(a, b) {
    Some(Add) => {
      let value = b.unwrap()
      if location != "" {
        "Added trait contents to " +
        name +
        " at path " +
        tick(location) +
        " with value " +
        ticked_node(value)
      } else if breaking && value == @smithy.NodeValue::Object(Map([])) {
        "Added trait " + name
      } else {
        "Added trait " + name + " with value " + ticked_node(value)
      }
    }
    Some(Remove) => {
      let value = a.unwrap()
      if location != "" {
        "Removed trait contents from " +
        name +
        " at path " +
        tick(location) +
        ". Removed value: " +
        ticked_node(value)
      } else if breaking && value == @smithy.NodeValue::Object(Map([])) {
        "Removed trait " + name
      } else {
        "Removed trait " +
        name +
        ". Previous trait value: " +
        ticked_node(value)
      }
    }
    _ => {
      let subject = if location == "" {
        "Changed trait " + name
      } else {
        "Changed trait contents of " + name + " at path " + tick(location)
      }
      subject +
      " from " +
      ticked_node(a.unwrap()) +
      " to " +
      ticked_node(b.unwrap())
    }
  }
}

///|
priv enum Strategy {
  Check(ChangeKind?, String)
  Contents
}

///|
fn legacy_strategies(shape : @smithy.Shape, contents : Bool) -> Array[Strategy] {
  let result = []
  for tag in strings(shape.trait_value("smithy.api#tags")) {
    if tag == "diff.contents" && contents {
      result.push(Contents)
      continue
    }
    let segments = tag.split(".").map(s => s.to_owned()).to_array()
    if segments.length() != 3 || segments[0] != "diff" {
      continue
    }
    let severity = match segments[1] {
      "error" => "ERROR"
      "danger" => "DANGER"
      "warning" => "WARNING"
      _ => continue
    }
    let kind = match segments[2] {
      "add" => Some(Add)
      "remove" => Some(Remove)
      "update" => Some(Update)
      "const" => None
      _ => continue
    }
    result.push(Check(kind, severity))
  }
  result
}

///|
fn check_strategy(
  strategy : Strategy,
  path : TraitPath,
  target : @smithy.Shape,
  id : @smithy.ShapeId,
  a : @smithy.NodeValue?,
  b : @smithy.NodeValue?,
  events : Array[ValidationEvent],
) -> Unit {
  if strategy is Check(expected, severity) &&
    change_kind(a, b) is Some(actual) &&
    (expected == None || expected == Some(actual)) {
    emit(
      events,
      "ModifiedTrait." + change_name(actual) + "." + id.to_string(),
      severity,
      target,
      trait_message(id, path, a, b, false),
    )
  }
}

///|
priv struct TraitWalk {
  shape : @smithy.ShapeId
  old_value : @smithy.NodeValue?
  new_value : @smithy.NodeValue?
  path : TraitPath
}

///|
fn crawl_legacy(
  model : @smithy.Model,
  target : @smithy.Shape,
  id : @smithy.ShapeId,
  a : @smithy.NodeValue?,
  b : @smithy.NodeValue?,
  events : Array[ValidationEvent],
) -> Unit {
  let stack : Array[TraitWalk] = [
    { shape: id, old_value: a, new_value: b, path: { segments: [], }, },
  ]
  while stack.pop() is Some(item) {
    guard model.shapes.get(item.shape) is Some(shape) else { continue }
    let a = item.old_value
    let b = item.new_value
    match shape.body {
      Member(target=next) => {
        for strategy in legacy_strategies(shape, false) {
          check_strategy(strategy, item.path, target, id, a, b, events)
        }
        stack.push({ ..item, shape: next, })
      }
      List(member_shape) =>
        if a is Some(Array(old_values)) && b is Some(Array(new_values)) {
          let count = if old_values.length() > new_values.length() {
            old_values.length()
          } else {
            new_values.length()
          }
          for i = 0; i < count; i = i + 1 {
            stack.push({
              shape: member_shape,
              old_value: old_values.get(i),
              new_value: new_values.get(i),
              path: item.path.child(i.to_string()),
            })
          }
        }
      Map(value~, ..) =>
        if a is Some(Object(old_values)) && b is Some(Object(new_values)) {
          for key, old_value in old_values {
            stack.push({
              shape: value,
              old_value: Some(old_value),
              new_value: new_values.get(key),
              path: item.path.child(key),
            })
          }
          for key, new_value in new_values {
            if !old_values.contains(key) {
              stack.push({
                shape: value,
                old_value: None,
                new_value: Some(new_value),
                path: item.path.child(key),
              })
            }
          }
        }
      Structure(ids) | Union(ids) =>
        if a is Some(Object(old_values)) && b is Some(Object(new_values)) {
          for member_shape in ids {
            let name = member_shape.member_name().unwrap()
            if old_values.contains(name) || new_values.contains(name) {
              stack.push({
                shape: member_shape,
                old_value: old_values.get(name),
                new_value: new_values.get(name),
                path: item.path.child(name),
              })
            }
          }
        }
      _ => ()
    }
  }
}

///|
fn extract_rule(
  model : @smithy.Model,
  start : @smithy.ShapeId,
  segments : Array[String],
  value : @smithy.NodeValue,
) -> Array[(TraitPath, @smithy.NodeValue)] {
  let out = []
  let stack : Array[(TraitPath, @smithy.ShapeId, Int32, @smithy.NodeValue)] = [
    ({ segments: [], }, start, 0, value),
  ]
  while stack.pop() is Some((path, id, position, node)) {
    if position >= segments.length() || segments[position] == "" {
      out.push((path, node))
      continue
    }
    guard model.shapes.get(id) is Some(shape) else { continue }
    let segment = segments[position]
    let member_shape = members(shape)
      .iter()
      .find_first(id => id.member_name() == Some(segment))
    guard member_shape.bind(id => model.shapes.get(id))
      is Some({ body: Member(target~), .. }) else {
      continue
    }
    match (shape.body, node) {
      (List(_), Array(values)) =>
        for i, value in values {
          stack.push((path.child(i.to_string()), target, position + 1, value))
        }
      // The pinned implementation walks map values for both key and value paths.
      (Map(..), Object(values)) =>
        for key, value in values {
          stack.push((path.child(key), target, position + 1, value))
        }
      (Structure(_) | Union(_), Object(values)) =>
        stack.push(
          (
            path.child(segment),
            target,
            position + 1,
            values.get(segment).unwrap_or(Null),
          ),
        )
      _ => ()
    }
  }
  out
}

///|
fn breaking_changes(
  model : @smithy.Model,
  definition : @smithy.Shape,
  target : @smithy.Shape,
  change : TraitChange,
  rules : Array[@smithy.NodeValue],
  events : Array[ValidationEvent],
) -> Unit {
  for rule in rules {
    let raw_path = string(field(Some(rule), "path")).unwrap_or("")
    let segments = if raw_path == "" {
      []
    } else {
      raw_path.split("/").drop(1).map(s => s.to_owned()).to_array()
    }
    let old_value = change.old_value.unwrap_or(Null)
    let new_value = change.new_value.unwrap_or(Null)
    if new_value == Null && !segments.is_empty() {
      continue
    }
    let old_values = extract_rule(model, definition.id, segments, old_value)
    let new_values = extract_rule(model, definition.id, segments, new_value)
    let pairs = old_values.map(pair => {
      (
        pair.0,
        pair.1,
        new_values
        .iter()
        .find_first(p => p.0 == pair.0)
        .map(p => p.1)
        .unwrap_or(Null),
      )
    })
    for (path, value) in new_values {
      if !old_values.iter().any(p => p.0 == path) {
        pairs.push((path, Null, value))
      }
    }
    for (path, a, b) in pairs {
      let a = if a == Null { None } else { Some(a) }
      let b = if b == Null { None } else { Some(b) }
      guard change_kind(a, b) is Some(actual) else { continue }
      let rule_kind = string(field(Some(rule), "change")).unwrap_or("any")
      let matches = match rule_kind {
        "any" => true
        "presence" => actual != Update
        "add" => actual == Add
        "remove" => actual == Remove
        "update" => actual == Update
        _ => false
      }
      if !matches {
        continue
      }
      let severity = string(field(Some(rule), "severity")).unwrap_or("ERROR")
      let mut message = trait_message(definition.id, path, a, b, true)
      if string(field(Some(rule), "message")) is Some(extra) {
        message = message +
          (if message.has_suffix(".") { "" } else { "; " }) +
          extra
      }
      emit(
        events,
        "TraitBreakingChange." +
        change_name(actual) +
        "." +
        definition.id.to_string(),
        severity,
        target,
        message,
      )
    }
  }
}

///|
fn trait_changes(
  d : Differences,
  change : ShapeChange,
  events : Array[ValidationEvent],
) -> Unit {
  for trait_change in change.traits {
    let id = trait_change.id
    let definition = d.new_model.shapes.get(id)
    let rules = match
      definition.bind(s => {
        field(s.trait_value("smithy.api#trait"), "breakingChanges")
      }) {
      Some(Array(rules)) => rules
      _ => []
    }
    if definition is Some(definition) {
      breaking_changes(
        d.new_model,
        definition,
        change.new_shape,
        trait_change,
        rules,
        events,
      )
    }
    if [
        "smithy.api#box", "smithy.api#required", "smithy.synthetic#enum", "smithy.synthetic#originalShapeId",
      ].contains(id.to_string()) {
      continue
    }
    let mut strategies = definition
      .map(s => legacy_strategies(s, true))
      .unwrap_or([Check(None, "WARNING")])
    if strategies.is_empty() && rules.is_empty() {
      strategies = [
        Check(Some(Add), "NOTE"),
        Check(Some(Update), "NOTE"),
        Check(Some(Remove), "WARNING"),
      ]
    }
    for strategy in strategies {
      match strategy {
        Contents =>
          if trait_change.old_value != None && trait_change.new_value != None {
            crawl_legacy(
              d.new_model,
              change.new_shape,
              id,
              trait_change.old_value,
              trait_change.new_value,
              events,
            )
          }
        Check(_, _) =>
          check_strategy(
            strategy,
            { segments: [], },
            change.new_shape,
            id,
            trait_change.old_value,
            trait_change.new_value,
            events,
          )
      }
    }
  }
}

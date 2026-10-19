///|
priv struct SelectorEdge {
  from : ShapeId
  to : ShapeId
  label : String
}

///|
fn selector_edges(model : Model) -> Array[SelectorEdge] {
  let edges : Array[SelectorEdge] = []
  fn link(
    edges : Array[SelectorEdge],
    from : ShapeId,
    to : ShapeId,
    label : String,
  ) {
    if model.shapes.get(to) is Some(shape) && shape.source.file != "<contracts>" {
      edges.push({ from, to, label, })
    }
  }
  for id, shape in model.shapes {
    if shape.source.file == "<contracts>" {
      continue
    }
    if !(shape.body is Member(..)) {
      for mixin in shape.mixins {
        link(edges, id, mixin, "mixin")
      }
    }
    for trait_id, _ in shape.traits {
      link(edges, id, trait_id, "trait")
    }
    match shape.body {
      Simple(_) => ()
      Member(target~) => {
        let enum_member = match model.shapes.get(id.root()) {
          Some(parent) => parent.body is (Enum(_) | IntEnum(_))
          None => false
        }
        if !enum_member {
          link(edges, id, target, "")
        }
      }
      List(member_) => link(edges, id, member_, "member")
      Map(key~, value~) => {
        link(edges, id, key, "member")
        link(edges, id, value, "member")
      }
      Structure(members) | Union(members) | Enum(members) | IntEnum(members) =>
        for member_ in members {
          link(edges, id, member_, "member")
        }
      Operation(input~, output~, errors~) => {
        if input.to_string() != "smithy.api#Unit" {
          link(edges, id, input, "input")
        }
        if output.to_string() != "smithy.api#Unit" {
          link(edges, id, output, "output")
        }
        for error in errors {
          link(edges, id, error, "error")
        }
      }
      Service(operations~, resources~, errors~, ..) => {
        for operation in operations {
          link(edges, id, operation, "operation")
        }
        for resource in resources {
          link(edges, id, resource, "resource")
        }
        for error in errors {
          link(edges, id, error, "error")
        }
      }
      Resource(
        identifiers~,
        properties~,
        create~,
        put~,
        read~,
        update~,
        delete~,
        list~,
        operations~,
        collectionOperations~,
        resources~
      ) => {
        for _, target in identifiers {
          link(edges, id, target, "identifier")
        }
        for _, target in properties {
          link(edges, id, target, "property")
        }
        for
          (label, target) in [
            ("create", create),
            ("put", put),
            ("read", read),
            ("update", update),
            ("delete", delete),
            ("list", list),
          ] {
          if target is Some(target) {
            link(edges, id, target, label)
          }
        }
        for target in operations {
          link(edges, id, target, "operation")
        }
        for target in collectionOperations {
          link(edges, id, target, "collectionOperation")
        }
        for target in resources {
          link(edges, id, target, "resource")
        }
      }
    }
  }
  edges
}

///|
fn selector_type_matches(shape : Shape, keyword : String) -> Bool {
  let kind = shape.body.keyword()
  if keyword == kind || keyword == "*" {
    return true
  }
  match keyword {
    "set" => kind == "list"
    "string" => kind == "enum"
    "integer" => kind == "intEnum"
    "number" =>
      [
        "byte", "short", "integer", "long", "float", "double", "bigInteger", "bigDecimal",
        "intEnum",
      ].contains(kind)
    "simpleType" =>
      shape.body is Simple(_) || kind == "enum" || kind == "intEnum"
    "collection" => kind == "list"
    "aggregateType" => ["list", "map", "structure", "union"].contains(kind)
    "serviceType" => ["service", "resource", "operation"].contains(kind)
    "dataType" =>
      kind != "service" &&
      kind != "resource" &&
      kind != "operation" &&
      kind != "member"
    _ => false
  }
}

///|
fn selector_trait(shape : Shape, name : String) -> NodeValue? {
  for id, value in shape.traits {
    if id.to_string() == name || id.name == name {
      return Some(value)
    }
  }
  None
}

///|
fn selector_attribute(shape : Shape, path : Array[String]) -> Array[String] {
  if path.is_empty() {
    return []
  }
  if path[0] == "id" {
    let id = shape.id
    if path.length() == 1 {
      return [id.to_string()]
    }
    return match path[1] {
      "name" => [id.name]
      "namespace" => [id.namespace]
      "member" => if id.member is Some(name) { [name] } else { [] }
      "(length)" => [id.to_string().length().to_string()]
      _ => []
    }
  }
  if path[0] == "service" && shape.body is Service(version~, ..) {
    return if path.length() == 1 {
      [shape.id.to_string()]
    } else if path[1] == "version" {
      [version]
    } else {
      []
    }
  }
  if path[0] == "trait" && path.length() >= 2 {
    if path[1] == "(length)" {
      return [shape.traits.length().to_string()]
    }
    if path[1] == "(keys)" {
      let keys : Array[String] = []
      for trait_id, _ in shape.traits {
        if path.length() == 2 {
          keys.push(trait_id.to_string())
        } else if path[2] == "namespace" {
          keys.push(trait_id.namespace)
        } else if path[2] == "name" {
          keys.push(trait_id.name)
        }
      }
      return keys
    }
    if path[1] == "(values)" {
      let values : Array[NodeValue] = []
      for _, trait_value in shape.traits {
        values.push(trait_value)
      }
      return selector_node_strings(
        selector_node_path(values, path, 2, projection=true),
        projection=selector_path_projection(path, 2, initial=true),
      )
    }
    guard selector_trait(shape, path[1]) is Some(initial) else { return [] }
    return selector_node_strings(
      selector_node_path([initial], path, 2),
      projection=selector_path_projection(path, 2),
    )
  }
  []
}

///|
fn selector_node_path(
  initial : Array[NodeValue],
  path : Array[String],
  start : Int32,
  projection~ : Bool = false,
) -> Array[NodeValue] {
  let mut current = initial
  let mut is_projection = projection
  for i = start; i < path.length(); i = i + 1 {
    if path[i] == "(first)" && is_projection {
      current = if current.is_empty() { [] } else { [current[0]] }
      is_projection = false
      continue
    }
    let next : Array[NodeValue] = []
    for value in current {
      match path[i] {
        "(values)" =>
          match value {
            Array(items) => next.append(items)
            Object(fields) =>
              for _, item in fields {
                next.push(item)
              }
            _ => ()
          }
        "(keys)" =>
          if value is Object(fields) {
            for key, _ in fields {
              next.push(String(key))
            }
          }
        "(length)" => {
          let length = match value {
            String(text) => Some(text.length())
            Array(items) => Some(items.length())
            Object(fields) => Some(fields.length())
            _ => None
          }
          if length is Some(length) {
            next.push(String(length.to_string()))
          }
        }
        key =>
          if value is Object(fields) && fields.get(key) is Some(item) {
            if !is_projection || item != Null {
              next.push(item)
            }
          }
      }
    }
    current = next
    if path[i] == "(values)" || path[i] == "(keys)" {
      is_projection = true
    }
  }
  current
}

///|
fn selector_path_projection(
  path : Array[String],
  start : Int32,
  initial~ : Bool = false,
) -> Bool {
  let mut projection = initial
  for i = start; i < path.length(); i = i + 1 {
    if path[i] == "(values)" || path[i] == "(keys)" {
      projection = true
    }
    if path[i] == "(first)" {
      projection = false
    }
  }
  projection
}

///|
// A null inside a projection preserves the projection's presence, but cannot
// compare equal to any value, including itself.
let selector_null_marker : String = "\u{0}selector.null"

///|
fn selector_node_strings(
  values : Array[NodeValue],
  projection~ : Bool = false,
) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    match value {
      String(text) => result.push(text)
      Boolean(value) => result.push(if value { "true" } else { "false" })
      Number(value) => result.push(@json.to_json(value).stringify())
      Null => if projection { result.push(selector_null_marker) }
      _ => result.push("")
    }
  }
  result
}

///|
fn selector_scope_nodes(
  shape : Shape,
  path : Array[String],
) -> Array[NodeValue] {
  if path.is_empty() {
    return [Null]
  }
  if path.length() >= 2 &&
    path[0] == "trait" &&
    selector_trait(shape, path[1]) is Some(value) {
    let nodes = selector_node_path([value], path, 2)
    return if selector_path_projection(path, 2) {
      nodes
    } else {
      nodes.filter(node => node != Null)
    }
  }
  []
}

///|
fn selector_scoped_value(
  value : ScopedValue,
  shape : Shape,
  node : NodeValue,
  model : Model,
  vars : Map[String, Array[ShapeId]],
) -> Array[String] {
  match value {
    Literal(text) => [text]
    Path(path) => {
      if path.is_empty() {
        return []
      }
      if path[0] == "var" && path.length() >= 3 {
        let values : Array[String] = []
        for id in vars.get(path[1]).unwrap_or([]) {
          if model.shapes.get(id) is Some(captured) {
            values.append(selector_attribute(captured, path[2:].to_owned()))
          }
        }
        return values
      }
      if path[0] == "trait" || path[0] == "id" || path[0] == "service" {
        return selector_attribute(shape, path)
      }
      selector_node_strings(
        selector_node_path([node], path, 0),
        projection=selector_path_projection(path, 0),
      )
    }
  }
}

///|
fn selector_compare(
  actual : Array[String],
  op : String?,
  values : Array[String],
  insensitive : Bool,
) -> Bool {
  if op is None {
    return !actual.is_empty()
  }
  guard op is Some(operator) else { return false }
  if operator == "?=" {
    return values.contains(if actual.is_empty() { "false" } else { "true" })
  }
  if operator == "{<}" ||
    operator == "{<<}" ||
    operator == "{=}" ||
    operator == "{!=}" {
    let left = if insensitive {
      actual.map(value => value.to_lower())
    } else {
      actual
    }
    let right = if insensitive {
      values.map(value => value.to_lower())
    } else {
      values
    }
    let subset = left
      .iter()
      .all(value => value != selector_null_marker && right.contains(value))
    let equal = subset &&
      right
      .iter()
      .all(value => value != selector_null_marker && left.contains(value))
    return match operator {
      "{<}" => subset
      "{<<}" => subset && !equal
      "{=}" => equal
      _ => !equal
    }
  }
  for raw in actual {
    if raw == selector_null_marker {
      continue
    }
    let value = if insensitive { raw.to_lower() } else { raw }
    for expected in values {
      if expected == selector_null_marker {
        continue
      }
      let expected = if insensitive { expected.to_lower() } else { expected }
      let matched = match operator {
        "=" => value == expected
        "!=" => value != expected
        "^=" => value.has_prefix(expected)
        "$=" => value.has_suffix(expected)
        "*=" => value.contains(expected)
        ">" | ">=" | "<" | "<=" => {
          let left = @json.parse(value) catch { _ => Json::null() }
          let right = @json.parse(expected) catch { _ => Json::null() }
          match (left, right) {
            (Number(a, ..), Number(b, ..)) =>
              match operator {
                ">" => a > b
                ">=" => a >= b
                "<" => a < b
                _ => a <= b
              }
            _ => false
          }
        }
        _ => false
      }
      if matched {
        return true
      }
    }
  }
  false
}

///|
fn selector_add(out : Array[ShapeId], id : ShapeId) -> Unit {
  if !out.contains(id) {
    out.push(id)
  }
}

///|
fn selector_eval(
  steps : Array[SelectorStep],
  input : Array[ShapeId],
  model : Model,
  edges : Array[SelectorEdge],
  vars : Map[String, Array[ShapeId]],
) -> Array[ShapeId] {
  let mut current = input
  for step in steps {
    let next : Array[ShapeId] = []
    match step {
      AnyShape => next.append(current)
      ShapeType(keyword) =>
        for id in current {
          if model.shapes.get(id) is Some(shape) &&
            selector_type_matches(shape, keyword) {
            selector_add(next, id)
          }
        }
      Attribute(path, op, values, insensitive) =>
        for id in current {
          if model.shapes.get(id) is Some(shape) &&
            selector_compare(
              selector_attribute(shape, path),
              op,
              values,
              insensitive,
            ) {
            selector_add(next, id)
          }
        }
      ScopedAttribute(scope, assertions) =>
        for id in current {
          guard model.shapes.get(id) is Some(shape) else { continue }
          for node in selector_scope_nodes(shape, scope) {
            let mut matched = true
            for assertion in assertions {
              let left = selector_scoped_value(
                assertion.left,
                shape,
                node,
                model,
                vars,
              )
              let right : Array[String] = []
              for value in assertion.right {
                right.append(
                  selector_scoped_value(value, shape, node, model, vars),
                )
              }
              if !selector_compare(
                  left,
                  Some(assertion.operator),
                  right,
                  assertion.insensitive,
                ) {
                matched = false
                break
              }
            }
            if matched {
              selector_add(next, id)
              break
            }
          }
        }
      Neighbor(direction, labels) =>
        for id in current {
          if direction == "~>" {
            let pending = [id]
            let seen : Set[ShapeId] = Set([id])
            while pending.pop() is Some(parent) {
              for edge in edges {
                if edge.from == parent &&
                  edge.label != "trait" &&
                  !seen.contains(edge.to) {
                  seen.add(edge.to)
                  selector_add(next, edge.to)
                  pending.push(edge.to)
                }
              }
            }
          } else {
            for edge in edges {
              if (edge.label != "trait" || labels.contains("trait")) &&
                (labels.is_empty() || labels.contains(edge.label)) {
                if (direction == ">" || direction == "->") && edge.from == id {
                  selector_add(next, edge.to)
                } else if (direction == "<" || direction == "<-") &&
                  edge.to == id {
                  selector_add(next, edge.from)
                }
              }
            }
          }
        }
      VariableStore(name, selector) =>
        for id in current {
          vars[name] = selector_eval(selector, [id], model, edges, vars)
          selector_add(next, id)
        }
      VariableGet(name) => next.append(vars.get(name).unwrap_or([]))
      Function(name, args) =>
        if name == "root" && args.length() == 1 {
          let all : Array[ShapeId] = []
          for id, shape in model.shapes {
            if shape.source.file != "<contracts>" {
              all.push(id)
            }
          }
          let isolated : Map[String, Array[ShapeId]] = Map([])
          next.append(selector_eval(args[0], all, model, edges, isolated))
        } else if name == "recursive" && args.length() == 1 {
          for id in current {
            let pending = [id]
            let seen : Set[ShapeId] = Set([])
            while pending.pop() is Some(parent) {
              for output in selector_eval(args[0], [parent], model, edges, vars) {
                if !seen.contains(output) {
                  seen.add(output)
                  selector_add(next, output)
                  pending.push(output)
                }
              }
            }
          }
        } else if name == "topdown" && !args.is_empty() {
          for id in current {
            guard model.shapes.get(id) is Some(shape) &&
              (
                shape.body is Service(..) ||
                shape.body is Resource(..) ||
                shape.body is Operation(..)
              ) else {
              continue
            }
            let pending = [(id, false)]
            let seen : Set[ShapeId] = Set([])
            while pending.pop() is Some((parent, inherited)) {
              if seen.contains(parent) {
                continue
              }
              seen.add(parent)
              let mut qualified = inherited ||
                !selector_eval(args[0], [parent], model, edges, vars).is_empty()
              if qualified &&
                args.length() > 1 &&
                !selector_eval(args[1], [parent], model, edges, vars).is_empty() {
                qualified = false
              }
              if qualified {
                selector_add(next, parent)
              }
              for edge in edges {
                if edge.from == parent &&
                  (edge.label == "resource" || edge.label == "operation") {
                  pending.push((edge.to, qualified))
                }
              }
            }
          }
        } else {
          for id in current {
            if name == "is" || name == "each" {
              for arg in args {
                for output in selector_eval(arg, [id], model, edges, vars) {
                  selector_add(next, output)
                }
              }
            } else if name == "test" || name == "not" || name == "in" {
              let mut matched = false
              for arg in args {
                let output = selector_eval(arg, [id], model, edges, vars)
                if (name == "in" && output.contains(id)) ||
                  (name != "in" && !output.is_empty()) {
                  matched = true
                }
              }
              if (name == "not" && !matched) || (name != "not" && matched) {
                selector_add(next, id)
              }
            }
          }
        }
    }
    current = next
  }
  current
}

///|
/// Return matching absolute shape IDs in lexical order.
pub fn Selector::select_ids(self : Selector, model : Model) -> Array[String] {
  let result : Array[ShapeId] = []
  let edges = selector_edges(model)
  for id, _ in model.shapes {
    if model.shapes.get(id) is Some(shape) && shape.source.file != "<contracts>" {
      let vars : Map[String, Array[ShapeId]] = Map([])
      for match_id in selector_eval(self.steps, [id], model, edges, vars) {
        selector_add(result, match_id)
      }
    }
  }
  let ids = result.map(id => id.to_string())
  ids.sort_by((a, b) => a.lexical_compare(b))
  ids
}

///|
/// Evaluate a selector with one shape as its starting context.
pub fn Selector::select_ids_from(
  self : Selector,
  model : Model,
  start_id : String,
) -> Array[String] {
  guard ShapeId::parse(start_id) is Some(start) &&
    model.shapes.get(start) is Some(_) else {
    return []
  }
  let vars : Map[String, Array[ShapeId]] = Map([])
  let ids = selector_eval(
    self.steps,
    [start],
    model,
    selector_edges(model),
    vars,
  ).map(id => id.to_string())
  ids.sort_by((a, b) => a.lexical_compare(b))
  ids
}

///|
pub(all) struct SelectorMatch {
  id : String
  variables : Map[String, Array[String]]
} derive(Debug)

///|
/// Retain variable captures for each selector match.
pub fn Selector::select_matches(
  self : Selector,
  model : Model,
) -> Array[SelectorMatch] {
  let matches : Array[SelectorMatch] = []
  let edges = selector_edges(model)
  for start, shape in model.shapes {
    if shape.source.file == "<contracts>" {
      continue
    }
    let vars : Map[String, Array[ShapeId]] = Map([])
    for id in selector_eval(self.steps, [start], model, edges, vars) {
      let variables : Map[String, Array[String]] = Map([])
      for name, captured in vars {
        variables[name] = captured.map(value => value.to_string())
      }
      matches.push({ id: id.to_string(), variables, })
    }
  }
  matches
}

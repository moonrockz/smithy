///|
/// The shapes that each `@idRef` selector expression selects in one model.
/// A validator makes one for its pass, so each distinct expression runs at
/// most once, however many node values it checks.
priv struct IdRefSelections {
  model : Model
  mut graph : SelectorGraph?
  selected : Map[String, Set[ShapeId]]
}

///|
fn IdRefSelections::new(model : Model) -> IdRefSelections {
  { model, graph: None, selected: Map([]), }
}

///|
/// The selector graph of the model. It is built on first use, so a pass that
/// checks no `@idRef` value does not build it.
fn IdRefSelections::selector_graph(self : IdRefSelections) -> SelectorGraph {
  match self.graph {
    Some(graph) => graph
    None => {
      let graph = SelectorGraph::new(self.model)
      self.graph = Some(graph)
      graph
    }
  }
}

///|
/// Tell whether the selector expression `selector` selects `id`, the shape
/// that the node value `text` names. An expression that does not parse
/// selects nothing.
fn IdRefSelections::selects(
  self : IdRefSelections,
  selector : String,
  id : ShapeId,
  text : String,
) -> Bool {
  let selected = match self.selected.get(selector) {
    Some(selected) => selected
    None => {
      let graph = self.selector_graph()
      let selected = Selector::parse(selector).select_set_in(graph) catch {
        _ => Set([])
      }
      self.selected[selector] = selected
      selected
    }
  }
  // `select_ids` returns rendered IDs, so the node value must also be the
  // rendered form of the ID.
  selected.contains(id) && id.to_string() == text
}

///|
/// The parsed form of a condition expression, kept in `parsed` so each
/// expression is parsed once per walk. An expression that does not parse is
/// `None`: the contract analysis reports it, and no value is checked with it.
fn parsed_condition(
  parsed : Map[String, @jmespath.Expression?],
  expression : String,
) -> @jmespath.Expression? {
  match parsed.get(expression) {
    Some(result) => result
    None => {
      let result = Some(@jmespath.parse(expression)) catch { _ => None }
      parsed[expression] = result
      result
    }
  }
}

///|
/// Evaluate a condition on a value. `None` means the condition holds. A
/// failure gives the text to add to the message: empty for a `false` result,
/// as in Smithy, and the reason for a result that is not boolean or an
/// evaluation error. Smithy stops the validation in these two cases.
fn condition_failure(
  expression : @jmespath.Expression,
  value : NodeValue,
) -> String? {
  let result = expression.evaluate(@json.to_json(value)) catch {
    @jmespath.JmespathError(diagnostic) =>
      return Some(", but I could not evaluate it: " + diagnostic.message)
  }
  let kind = match result {
    True => return None
    False => return Some("")
    Null => "null"
    Number(_) => "a number"
    String(_) => "a string"
    Array(_) => "an array"
    Object(_) => "an object"
  }
  Some(", but the result is " + kind + ", not a boolean")
}

///|
/// Tell whether the value reaches the node validator plugins of a shape with
/// this body, as in Smithy's `NodeValidationVisitor`: a member always, a
/// document never, a timestamp always, and any other shape only when the value
/// has its node type (and an integer is in range).
fn conditions_apply(body : ShapeBody, value : NodeValue) -> Bool {
  match (body, value) {
    (Member(..), _) => true
    (Simple(Document), _) => false
    (Simple(Timestamp), _) => true
    (Simple(Boolean), Boolean(_)) => true
    (Simple(String | Blob), String(_)) => true
    (Enum(_), String(_)) => true
    (Simple(Float | Double), Number(_) | String(_)) => true
    (Simple(BigDecimal), Number(_)) => true
    (Simple(BigInteger), Number(n)) => n.is_integer()
    (Simple(Byte), Number(n)) => n.in_range("-128", "127")
    (Simple(Short), Number(n)) => n.in_range("-32768", "32767")
    (Simple(Integer) | IntEnum(_), Number(n)) =>
      n.in_range("-2147483648", "2147483647")
    (Simple(Long), Number(n)) =>
      n.in_range("-9223372036854775808", "9223372036854775807")
    (List(_), Array(_)) => true
    (Map(..) | Structure(_) | Union(_), Object(_)) => true
    _ => false
  }
}

///|
fn Model::node_validation_events(
  self : Model,
  value : NodeValue,
  target : ShapeId,
  owner : Shape?,
  event_id : String,
  severity : String,
  id_refs~ : IdRefSelections,
  allow_constraint_errors~ : Bool = false,
  protocol_params~ : Bool = false,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let stack = [(target, value, "")]
  let seen : Set[String] = Set([])
  let conditions_parsed : Map[String, @jmespath.Expression?] = Map([])
  let constraint_severity = if allow_constraint_errors {
    "WARNING"
  } else {
    severity
  }
  while stack.pop() is Some((target, value, path)) {
    let key = target.to_string() + "|" + path
    if seen.contains(key) {
      continue
    }
    seen.add(key)
    guard self.shapes.get(target) is Some(shape) else { continue }
    let effective = match shape.body {
      Member(target~) => self.shapes.get(target).unwrap_or(shape)
      _ => shape
    }
    let emit = fn(suffix : String, level : String, message : String) {
      events.push(
        validation_event(
          event_id + suffix,
          level,
          owner,
          "Error validating value" + path + ": " + message,
        ),
      )
    }
    if shape.trait_value("smithy.api#range") is Some(range) &&
      value is Number(n) {
      for bound in ["min", "max"] {
        if validation_field(range, bound) is Some(Number(limit)) &&
          (
            (bound == "min" && n.numeric_compare(limit) < 0) ||
            (bound == "max" && n.numeric_compare(limit) > 0)
          ) {
          let level = if event_id == "DefaultTrait" &&
            n.coefficient == BigInt::from_int(0) {
            "WARNING"
          } else {
            constraint_severity
          }
          emit(
            if shape.body is Member(..) {
              ".Member.InvalidRange"
            } else {
              ".Target.InvalidRange"
            },
            level,
            "Value provided for `" +
            target.to_string() +
            "` violates its " +
            bound +
            " range.",
          )
        }
      }
    }
    if shape.trait_value("smithy.api#range") is Some(range) &&
      value is String(text) {
      if text == "NaN" {
        emit(
          "", constraint_severity, "A value constrained by @range must be a number, but found NaN.",
        )
      }
      if (text == "-Infinity" && validation_field(range, "min") is Some(_)) ||
        (text == "Infinity" && validation_field(range, "max") is Some(_)) {
        emit(
          if shape.body is Member(..) {
            ".Member.InvalidRange"
          } else {
            ".Target.InvalidRange"
          },
          constraint_severity,
          "Infinite value violates its range constraint.",
        )
      }
    }
    if shape.trait_value("smithy.api#length") is Some(length) {
      let count = match value {
        String(text) => Some(text.length())
        Array(values) => Some(values.length())
        Object(values) => Some(values.length())
        _ => None
      }
      if count is Some(count) {
        let n = NodeNumber::parse(count.to_string()).unwrap()
        for bound in ["min", "max"] {
          if validation_field(length, bound) is Some(Number(limit)) &&
            (
              (bound == "min" && n.numeric_compare(limit) < 0) ||
              (bound == "max" && n.numeric_compare(limit) > 0)
            ) {
            emit(
              "",
              constraint_severity,
              "Value provided for `" +
              target.to_string() +
              "` violates its " +
              bound +
              " length.",
            )
          }
        }
      }
    }
    if effective.body is Simple(String) && value is String(text) {
      if shape.trait_value("smithy.api#pattern") is Some(String(pattern)) {
        let matches = if shape.id.to_string() == "smithy.api#Identifier" {
          identifier(text)
        } else {
          let pattern = pattern
            .replace_all(old="\\d", new="[0-9]")
            .replace_all(old="\\w", new="[a-zA-Z0-9_]")
          try (@string.Regex::Regex(pattern).execute(text) is Some(_)) catch {
            _ => true
          }
        }
        if !matches {
          emit(
            "",
            constraint_severity,
            "String value provided for `" +
            target.to_string() +
            "` must match regular expression: " +
            pattern,
          )
        }
      }
      if shape.trait_value("smithy.api#idRef") is Some(config) {
        let valid = match ShapeId::parse(text) {
          None => false
          Some(id) =>
            match self.shapes.get(id) {
              None =>
                validation_field(config, "failWhenMissing") !=
                Some(Boolean(true))
              Some(_) => {
                let selector = validation_string(config, "selector").unwrap_or(
                  "*",
                )
                id_refs.selects(selector, id, text)
              }
            }
        }
        if !valid {
          emit(
            "",
            severity,
            validation_string(config, "errorMessage").unwrap_or(
              "Shape ID `" + text + "` does not satisfy its idRef constraint.",
            ),
          )
        }
      }
      if shape.trait_value("smithy.api#enum") is Some(Array(values)) &&
        !values
        .iter()
        .any(entry => validation_field(entry, "value") == Some(value)) {
        emit(
          "",
          severity,
          "String value provided for `" +
          target.to_string() +
          "` is not an enum value.",
        )
      }
    }
    if shape.trait_value("smithy.api#uniqueItems") is Some(_) &&
      value is Array(values) {
      let mut duplicate = false
      for i = 0; i < values.length(); i = i + 1 {
        for j = 0; j < i; j = j + 1 {
          if values[i] == values[j] {
            duplicate = true
          }
        }
      }
      if duplicate {
        emit("", severity, "Collection contains duplicate values.")
      }
    }
    if shape.trait_value("smithy.contracts#conditions")
      is Some(Object(conditions)) &&
      conditions_apply(shape.body, value) {
      for name, condition in conditions {
        guard validation_string(condition, "expression") is Some(expression) &&
          parsed_condition(conditions_parsed, expression) is Some(parsed) else {
          continue
        }
        if condition_failure(parsed, value) is Some(reason) {
          emit(
            "." + name,
            constraint_severity,
            "Value provided for `" +
            target.to_string() +
            "` must match the " +
            name +
            " condition expression" +
            reason,
          )
        }
      }
    }
    let valid = match (shape.body, value) {
      (Member(target~), value) => {
        stack.push((target, value, path))
        true
      }
      (Simple(Document), _) => true
      (Simple(Boolean), Boolean(_)) => true
      (Simple(String | Blob), String(_)) => true
      (Simple(Timestamp), Number(_)) => true
      (Simple(Timestamp), String(_)) => !protocol_params
      (Simple(Float | Double), Number(_)) => true
      (Simple(Float | Double), String("NaN" | "Infinity" | "-Infinity")) => true
      (Simple(BigDecimal), Number(_)) => true
      (Simple(BigInteger), Number(n)) => n.is_integer()
      (Simple(Byte), Number(n)) => n.in_range("-128", "127")
      (Simple(Short), Number(n)) => n.in_range("-32768", "32767")
      (Simple(Integer), Number(n)) => n.in_range("-2147483648", "2147483647")
      (Simple(Long), Number(n)) =>
        n.in_range("-9223372036854775808", "9223372036854775807")
      (List(member_), Array(values)) => {
        for i, value in values {
          if protocol_params &&
            value is Null &&
            shape.trait_value("smithy.api#sparse") is Some(_) {
            continue
          }
          stack.push((member_, value, path + "/" + i.to_string()))
        }
        true
      }
      (Map(key~, value=member_), Object(values)) => {
        for name, value in values {
          if protocol_params &&
            value is Null &&
            shape.trait_value("smithy.api#sparse") is Some(_) {
            continue
          }
          stack.push(
            (key, String(name), path + "/" + pointer(name) + " (map-key)"),
          )
          stack.push((member_, value, path + "/" + pointer(name)))
        }
        true
      }
      (Structure(members) | Union(members), Object(values)) => {
        if shape.body is Union(_) && values.length() > 1 {
          emit(
            "", severity, "Union values can contain a value for only a single member.",
          )
          continue
        }
        let declared : Set[String] = Set([])
        for member_ in members {
          guard self.shapes.get(member_) is Some(member_shape) &&
            member_.member is Some(name) else {
            continue
          }
          declared.add(name)
          match values.get(name) {
            Some(Null) if protocol_params &&
              member_shape.trait_value("smithy.api#required") is None => ()
            Some(value) =>
              stack.push((member_, value, path + "/" + pointer(name)))
            None =>
              if member_shape.trait_value("smithy.api#required") is Some(_) {
                emit(
                  "",
                  constraint_severity,
                  "Missing required structure member `" +
                  name +
                  "` for `" +
                  target.to_string() +
                  "`.",
                )
              }
          }
        }
        for name, _ in values {
          if !declared.contains(name) {
            emit(
              ".UnknownMember." + target.to_string() + "." + name,
              if shape.body is Union(_) {
                severity
              } else {
                "WARNING"
              },
              "Member `" +
              name +
              "` does not exist in `" +
              target.to_string() +
              "`.",
            )
          }
        }
        !(shape.body is Union(_) && values.length() > 1)
      }
      (Enum(members) | IntEnum(members), _) =>
        members
        .iter()
        .any(id => {
          self.shapes.get(id).bind(s => s.trait_value("smithy.api#enumValue")) ==
          Some(value)
        })
      _ => false
    }
    if !valid {
      emit(
        "",
        severity,
        "Expected " +
        shape.body.keyword() +
        " value for `" +
        target.to_string() +
        "`.",
      )
    }
  }
  events
}

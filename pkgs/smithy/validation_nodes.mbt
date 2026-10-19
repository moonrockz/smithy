///|
fn Model::node_validation_events(
  self : Model,
  value : NodeValue,
  target : ShapeId,
  owner : Shape?,
  event_id : String,
  severity : String,
  allow_constraint_errors~ : Bool = false,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let stack = [(target, value, "")]
  let seen : Set[String] = Set([])
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
                Selector::parse(selector).select_ids(self).contains(text) catch {
                  _ => false
                }
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
    let valid = match (shape.body, value) {
      (Member(target~), value) => {
        stack.push((target, value, path))
        true
      }
      (Simple(Document), _) => true
      (Simple(Boolean), Boolean(_)) => true
      (Simple(String | Blob), String(_)) => true
      (Simple(Timestamp), String(_) | Number(_)) => true
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
          stack.push((member_, value, path + "/" + i.to_string()))
        }
        true
      }
      (Map(key~, value=member_), Object(values)) => {
        for name, value in values {
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

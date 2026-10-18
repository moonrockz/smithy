///|
priv enum Argument {
  Value(Json)
  Reference(Node)
}

///|
fn signature(name : String) -> Array[String]? {
  match name {
    "abs" | "ceil" | "floor" => Some(["number"])
    "avg" | "sum" => Some(["array[number]"])
    "contains" => Some(["string|array", "any"])
    "starts_with" | "ends_with" => Some(["string", "string"])
    "join" => Some(["string", "array[string]"])
    "keys" | "values" | "merge" => Some(["object"])
    "length" => Some(["string|array|object"])
    "map" => Some(["expref", "array"])
    "max" | "min" | "sort" => Some(["array[sortable]"])
    "max_by" | "min_by" | "sort_by" => Some(["array", "expref"])
    "reverse" => Some(["string|array"])
    "not_null" | "to_array" | "to_number" | "to_string" | "type" =>
      Some(["any"])
    _ => None
  }
}

///|
fn accepts(value : Json, expected : String) -> Bool {
  if expected == "any" {
    return true
  }
  if expected.contains("|") {
    return expected.split("|").any(t => accepts(value, t.to_owned()))
  }
  match expected {
    "array[number]" =>
      match value {
        Array(xs) => xs.iter().all(x => x is Number(_, ..))
        _ => false
      }
    "array[string]" =>
      match value {
        Array(xs) => xs.iter().all(x => x is String(_))
        _ => false
      }
    "array[sortable]" =>
      match value {
        Array(xs) =>
          xs.is_empty() ||
          xs.iter().all(x => x is Number(_, ..)) ||
          xs.iter().all(x => x is String(_))
        _ => false
      }
    _ => json_type(value) == expected
  }
}

///|
fn[T] type_error(
  name : String,
  expected : String,
  span : Span,
) -> T raise JmespathError {
  raise JmespathError({
    code: InvalidType,
    span,
    message: "I expected \{expected} in JMESPath function \{name}.",
  })
}

///|
fn json_argument(
  arg : Argument,
  name : String,
  span : Span,
) -> Json raise JmespathError {
  match arg {
    Value(value) => value
    Reference(_) => type_error(name, "a JSON argument", span)
  }
}

///|
fn finite_number(value : Double, span : Span) -> Json raise JmespathError {
  if value.is_nan() || value.is_inf() {
    problem(
      InvalidValue,
      span,
      "I expected a finite JSON number from the JMESPath function.",
    )
  }
  Json::number(value)
}

///|
/// Compare strings by Unicode code point rather than UTF-16 code unit.
fn compare_json(a : Json, b : Json) -> Int32 {
  match (a, b) {
    (Number(a, ..), Number(b, ..)) => a.compare(b)
    (String(a), String(b)) => {
      let a = a.iter()
      let b = b.iter()
      while true {
        match (a.next(), b.next()) {
          (Some(a), Some(b)) => {
            let order = a.compare(b)
            if order != 0 {
              return order
            }
          }
          (None, None) => return 0
          (None, _) => return -1
          (_, None) => return 1
        }
      } nobreak {
        0
      }
    }
    _ => 0
  }
}

///|
fn check_arity(
  name : String,
  count : Int32,
  span : Span,
) -> Array[String] raise JmespathError {
  guard signature(name) is Some(types) else {
    problem(
      UnknownFunction,
      span,
      "I could not resolve JMESPath function \{name}.",
    )
    return []
  }
  let variadic = name == "merge" || name == "not_null"
  if count < types.length() || (!variadic && count != types.length()) {
    problem(
      InvalidArity,
      span,
      "I expected \{types.length()} argument(s) for JMESPath function \{name}, but found \{count}.",
    )
  }
  types
}

///|
fn check_arguments(
  name : String,
  nodes : Array[Node],
  args : Array[Argument],
  span : Span,
) -> Unit raise JmespathError {
  let types = check_arity(name, args.length(), span)
  let variadic = name == "merge" || name == "not_null"
  for i, arg in args {
    let expected = types[if variadic { 0 } else { i }]
    let valid = match arg {
      Reference(_) => expected == "expref"
      Value(value) => accepts(value, expected)
    }
    if !valid {
      type_error(name, expected, nodes[i].span)
    }
  }
}

///|
fn call(
  name : String,
  nodes : Array[Node],
  args : Array[Argument],
  span : Span,
) -> Json raise JmespathError {
  // Typed arguments have been checked above. Keep JSON and expression arguments
  // separate so an expression reference can never leak into a JSON result.
  let first = match args[0] {
    Value(value) => value
    Reference(_) => Json::null()
  }
  match name {
    "type" => Json::string(json_type(first))
    "to_array" =>
      match first {
        Array(_) => first
        _ => Json::array([first])
      }
    "to_string" =>
      match first {
        String(_) => first
        _ => Json::string(first.stringify())
      }
    "to_number" =>
      match first {
        Number(n, ..) => finite_number(n, span)
        String(s) => {
          let n = @string.parse_double(s) catch { _ => return Json::null() }
          if n.is_nan() || n.is_inf() {
            Json::null()
          } else {
            Json::number(n)
          }
        }
        _ => Json::null()
      }
    "not_null" => {
      for arg in args {
        let value = json_argument(arg, name, span)
        if value != Json::null() {
          return value
        }
      }
      Json::null()
    }
    "abs" | "ceil" | "floor" => {
      guard first is Number(n, ..) else {
        return type_error(name, "number", span)
      }
      finite_number(
        match name {
          "abs" => n.abs()
          "ceil" => n.ceil()
          _ => n.floor()
        },
        span,
      )
    }
    "length" => {
      let n = match first {
        String(s) => s.iter().count()
        Array(xs) => xs.length()
        Object(xs) => xs.length()
        _ => 0
      }
      Json::number(n.to_double())
    }
    "starts_with" | "ends_with" => {
      guard first is String(s) &&
        json_argument(args[1], name, span) is String(needle) else {
        return type_error(name, "string", span)
      }
      Json::boolean(
        if name == "starts_with" {
          s.has_prefix(needle)
        } else {
          s.has_suffix(needle)
        },
      )
    }
    "contains" => {
      let needle = json_argument(args[1], name, span)
      match first {
        String(s) =>
          match needle {
            String(needle) => Json::boolean(s.contains(needle))
            _ => type_error(name, "a string search value", nodes[1].span)
          }
        Array(xs) => Json::boolean(xs.contains(needle))
        _ => type_error(name, "string or array", span)
      }
    }
    "reverse" =>
      match first {
        String(s) =>
          Json::string(String::from_iter(s.iter().to_array().rev_iter()))
        Array(xs) => Json::array(xs.rev_iter().to_array())
        _ => type_error(name, "string or array", span)
      }
    "keys" | "values" => {
      guard first is Object(fields) else {
        return type_error(name, "object", span)
      }
      let out = []
      for key, value in fields {
        out.push(if name == "keys" { Json::string(key) } else { value })
      }
      Json::array(out)
    }
    "merge" => {
      let out : Map[String, Json] = Map([])
      for arg in args {
        guard json_argument(arg, name, span) is Object(fields) else {
          return type_error(name, "object", span)
        }
        for key, value in fields {
          out[key] = value
        }
      }
      Json::object(out)
    }
    "join" => {
      guard first is String(separator) &&
        json_argument(args[1], name, span) is Array(xs) else {
        return type_error(name, "string and array[string]", span)
      }
      let strings = []
      for value in xs {
        if value is String(s) {
          strings.push(s)
        }
      }
      Json::string(strings.join(separator))
    }
    "sum" | "avg" => {
      guard first is Array(xs) else {
        return type_error(name, "array[number]", span)
      }
      let mut sum = 0.0
      for x in xs {
        if x is Number(n, ..) {
          sum += n
        }
      }
      if name == "avg" && xs.is_empty() {
        Json::null()
      } else {
        finite_number(
          if name == "sum" {
            sum
          } else {
            sum / xs.length().to_double()
          },
          span,
        )
      }
    }
    "sort" | "min" | "max" => {
      guard first is Array(xs) else {
        return type_error(name, "an array of numbers or strings", span)
      }
      let xs = xs.copy()
      if name == "sort" {
        xs.sort_by(compare_json)
        Json::array(xs)
      } else {
        let mut best = Json::null()
        for x in xs {
          let order = compare_json(x, best)
          if best == Json::null() ||
            (name == "min" && order < 0) ||
            (name == "max" && order > 0) {
            best = x
          }
        }
        best
      }
    }
    _ => Json::null()
  }
}

///|
fn apply_keys(
  name : String,
  xs : Array[Json],
  keys : Array[Json],
  span : Span,
) -> Json raise JmespathError {
  let keyed : Array[(Json, Json, Int32)] = []
  let mut key_type = ""
  for i, key in keys {
    let kind = json_type(key)
    if (kind != "number" && kind != "string") ||
      (key_type != "" && key_type != kind) {
      return type_error(
        name, "uniform number or string expression results", span,
      )
    }
    key_type = kind
    keyed.push((key, xs[i], i))
  }
  if name == "sort_by" {
    keyed.sort_by(fn(a, b) {
      let order = compare_json(a.0, b.0)
      if order == 0 {
        a.2.compare(b.2)
      } else {
        order
      }
    })
    Json::array(keyed.map(entry => entry.1))
  } else {
    let mut best : (Json, Json, Int32)? = None
    for entry in keyed {
      match best {
        None => best = Some(entry)
        Some(old) => {
          let order = compare_json(entry.0, old.0)
          if (name == "min_by" && order < 0) || (name == "max_by" && order > 0) {
            best = Some(entry)
          }
        }
      }
    }
    best.map(entry => entry.1).unwrap_or(Json::null())
  }
}

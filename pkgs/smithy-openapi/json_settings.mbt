///|
priv struct DocumentPointer {
  segments : Array[String]
}

///|
fn DocumentPointer::parse(text : String) -> DocumentPointer raise OpenApiError {
  let pointer = text.trim_start(chars="#").to_owned()
  if pointer.is_empty() {
    return { segments: [], }
  }
  guard pointer.has_prefix("/") else {
    raise InvalidConfiguration("JSON pointer must start with /: " + text)
  }
  let segments = pointer[1:]
    .split("/")
    .map(part => {
      part
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    })
    .to_array()
  { segments, }
}

///|
fn substitute_json(node : Json, substitutions : Map[String, Json]) -> Json {
  match node {
    String(value) => substitutions.get(value).unwrap_or(node)
    Array(values) =>
      Json::array(values.map(value => substitute_json(value, substitutions)))
    Object(properties) => {
      let out : Map[String, Json] = Map([])
      for key, value in properties {
        out[key] = substitute_json(value, substitutions)
      }
      Json::object(out)
    }
    _ => node
  }
}

///|
fn add_json_value(
  node : Json,
  segments : Array[String],
  at : Int32,
  value : Json,
) -> Json {
  if at == segments.length() {
    return value
  }
  let key = segments[at]
  let last = at == segments.length() - 1
  match node {
    Object(properties) => {
      let out = copy_fields(node)
      out[key] = if last {
        value
      } else {
        add_json_value(
          properties.get(key).unwrap_or(Json::object(Map([]))),
          segments,
          at + 1,
          value,
        )
      }
      Json::object(out)
    }
    Array(values) => {
      let index = if key == "-" {
        if last {
          values.length()
        } else {
          values.length() - 1
        }
      } else {
        @string.parse_int(key) catch {
          _ => -1
        }
      }
      if index < 0 ||
        index > values.length() ||
        (!last && index == values.length()) {
        return node
      }
      let out : Array[Json] = []
      for i = 0; i < values.length(); i = i + 1 {
        if i == index && last {
          out.push(value)
        }
        out.push(
          if i == index && !last {
            add_json_value(values[i], segments, at + 1, value)
          } else {
            values[i]
          },
        )
      }
      if last && index == values.length() {
        out.push(value)
      }
      Json::array(out)
    }
    _ => node
  }
}

///|
fn apply_json_settings(
  document : Json,
  config : Config,
) -> Json raise OpenApiError {
  let mut result = if config.substitutions.is_empty() {
    document
  } else {
    substitute_json(document, config.substitutions)
  }
  for pointer, value in config.json_add {
    let pointer = DocumentPointer::parse(pointer)
    result = add_json_value(result, pointer.segments, 0, value)
  }
  guard result is Object(_) else {
    raise InvalidConfiguration(
      "OpenAPI jsonAdd must preserve an object document",
    )
  }
  result
}

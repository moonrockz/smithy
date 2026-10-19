///|
fn recursion_cycles(
  model : Model,
  graph : Map[ShapeId, Array[ShapeId]],
  start : Shape,
) -> Array[String] {
  let paths : Array[String] = []
  let pending : Array[(ShapeId, Array[ShapeId])] = [(start.id, [])]
  while pending.pop() is Some((current, path)) {
    for neighbor in graph.get(current).unwrap_or([]) {
      let next = path.copy()
      next.push(neighbor)
      if neighbor == start.id {
        paths.push(next.map(id => id.to_string()).join(" > "))
      } else if !path.contains(neighbor) && model.shapes.contains(neighbor) {
        pending.push((neighbor, next))
      }
    }
  }
  paths
}

///|
fn recursion_union_terminates(model : Model, union : Shape) -> Bool {
  let seen : Map[ShapeId, Bool] = Map([])
  let pending = [union.id]
  while pending.pop() is Some(current) {
    if seen.contains(current) {
      continue
    }
    seen[current] = true
    guard model.shapes.get(current) is Some(shape) else { continue }
    match shape.body {
      Union(members) => pending.append(members)
      Structure(members) => {
        if members.is_empty() ||
          members
          .iter()
          .any(id => {
            model.shapes
            .get(id)
            .map(member_ => member_.trait_value("smithy.api#required") is None)
            .unwrap_or(false)
          }) {
          return true
        }
        pending.append(members)
      }
      Member(target~) => pending.push(target)
      _ => return true
    }
  }
  false
}

///|
fn Model::shape_recursion_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let collection_graph : Map[ShapeId, Array[ShapeId]] = Map([])
  let required_graph : Map[ShapeId, Array[ShapeId]] = Map([])
  for edge in selector_edges(self) {
    if edge.label == "trait" {
      continue
    }
    guard self.shapes.get(edge.from) is Some(from) &&
      self.shapes.get(edge.to) is Some(to) else {
      continue
    }
    if edge.label == "mixin" && from.body is Member(..) {
      continue
    }
    if !(from.body is Structure(_) || from.body is Union(_)) {
      collection_graph.get_or_init(edge.from, () => []).push(edge.to)
    }
    if (
        from.body is Structure(_) &&
        to.trait_value("smithy.api#required") is Some(_)
      ) ||
      from.body is Member(..) {
      required_graph.get_or_init(edge.from, () => []).push(edge.to)
    }
  }
  for _, shape in self.shapes {
    match shape.body {
      List(_) | Map(..) =>
        for path in recursion_cycles(self, collection_graph, shape) {
          events.push(
            validation_event(
              "ShapeRecursion",
              "ERROR",
              Some(shape),
              "Found invalid shape recursion: " +
              path +
              ". A recursive list, set, or map shape is only valid if an intermediate reference is through a union or structure.",
            ),
          )
        }
      Structure(_) =>
        for path in recursion_cycles(self, required_graph, shape) {
          events.push(
            validation_event(
              "ShapeRecursion",
              "ERROR",
              Some(shape),
              "Found invalid shape recursion: " +
              path +
              ". A structure cannot be mutually recursive through all required members.",
            ),
          )
        }
      Union(members) =>
        if !members.is_empty() && !recursion_union_terminates(self, shape) {
          events.push(
            validation_event(
              "ShapeRecursion",
              "ERROR",
              Some(shape),
              "It is impossible to create instances of this recursive union",
            ),
          )
        }
      _ => ()
    }
  }
  events
}

///|
fn Model::enum_trait_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  for _, shape in self.shapes {
    guard shape.trait_value("smithy.api#enum") is Some(Array(definitions)) else {
      continue
    }
    let values : Map[String, Bool] = Map([])
    let names : Map[String, Bool] = Map([])
    for definition in definitions {
      if validation_string(definition, "value") is Some(value) {
        if values.contains(value) {
          events.push(
            validation_event(
              "EnumTrait",
              "ERROR",
              Some(shape),
              "Duplicate enum trait values found with the same `value` property of '" +
              value +
              "'",
            ),
          )
        }
        values[value] = true
      }
    }
    for definition in definitions {
      if validation_string(definition, "name") is Some(name) {
        if names.contains(name) {
          events.push(
            validation_event(
              "EnumTrait",
              "ERROR",
              Some(shape),
              "Duplicate enum trait values found with the same `name` property of '" +
              name +
              "'",
            ),
          )
        }
        names[name] = true
        let chars = name.to_array()
        let recommended = !chars.is_empty() &&
          chars[0] >= 'A' &&
          chars[0] <= 'Z' &&
          chars
          .iter()
          .all(c => (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')
        if !recommended {
          events.push(
            validation_event(
              "EnumTrait." + name,
              "WARNING",
              Some(shape),
              "The name `" +
              name +
              "` does not match the recommended enum name format of beginning with an uppercase letter, followed by any number of uppercase letters, numbers, or underscores.",
            ),
          )
        }
      }
    }
    if names.is_empty() {
      events.push(
        validation_event(
          "EnumNamesPresent",
          "WARNING",
          Some(shape),
          "Enums should define the `name` property to allow rich types to be generated in code generators.",
        ),
      )
    } else {
      for definition in definitions {
        if validation_string(definition, "name") is None &&
          validation_string(definition, "value") is Some(value) {
          events.push(
            validation_event(
              "EnumTrait",
              "ERROR",
              Some(shape),
              "`" +
              value +
              "` enum value body is missing the `name` property; if any enum trait value contains a `name` property, then all values must contain the `name` property.",
            ),
          )
        }
      }
    }
  }
  events
}

///|
priv struct MediaTypeParser {
  chars : Array[Char]
  mut pos : Int32
}

///|
fn media_type_token(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  "!#$%&'*+-.^_`|~".contains(c.to_string())
}

///|
fn MediaTypeParser::token(self : MediaTypeParser) -> Bool {
  let start = self.pos
  while self.pos < self.chars.length() && media_type_token(self.chars[self.pos]) {
    self.pos += 1
  }
  self.pos > start
}

///|
fn MediaTypeParser::take(self : MediaTypeParser, c : Char) -> Bool {
  if self.pos < self.chars.length() && self.chars[self.pos] == c {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn MediaTypeParser::ws(self : MediaTypeParser) -> Unit {
  while self.pos < self.chars.length() &&
        (
          self.chars[self.pos] == ' ' ||
          self.chars[self.pos] == '\t' ||
          self.chars[self.pos] == '\n' ||
          self.chars[self.pos] == '\r'
        ) {
    self.pos += 1
  }
}

///|
fn valid_media_type(value : String) -> Bool {
  let parser : MediaTypeParser = { chars: value.to_array(), pos: 0, }
  if !parser.token() || !parser.take('/') || !parser.token() {
    return false
  }
  parser.ws()
  while parser.pos < parser.chars.length() {
    if !parser.take(';') {
      return false
    }
    parser.ws()
    if !parser.token() || !parser.take('=') {
      return false
    }
    if parser.take('"') {
      let mut closed = false
      while parser.pos < parser.chars.length() {
        if parser.take('"') {
          closed = true
          break
        }
        if parser.take('\\') && parser.pos == parser.chars.length() {
          return false
        }
        parser.pos += 1
      }
      if !closed {
        return false
      }
    } else if !parser.token() {
      return false
    }
    parser.ws()
  }
  true
}

///|
fn valid_namespace_uri(uri : String) -> Bool {
  let chars = uri.to_array()
  for i, c in chars {
    if c <= ' ' || "<>\"{}|\\^`".contains(c.to_string()) {
      return false
    }
    if c == '%' {
      if i + 2 >= chars.length() {
        return false
      }
      for j in [i + 1, i + 2] {
        let c = chars[j]
        if !((c >= '0' && c <= '9') ||
          (c >= 'a' && c <= 'f') ||
          (c >= 'A' && c <= 'F')) {
          return false
        }
      }
    }
  }
  let fragments = uri.split("#").to_array()
  if fragments.length() > 2 {
    return false
  }
  let main = fragments[0].to_owned()
  let before_query = main.split("?").to_array()[0].to_owned()
  let first = before_query.split("/").to_array()[0].to_owned()
  let mut relative = before_query
  if first.find(":") is Some(colon) {
    let scheme = first[:colon].to_owned().to_array()
    if scheme.is_empty() ||
      !((scheme[0] >= 'a' && scheme[0] <= 'z') ||
      (scheme[0] >= 'A' && scheme[0] <= 'Z')) {
      return false
    }
    if !scheme
      .iter()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '+' ||
        c == '-' ||
        c == '.'
      }) {
      return false
    }
    if main.length() == colon + 1 {
      return false
    }
    // Opaque URIs have no hierarchical path to validate.
    if !main[colon + 1:].has_prefix("/") {
      return true
    }
    relative = before_query[colon + 1:].to_owned()
  }
  if relative.has_prefix("//") {
    let authority_and_path = relative[2:].to_owned()
    let authority_end = authority_and_path
      .find("/")
      .unwrap_or(authority_and_path.length())
    let authority = authority_and_path[:authority_end].to_owned()
    relative = authority_and_path[authority_end:].to_owned()
    if authority.is_empty() && relative.is_empty() && main == before_query {
      return false
    }
    let host = authority.split("@").to_array().last().unwrap().to_owned()
    if host.contains("[") || host.contains("]") {
      if !host.has_prefix("[") {
        return false
      }
      guard host.find("]") is Some(end) else { return false }
      let address = host[1:end].to_owned()
      if !address.contains(":") ||
        address.contains("[") ||
        host[end + 1:].contains("]") ||
        host[end + 1:].contains("[") {
        return false
      }
      let suffix = host[end + 1:].to_owned()
      if !suffix.is_empty() &&
        (
          !suffix.has_prefix(":") ||
          !suffix[1:].iter().all(c => c >= '0' && c <= '9')
        ) {
        return false
      }
    }
  }
  !relative.contains("[") && !relative.contains("]")
}

///|
fn Model::recursion_and_format_events(self : Model) -> Array[ValidationEvent] {
  let events = self.shape_recursion_events()
  events.append(self.enum_trait_events())
  for _, shape in self.shapes {
    if shape.trait_value("smithy.api#mediaType") is Some(String(value)) &&
      !valid_media_type(value) {
      events.push(
        validation_event(
          "MediaType",
          "ERROR",
          Some(shape),
          "Invalid mediaType value, \"" +
          value +
          "\": Invalid media type syntax",
        ),
      )
    }
    if shape.trait_value("smithy.api#xmlNamespace") is Some(config) &&
      validation_string(config, "uri") is Some(uri) &&
      !valid_namespace_uri(uri) {
      events.push(
        validation_event(
          "XmlNamespaceTrait",
          "ERROR",
          Some(shape),
          "An `xmlNamespace` trait is applied to the (" +
          shape.body.keyword() +
          ": `" +
          shape.id.to_string() +
          "`) shape with an invalid uri: " +
          uri,
        ),
      )
    }
  }
  events
}

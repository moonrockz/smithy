///|
pub(all) suberror SelectorError {
  InvalidSelector(String)
} derive(Eq, Debug)

///|
pub(all) enum SelectorStep {
  ShapeType(String)
  AnyShape
  Attribute(Array[String], String?, Array[String], Bool)
  ScopedAttribute(Array[String], Array[ScopedAssertion])
  Neighbor(String, Array[String])
  Function(String, Array[Array[SelectorStep]])
  VariableStore(String, Array[SelectorStep])
  VariableGet(String)
} derive(Eq, Debug)

///|
pub(all) enum ScopedValue {
  Literal(String)
  Path(Array[String])
} derive(Eq, Debug)

///|
pub(all) struct ScopedAssertion {
  left : ScopedValue
  operator : String
  right : Array[ScopedValue]
  insensitive : Bool
} derive(Eq, Debug)

///|
pub(all) struct Selector {
  source : String
  steps : Array[SelectorStep]
} derive(Eq, Debug)

///|
priv struct SelectorParser {
  chars : Array[Char]
  mut pos : Int32
  mut depth : Int32
}

///|
fn SelectorParser::peek(self : SelectorParser) -> Char {
  if self.pos < self.chars.length() {
    self.chars[self.pos]
  } else {
    '\u{0}'
  }
}

///|
fn SelectorParser::take(self : SelectorParser) -> Char {
  let value = self.peek()
  if value != '\u{0}' {
    self.pos += 1
  }
  value
}

///|
fn SelectorParser::space(self : SelectorParser) -> Unit {
  while self.peek() == ' ' ||
        self.peek() == '\n' ||
        self.peek() == '\r' ||
        self.peek() == '\t' {
    self.pos += 1
  }
}

///|
fn SelectorParser::expect(
  self : SelectorParser,
  character : Char,
) -> Unit raise SelectorError {
  if self.take() != character {
    raise InvalidSelector(
      "I expected '\{character}' at selector offset \{self.pos}.",
    )
  }
}

///|
fn selector_identifier_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

///|
fn selector_type_known(keyword : String) -> Bool {
  [
    "blob", "boolean", "string", "byte", "short", "integer", "long", "float", "double",
    "bigInteger", "bigDecimal", "timestamp", "document", "list", "set", "map", "structure",
    "union", "enum", "intEnum", "service", "resource", "operation", "member", "number",
    "simpleType", "collection", "aggregateType", "serviceType", "dataType",
  ].contains(keyword)
}

///|
fn SelectorParser::identifier(
  self : SelectorParser,
) -> String raise SelectorError {
  let start = self.pos
  while selector_identifier_char(self.peek()) {
    self.pos += 1
  }
  if self.pos == start {
    raise InvalidSelector(
      "I expected an identifier at selector offset \{start}.",
    )
  }
  String::from_array(self.chars[start:self.pos])
}

///|
fn SelectorParser::path_segment(
  self : SelectorParser,
) -> String raise SelectorError {
  let start = self.pos
  while selector_identifier_char(self.peek()) ||
        self.peek() == '.' ||
        self.peek() == '#' {
    self.pos += 1
  }
  if self.pos == start {
    raise InvalidSelector(
      "I expected an attribute path segment at selector offset \{start}.",
    )
  }
  String::from_array(self.chars[start:self.pos])
}

///|
fn SelectorParser::selector_path(
  self : SelectorParser,
) -> Array[String] raise SelectorError {
  let parts : Array[String] = []
  while true {
    if self.peek() == '(' {
      self.take() |> ignore
      let name = self.identifier()
      self.expect(')')
      parts.push("(" + name + ")")
    } else {
      parts.push(self.path_segment())
    }
    if self.peek() != '|' {
      break
    }
    self.take() |> ignore
  }
  parts
}

///|
fn SelectorParser::value(self : SelectorParser) -> String raise SelectorError {
  self.space()
  if self.peek() == '"' || self.peek() == '\'' {
    let quote = self.take()
    let start = self.pos
    while self.peek() != quote && self.peek() != '\u{0}' {
      if self.peek() == '\\' && self.pos + 1 < self.chars.length() {
        self.pos += 1
      }
      self.pos += 1
    }
    let value = String::from_array(self.chars[start:self.pos])
    self.expect(quote)
    return value
  }
  let start = self.pos
  while self.peek() != '\u{0}' &&
        self.peek() != ',' &&
        self.peek() != ']' &&
        self.peek() != ' ' &&
        self.peek() != '\n' &&
        self.peek() != '\r' {
    self.pos += 1
  }
  if self.pos == start {
    raise InvalidSelector(
      "I expected an attribute value at selector offset \{start}.",
    )
  }
  String::from_array(self.chars[start:self.pos])
}

///|
fn SelectorParser::attribute(
  self : SelectorParser,
) -> SelectorStep raise SelectorError {
  let path = self.attribute_path()
  self.space()
  if self.peek() == ']' {
    self.take() |> ignore
    return Attribute(path, None, [], false)
  }
  let first = self.take()
  let operator = match first {
    '=' => "="
    '!' | '^' | '$' | '*' | '?' => {
      self.expect('=')
      first.to_string() + "="
    }
    '>' | '<' =>
      if self.peek() == '=' {
        self.take() |> ignore
        first.to_string() + "="
      } else {
        first.to_string()
      }
    _ =>
      raise InvalidSelector(
        "I expected an attribute comparator at selector offset \{self.pos}.",
      )
  }
  self.space()
  if self.peek() == '=' {
    raise InvalidSelector("I found a repeated attribute comparator.")
  }
  let values = [self.value()]
  self.space()
  while self.peek() == ',' {
    self.take() |> ignore
    values.push(self.value())
    self.space()
  }
  let insensitive = self.peek() == 'i'
  if insensitive {
    self.take() |> ignore
    self.space()
  }
  self.expect(']')
  Attribute(path, Some(operator), values, insensitive)
}

///|
fn SelectorParser::attribute_path(
  self : SelectorParser,
) -> Array[String] raise SelectorError {
  let path : Array[String] = [self.identifier()]
  while self.peek() == '|' {
    self.take() |> ignore
    if self.peek() == '(' {
      self.take() |> ignore
      let function_name = self.identifier()
      self.expect(')')
      path.push("(" + function_name + ")")
    } else if self.peek() == '"' || self.peek() == '\'' {
      path.push(self.value())
    } else {
      path.push(self.path_segment())
    }
  }
  path
}

///|
fn SelectorParser::scoped_value(
  self : SelectorParser,
) -> ScopedValue raise SelectorError {
  self.space()
  if self.peek() == '@' {
    self.take() |> ignore
    self.expect('{')
    let path = self.selector_path()
    self.expect('}')
    Path(path)
  } else {
    Literal(self.value())
  }
}

///|
fn SelectorParser::scoped_assertion(
  self : SelectorParser,
) -> ScopedAssertion raise SelectorError {
  let left = self.scoped_value()
  self.space()
  let first = self.take()
  let operator = match first {
    '=' => "="
    '!' | '^' | '$' | '*' | '?' => {
      self.expect('=')
      first.to_string() + "="
    }
    '>' | '<' =>
      if self.peek() == '=' {
        self.take() |> ignore
        first.to_string() + "="
      } else {
        first.to_string()
      }
    '{' => {
      let start = self.pos
      while self.peek() != '}' && self.peek() != '\u{0}' {
        self.take() |> ignore
      }
      let token = String::from_array(self.chars[start:self.pos])
      self.expect('}')
      "{" + token + "}"
    }
    _ =>
      raise InvalidSelector(
        "I expected a scoped comparator at offset \{self.pos}.",
      )
  }
  let right = [self.scoped_value()]
  self.space()
  while self.peek() == ',' {
    self.take() |> ignore
    right.push(self.scoped_value())
    self.space()
  }
  let insensitive = self.peek() == 'i'
  if insensitive {
    self.take() |> ignore
    self.space()
  }
  { left, operator, right, insensitive, }
}

///|
fn SelectorParser::scoped_attribute(
  self : SelectorParser,
) -> SelectorStep raise SelectorError {
  let scope = if self.peek() == ':' { [] } else { self.attribute_path() }
  self.expect(':')
  let assertions = [self.scoped_assertion()]
  self.space()
  while self.peek() == '&' {
    self.expect('&')
    self.expect('&')
    assertions.push(self.scoped_assertion())
    self.space()
  }
  self.expect(']')
  ScopedAttribute(scope, assertions)
}

///|
fn SelectorParser::labels(
  self : SelectorParser,
) -> Array[String] raise SelectorError {
  let labels = [self.identifier()]
  self.space()
  while self.peek() == ',' {
    self.take() |> ignore
    self.space()
    labels.push(self.identifier())
    self.space()
  }
  self.expect(']')
  labels
}

///|
fn SelectorParser::function_(
  self : SelectorParser,
) -> SelectorStep raise SelectorError {
  let name = self.identifier()
  self.space()
  self.expect('(')
  let args : Array[Array[SelectorStep]] = []
  self.space()
  if self.peek() != ')' {
    args.push(self.sequence())
    while self.peek() == ',' {
      self.take() |> ignore
      args.push(self.sequence())
    }
  }
  self.expect(')')
  if args.is_empty() ||
    (["not", "in", "root", "recursive"].contains(name) && args.length() != 1) ||
    (name == "topdown" && (args.is_empty() || args.length() > 2)) ||
    (["is", "each", "test"].contains(name) && args.is_empty()) {
    raise InvalidSelector("I found the wrong number of arguments for :\{name}.")
  }
  Function(name, args)
}

///|
fn SelectorParser::variable(
  self : SelectorParser,
) -> SelectorStep raise SelectorError {
  self.space()
  if self.peek() == '{' {
    self.take() |> ignore
    self.space()
    let name = self.identifier()
    self.space()
    self.expect('}')
    return VariableGet(name)
  }
  let name = self.identifier()
  self.space()
  self.expect('(')
  let selector = self.sequence()
  self.expect(')')
  VariableStore(name, selector)
}

///|
fn SelectorParser::step(
  self : SelectorParser,
) -> SelectorStep raise SelectorError {
  self.space()
  match self.take() {
    '*' => AnyShape
    '[' =>
      if self.peek() == '@' {
        self.take() |> ignore
        self.scoped_attribute()
      } else {
        self.attribute()
      }
    ':' => self.function_()
    '$' => self.variable()
    '>' => Neighbor(">", [])
    '<' =>
      if self.peek() == '-' {
        self.take() |> ignore
        self.expect('[')
        let labels = self.labels()
        self.expect('-')
        Neighbor("<-", labels)
      } else {
        Neighbor("<", [])
      }
    '~' => {
      self.expect('>')
      Neighbor("~>", [])
    }
    '-' => {
      self.expect('[')
      let labels = self.labels()
      self.expect('-')
      self.expect('>')
      Neighbor("->", labels)
    }
    '\u{0}' =>
      raise InvalidSelector(
        "I found the end of the selector where a step was required.",
      )
    other => {
      self.pos -= 1
      if selector_identifier_char(other) {
        let keyword = self.identifier()
        if !selector_type_known(keyword) {
          raise InvalidSelector("I found unknown shape type \{keyword}.")
        }
        ShapeType(keyword)
      } else {
        raise InvalidSelector(
          "I found unexpected selector character '\{other}'.",
        )
      }
    }
  }
}

///|
fn SelectorParser::sequence(
  self : SelectorParser,
) -> Array[SelectorStep] raise SelectorError {
  self.depth += 1
  if self.depth > 100 {
    raise InvalidSelector("I found more than 100 nested selectors.")
  }
  self.space()
  let steps : Array[SelectorStep] = []
  while self.peek() != '\u{0}' && self.peek() != ',' && self.peek() != ')' {
    steps.push(self.step())
    self.space()
  }
  self.depth -= 1
  if steps.is_empty() {
    raise InvalidSelector("I expected a selector step at offset \{self.pos}.")
  }
  steps
}

///|
pub fn Selector::parse(source : String) -> Selector raise SelectorError {
  let parser : SelectorParser = { chars: source.to_array(), pos: 0, depth: 0, }
  let steps = parser.sequence()
  parser.space()
  if parser.peek() != '\u{0}' {
    raise InvalidSelector(
      "I found unexpected selector text at offset \{parser.pos}.",
    )
  }
  { source, steps, }
}

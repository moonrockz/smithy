///|
priv struct Parser {
  source : String
  tokens : Array[Token]
  mut pos : Int32
  mut depth : Int32
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[self.pos]
}

///|
fn Parser::take(self : Parser) -> Token {
  let token = self.peek()
  if self.pos < self.tokens.length() - 1 {
    self.pos += 1
  }
  token
}

///|
fn[T] Parser::expected(
  self : Parser,
  construct : String,
) -> T raise JmespathError {
  let token = self.peek()
  let found = if token.tag == "eof" {
    "end of expression"
  } else {
    Json::string(token.text).stringify()
  }
  raise JmespathError({
    code: Syntax,
    span: token.span,
    message: "I expected \{construct}, but found \{found}.",
  })
}

///|
fn Parser::expect(self : Parser, tag : String) -> Token raise JmespathError {
  if self.peek().tag != tag {
    return self.expected(tag)
  }
  self.take()
}

///|
fn binding(tag : String) -> Int32 {
  match tag {
    "|" => 1
    "||" => 2
    "&&" => 3
    "==" | "!=" | "<" | "<=" | ">" | ">=" => 5
    "[]" => 9
    "*" => 20
    "[?" => 21
    "." => 40
    "!" => 45
    "{" => 50
    "[" => 55
    "(" => 60
    _ => 0
  }
}

///|
/// Index magnitudes beyond an addressable array are equivalent to its bounds.
fn Parser::integer(self : Parser) -> Int32 raise JmespathError {
  let token = self.expect("number")
  let n = @string.parse_double(token.text) catch {
    _ => {
      problem(
        Syntax,
        token.span,
        "I expected an integer index, but found \{token.text}.",
      )
      0.0
    }
  }
  n.clamp(min=-2147483647.0, max=2147483647.0).to_int()
}

///|
fn Parser::projection_rhs(
  self : Parser,
  power : Int32,
) -> Node raise JmespathError {
  match self.peek().tag {
    "[" | "[?" => self.expression(power)
    "." => {
      self.take() |> ignore
      self.dot_rhs(power)
    }
    tag if binding(tag) < 10 =>
      node(Identity, self.peek().span.start, self.peek().span.start)
    _ => self.expected("a projection continuation")
  }
}

///|
fn Parser::dot_rhs(self : Parser, power : Int32) -> Node raise JmespathError {
  match self.peek().tag {
    "identifier" | "quoted" | "*" => self.expression(power)
    "[" => {
      let t = self.take()
      self.multi_list(t.span.start)
    }
    "{" => {
      let t = self.take()
      self.multi_hash(t.span.start)
    }
    _ => self.expected("an identifier, wildcard or multi-select after '.'")
  }
}

///|
fn Parser::multi_list(self : Parser, start : Int32) -> Node raise JmespathError {
  let children = [self.expression(0)]
  while self.peek().tag == "," {
    self.take() |> ignore
    children.push(self.expression(0))
  }
  let end = self.expect("]").span.end
  node(MultiList(children), start, end)
}

///|
fn Parser::multi_hash(self : Parser, start : Int32) -> Node raise JmespathError {
  let children = []
  while true {
    let token = self.peek()
    let name = match (token.tag, token.value) {
      ("identifier", _) => token.text
      ("quoted", String(s)) => s
      _ => self.expected("an object key")
    }
    self.take() |> ignore
    self.expect(":") |> ignore
    children.push((name, self.expression(0)))
    if self.peek().tag != "," {
      break
    }
    self.take() |> ignore
  }
  let end = self.expect("}").span.end
  node(MultiHash(children), start, end)
}

///|
fn Parser::bracket(self : Parser, left : Node) -> Node raise JmespathError {
  if self.peek().tag == "*" {
    self.take() |> ignore
    let close = self.expect("]")
    let right = self.projection_rhs(20)
    return node(
      Projection(left, right),
      left.span.start,
      close.span.end.max(right.span.end),
    )
  }
  let start = if self.peek().tag == "number" {
    Some(self.integer())
  } else {
    None
  }
  if self.peek().tag == "]" && start is Some(index) {
    let close = self.take()
    return node(Index(left, index), left.span.start, close.span.end)
  }
  self.expect(":") |> ignore
  let stop = if self.peek().tag == "number" {
    Some(self.integer())
  } else {
    None
  }
  let step = if self.peek().tag == ":" {
    self.take() |> ignore
    if self.peek().tag == "number" {
      Some(self.integer())
    } else {
      None
    }
  } else {
    None
  }
  let close = self.expect("]")
  let slice = node(
    Slice(left, start, stop, step),
    left.span.start,
    close.span.end,
  )
  let right = self.projection_rhs(20)
  node(
    Projection(slice, right),
    left.span.start,
    close.span.end.max(right.span.end),
  )
}

///|
fn Parser::filter(self : Parser, left : Node) -> Node raise JmespathError {
  let predicate = self.expression(0)
  let close = self.expect("]")
  let right = self.projection_rhs(21)
  node(
    Filter(left, predicate, right),
    left.span.start,
    close.span.end.max(right.span.end),
  )
}

///|
fn Parser::prefix(self : Parser) -> Node raise JmespathError {
  let token = self.take()
  let start = token.span.start
  let identity = node(Identity, start, token.span.end)
  match token.tag {
    "identifier" => node(Field(token.text), start, token.span.end)
    "quoted" =>
      match token.value {
        String(s) => node(Field(s), start, token.span.end)
        _ => self.expected("a quoted identifier")
      }
    "literal" => node(Literal(token.value), start, token.span.end)
    "@" => identity
    "!" => {
      let right = self.expression(45)
      node(Not(right), start, right.span.end)
    }
    "(" => {
      let inner = self.expression(0)
      let close = self.expect(")")
      node(inner.kind, start, close.span.end)
    }
    "*" => {
      let right = self.projection_rhs(20)
      node(
        ObjectProjection(identity, right),
        start,
        token.span.end.max(right.span.end),
      )
    }
    "[]" => {
      let flat = node(Flatten(identity), start, token.span.end)
      let right = self.projection_rhs(9)
      node(Projection(flat, right), start, token.span.end.max(right.span.end))
    }
    "[?" => self.filter(identity)
    "[" =>
      if self.peek().tag == "number" ||
        self.peek().tag == ":" ||
        (self.peek().tag == "*" && self.tokens[self.pos + 1].tag == "]") {
        self.bracket(identity)
      } else {
        self.multi_list(start)
      }
    "{" => self.multi_hash(start)
    _ => {
      let found = if token.tag == "eof" {
        "end of expression"
      } else {
        Json::string(token.text).stringify()
      }
      raise JmespathError({
        code: Syntax,
        span: token.span,
        message: "I expected a JMESPath expression, but found \{found}.",
      })
    }
  }
}

///|
fn Parser::infix(self : Parser, left : Node) -> Node raise JmespathError {
  let token = self.take()
  let start = left.span.start
  match token.tag {
    "." =>
      if self.peek().tag == "*" {
        let star = self.take()
        let right = self.projection_rhs(40)
        node(
          ObjectProjection(left, right),
          start,
          star.span.end.max(right.span.end),
        )
      } else {
        let right = self.dot_rhs(40)
        node(Subexpression(left, right), start, right.span.end)
      }
    "[" => self.bracket(left)
    "[?" => self.filter(left)
    "[]" => {
      let flat = node(Flatten(left), start, token.span.end)
      let right = self.projection_rhs(9)
      node(Projection(flat, right), start, token.span.end.max(right.span.end))
    }
    "(" => {
      guard left.kind is Field(name) &&
        self.source[left.span.start:left.span.end] == name else {
        let found = Json::string(
          self.source[left.span.start:left.span.end].to_owned(),
        ).stringify()
        raise JmespathError({
          code: Syntax,
          span: left.span,
          message: "I expected an unquoted JMESPath function name, but found \{found}.",
        })
      }
      let args = []
      if self.peek().tag != ")" {
        while true {
          let arg = if self.peek().tag == "&" {
            let amp = self.take()
            let expr = self.expression(0)
            node(ExpressionRef(expr), amp.span.start, expr.span.end)
          } else {
            self.expression(0)
          }
          args.push(arg)
          if self.peek().tag != "," {
            break
          }
          self.take() |> ignore
        }
      }
      let close = self.expect(")")
      node(Function(name, args), start, close.span.end)
    }
    "|" | "||" | "&&" | "==" | "!=" | "<" | "<=" | ">" | ">=" => {
      let op = match token.tag {
        "|" => Pipe
        "||" => Or
        "&&" => And
        "==" => Equal
        "!=" => NotEqual
        "<" => Less
        "<=" => LessEqual
        ">" => Greater
        _ => GreaterEqual
      }
      let right = self.expression(binding(token.tag))
      node(Binary(op, left, right), start, right.span.end)
    }
    _ => self.expected("an operator or expression continuation")
  }
}

///|
fn Parser::expression(self : Parser, power : Int32) -> Node raise JmespathError {
  if self.depth >= 256 {
    return self.expected("an expression nested at most 256 levels deep")
  }
  self.depth += 1
  let mut left = self.prefix()
  while binding(self.peek().tag) > power {
    left = self.infix(left)
  }
  self.depth -= 1
  left
}

///|
/// Parse a standard JMESPath expression. Errors carry offsets into source.
pub fn parse(source : String) -> Expression raise JmespathError {
  let parser : Parser = { source, tokens: lex(source), pos: 0, depth: 0, }
  let root = parser.expression(0)
  parser.expect("eof") |> ignore
  { source, root, }
}

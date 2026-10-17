///|
/// Reindent and space tokens while retaining line breaks, comments, commas,
/// and exact literal spellings. In particular text-block indentation is data.
struct Layout {
  out : StringBuilder
  mut indent : Int32
  mut breaks : Int32
  mut started : Bool
  mut previous : @syntax.TokenKind?
  mut separated : Bool
}

///|
fn Layout::flush(self : Layout) -> Unit {
  if self.breaks > 0 {
    if self.started {
      self.out.write_string("\n".repeat(Int32::min(self.breaks, 2)))
    }
    self.out.write_string("    ".repeat(Int32::max(self.indent, 0)))
    self.breaks = 0
    self.previous = None
    self.separated = true
  }
}

///|
fn Layout::trivia(self : Layout, trivia : ArrayView[@syntax.Trivia]) -> Unit {
  for item in trivia {
    match item {
      Newline(_, _) => self.breaks += 1
      Whitespace(_, _) => ()
      Comma(_) => {
        self.out.write_string(",")
        self.separated = false
        self.previous = None
      }
      Comment(_) => {
        let same_line = self.breaks == 0 && self.started
        self.flush()
        if same_line {
          self.out.write_string(" ")
        }
        self.out.write_string(item.text())
        self.started = true
        self.breaks = 0
        self.previous = None
        self.separated = true
      }
    }
  }
}

///|
fn spaced(previous : @syntax.TokenKind?, current : @syntax.TokenKind) -> Bool {
  match (previous, current) {
    (_, Dot | Pound | Colon | RParen | RBracket) => false
    (Some(At | Dot | Pound | Dollar | LParen | LBracket), _) => false
    (_, LParen) => false
    (Some(LBrace), RBrace) => false
    (_, _) => true
  }
}

///|
fn format_idl(parsed : @syntax.ParseResult) -> String {
  let layout : Layout = {
    out: StringBuilder(),
    indent: 0,
    breaks: 1,
    started: false,
    previous: None,
    separated: true,
  }
  layout.trivia(parsed.cst.trivia)
  for token in parsed.cst.tokens {
    layout.trivia(token.trivia_before)
    if token.kind is (RBrace | RBracket | RParen) {
      layout.indent -= 1
    }
    let new_line = layout.breaks > 0
    layout.flush()
    if !new_line &&
      layout.started &&
      !layout.separated &&
      spaced(layout.previous, token.kind) {
      layout.out.write_string(" ")
    }
    layout.out.write_string(token.lexeme)
    layout.started = true
    layout.separated = false
    layout.previous = Some(token.kind)
    if token.kind is (LBrace | LBracket | LParen) {
      layout.indent += 1
    }
    layout.trivia(token.trivia_after)
  }
  let text = layout.out.to_string()
  if text.is_empty() {
    ""
  } else {
    text + "\n"
  }
}

///|
fn format_text(
  text : String,
  name : String,
  format : String,
) -> String raise CliError {
  if format == "json" {
    let ast = @syntax.parse_json_ast(text) catch {
      error => raise CliError("\{name}: \{error}", 1)
    }
    return @syntax.encode_json_ast(ast).stringify(indent=4) + "\n"
  }
  let source = @syntax.SourceText::new(text, name~)
  let parsed = @syntax.parse(source)
  if parsed.has_errors() {
    let messages = parsed.diagnostics.map(d => @syntax.render_short(d, source))
    raise CliError(messages.join("\n"), 1)
  }
  format_idl(parsed)
}

///|
/// A formatter of a template. A built-in formatter returns the text, or the
/// problem phrase when it cannot format the value; `render` makes the full
/// error from the phrase. A custom formatter raises its own errors, and `render`
/// does not change them.
priv enum Formatter {
  Builtin((TemplateValue) -> Result[String, String])
  Custom((CodeWriter, TemplateValue) -> String raise CodegenError)
}

///|
/// The part of the writer that `push_state` copies and `pop_state` restores.
priv struct WriterState {
  mut indent_level : Int32
  mut newline_prefix : String
  context : Map[String, TemplateValue]
  formatters : Map[Char, Formatter]
}

///|
fn WriterState::copy(self : WriterState) -> WriterState {
  {
    indent_level: self.indent_level,
    newline_prefix: self.newline_prefix,
    context: self.context.copy(),
    formatters: self.formatters.copy(),
  }
}

///|
/// A writer of generated code. It keeps the output, the indentation, a stack of
/// states (indentation, newline prefix, context and formatters) and the formatters.
#warnings("-unused_field")
pub struct CodeWriter {
  priv namespace : Namespace
  priv indent_text : String
  priv imports : ImportTracker
  // The stack of output buffers. The last one takes the output. A capture of
  // text can push a buffer and pop it later.
  priv buffers : Array[StringBuilder]
  priv mut at_line_start : Bool
  // The stack of states. The last one is the current state.
  priv states : Array[WriterState]
}

///|
fn format_literal(value : TemplateValue) -> Result[String, String] {
  match value {
    Text(text) => Ok(text)
    Int(number) => Ok(number.to_string())
    Bool(flag) => Ok(flag.to_string())
    Null => Ok("")
    Sym(symbol) => Ok(symbol.full_name())
    Ref(_) => Err("a value that `L` cannot format: a reference")
    Call(_) => Err("a value that `L` cannot format: a function")
    List(_) => Err("a value that `L` cannot format: a list")
    Record(_) => Err("a value that `L` cannot format: a record")
  }
}

///|
pub fn CodeWriter::new(
  namespace~ : Namespace = Namespace::root(),
  indent_text~ : String = "    ",
  string_literal~ : (String) -> String = json_string_literal,
) -> CodeWriter {
  let formatters : Map[Char, Formatter] = Map([])
  formatters['L'] = Builtin(format_literal)
  formatters['S'] = Builtin(value => {
    match value {
      Text(text) => Ok(string_literal(text))
      _ => Err("a value that `S` cannot format: only text")
    }
  })
  {
    namespace,
    indent_text,
    imports: ImportTracker::new(),
    buffers: [StringBuilder()],
    at_line_start: true,
    states: [
      { indent_level: 0, newline_prefix: "", context: Map([]), formatters, },
    ],
  }
}

///|
fn CodeWriter::state(self : CodeWriter) -> WriterState {
  self.states[self.states.length() - 1]
}

///|
pub fn CodeWriter::namespace(self : CodeWriter) -> Namespace {
  self.namespace
}

///|
/// Write the text. Each line gets the newline prefix and the indentation, but
/// an empty line gets nothing. `end_line` ends the last line.
fn CodeWriter::emit(self : CodeWriter, text : String, end_line : Bool) -> Unit {
  let out = self.buffers[self.buffers.length() - 1]
  let state = self.state()
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  for index, line in lines {
    if index > 0 {
      out.write_char('\n')
      self.at_line_start = true
    }
    if line.is_empty() {
      continue
    }
    if self.at_line_start {
      out.write_string(state.newline_prefix)
      for _ in 0..<state.indent_level {
        out.write_string(self.indent_text)
      }
      self.at_line_start = false
    }
    out.write_string(line)
  }
  if end_line {
    out.write_char('\n')
    self.at_line_start = true
  }
}

///|
/// Write a template and end the line. The template can have several lines.
pub fn CodeWriter::write(
  self : CodeWriter,
  template : String,
  args~ : Array[TemplateValue] = [],
) -> Unit raise CodegenError {
  let text = self.render(template, args)
  self.emit(text, true)
}

///|
/// Write a template and continue the current line. The indentation applies
/// only at the start of a line.
pub fn CodeWriter::write_inline(
  self : CodeWriter,
  template : String,
  args~ : Array[TemplateValue] = [],
) -> Unit raise CodegenError {
  let text = self.render(template, args)
  self.emit(text, false)
}

///|
/// Write an empty line.
pub fn CodeWriter::blank_line(self : CodeWriter) -> Unit {
  self.emit("", true)
}

///|
pub fn CodeWriter::indent(self : CodeWriter, levels~ : Int32 = 1) -> Unit {
  self.state().indent_level += levels
}

///|
/// Remove levels of indentation. It raises `StateError` below zero.
pub fn CodeWriter::dedent(
  self : CodeWriter,
  levels~ : Int32 = 1,
) -> Unit raise CodegenError {
  let state = self.state()
  if levels > state.indent_level {
    raise StateError(
      "I could not remove \{levels} levels of indentation: the writer has only \{state.indent_level}.",
    )
  }
  state.indent_level -= levels
}

///|
/// Write the opening line, indent, run the body, dedent and write the closing line.
pub fn CodeWriter::open_block(
  self : CodeWriter,
  open : String,
  close : String,
  args~ : Array[TemplateValue] = [],
  body : (CodeWriter) -> Unit raise CodegenError,
) -> Unit raise CodegenError {
  self.write(open, args~)
  self.indent()
  body(self)
  self.dedent()
  self.write(close)
}

///|
pub fn CodeWriter::set_newline_prefix(
  self : CodeWriter,
  prefix : String,
) -> Unit {
  self.state().newline_prefix = prefix
}

///|
pub fn CodeWriter::put_context(
  self : CodeWriter,
  name : String,
  value : TemplateValue,
) -> Unit {
  self.state().context[name] = value
}

///|
pub fn CodeWriter::get_context(
  self : CodeWriter,
  name : String,
) -> TemplateValue? {
  self.state().context.get(name)
}

///|
/// Set the formatter for a character. A template can use only the formatters
/// whose character is an uppercase ASCII letter.
pub fn CodeWriter::put_formatter(
  self : CodeWriter,
  character : Char,
  formatter : (CodeWriter, TemplateValue) -> String raise CodegenError,
) -> Unit {
  self.state().formatters[character] = Custom(formatter)
}

///|
/// Save a copy of the indentation, the newline prefix, the context and the
/// formatters. `pop_state` restores them.
pub fn CodeWriter::push_state(self : CodeWriter) -> Unit {
  self.states.push(self.state().copy())
}

///|
/// Restore the state of the last `push_state`. It raises `StateError` when
/// there is no `push_state` to undo.
pub fn CodeWriter::pop_state(self : CodeWriter) -> Unit raise CodegenError {
  if self.states.length() <= 1 {
    raise StateError(
      "I could not pop the state of the writer: I did not push one.",
    )
  }
  let _ = self.states.pop()
}

///|
/// The text that I wrote. I trim the trailing whitespace of each line and end
/// with exactly one newline. I give the empty string when nothing is there.
pub fn CodeWriter::to_string(self : CodeWriter) -> String {
  let lines : Array[String] = []
  for line in self.buffers[0].to_string().split("\n") {
    lines.push(line.trim_end(chars=" \t").to_owned())
  }
  while lines.last() is Some("") {
    let _ = lines.pop()
  }
  if lines.is_empty() {
    return ""
  }
  lines.join("\n") + "\n"
}

///|
/// Render a template to text with the arguments and the current state. It
/// writes nothing, so a bad template leaves the output as it was.
fn CodeWriter::render(
  self : CodeWriter,
  template : String,
  args : Array[TemplateValue],
) -> String raise CodegenError {
  let parsed = parse_template(template)
  let used = Array::make(args.length(), false)
  let state = self.state()
  // 0: no argument yet, 1: relative, 2: positional
  let mut mode = 0
  let mut next_relative = 0
  let out = StringBuilder()
  for token in parsed.tokens {
    match token {
      Literal(text) => out.write_string(text)
      Expr(source, name, offset) => {
        let value = match source {
          Relative => {
            if mode == 2 {
              raise template_error(
                "a relative argument mixed with positional arguments", offset, template,
              )
            }
            mode = 1
            if next_relative >= args.length() {
              raise template_error(
                "no argument for `$\{name}`",
                offset,
                template,
              )
            }
            used[next_relative] = true
            next_relative += 1
            args[next_relative - 1]
          }
          Positional(index) => {
            if mode == 1 {
              raise template_error(
                "a positional argument mixed with relative arguments", offset, template,
              )
            }
            mode = 2
            if index > args.length() {
              raise template_error(
                "no argument at position \{index} for `$\{index}\{name}`",
                offset,
                template,
              )
            }
            used[index - 1] = true
            args[index - 1]
          }
          Named(key) =>
            match state.context.get(key) {
              Some(value) => value
              None =>
                raise template_error(
                  "a name `\{key}` that has no value in the context",
                  offset,
                  template,
                )
            }
        }
        match state.formatters.get(name) {
          None =>
            raise template_error(
              "a formatter `\{name}` that does not exist",
              offset,
              template,
            )
          Some(Builtin(format)) =>
            match format(value) {
              Ok(text) => out.write_string(text)
              Err(problem) => raise template_error(problem, offset, template)
            }
          Some(Custom(format)) => out.write_string(format(self, value))
        }
      }
    }
  }
  if used.iter().any(flag => !flag) {
    let count = used.iter().filter(flag => !flag).count()
    raise template_error(
      if count == 1 {
        "an argument that the template does not use"
      } else {
        "\{count} arguments that the template does not use"
      },
      parsed.length,
      template,
    )
  }
  out.to_string()
}

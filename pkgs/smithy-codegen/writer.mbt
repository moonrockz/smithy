///|
/// A formatter of a template. A built-in formatter returns the text, or the
/// problem phrase when it cannot format the value; `render` makes the full
/// error from the phrase. The nested formatter needs a writer, so `render`
/// runs it. A custom formatter raises its own errors, and `render`
/// does not change them.
priv enum Formatter {
  Builtin((TemplateValue) -> Result[String, String])
  /// `C`: run a `Call` value on a child writer and give its text.
  Nested
  /// `T`: write a symbol, and record its imports and dependencies.
  Symbolic
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
pub struct CodeWriter {
  priv namespace : Namespace
  priv indent_text : String
  priv tracker : ImportTracker
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
  formatters['C'] = Nested
  formatters['T'] = Symbolic
  formatters['S'] = Builtin(value => {
    match value {
      Text(text) => Ok(string_literal(text))
      _ => Err("a value that `S` cannot format: only text")
    }
  })
  {
    namespace,
    indent_text,
    tracker: ImportTracker::new(),
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
/// A new writer for a nested piece of code. It has the namespace and the import
/// tracker of this writer, and a copy of its context and formatters. Its
/// indentation and newline prefix are empty.
pub fn CodeWriter::child(self : CodeWriter) -> CodeWriter {
  let state = self.state()
  {
    namespace: self.namespace,
    indent_text: self.indent_text,
    tracker: self.tracker,
    buffers: [StringBuilder()],
    at_line_start: true,
    states: [
      {
        indent_level: 0,
        newline_prefix: "",
        context: state.context.copy(),
        formatters: state.formatters.copy(),
      },
    ],
  }
}

///|
/// The variables of one loop that runs, and its place in it.
priv struct LoopFrame {
  entries : Array[(TemplateValue, TemplateValue)]
  key_name : String
  value_name : String
  mut index : Int32
  vars : Map[String, TemplateValue]
}

///|
fn LoopFrame::bind(self : LoopFrame) -> Unit {
  let (key, value) = self.entries[self.index]
  self.vars[self.key_name] = key
  self.vars[self.value_name] = value
  self.vars["\{self.key_name}.first"] = Bool(self.index == 0)
  self.vars["\{self.key_name}.last"] = Bool(
    self.index == self.entries.length() - 1,
  )
}

///|
/// The value of a name. The variables of the loops come first, the innermost
/// loop first, then the context.
fn lookup_name(
  frames : Array[LoopFrame],
  context : Map[String, TemplateValue],
  name : String,
) -> TemplateValue? {
  for i = frames.length() - 1; i >= 0; i = i - 1 {
    if frames[i].vars.get(name) is Some(value) {
      return Some(value)
    }
  }
  context.get(name)
}

///|
/// True when the name has a truthy value. A missing name is falsy.
fn name_is_truthy(
  frames : Array[LoopFrame],
  context : Map[String, TemplateValue],
  name : String,
) -> Bool {
  match lookup_name(frames, context, name) {
    Some(value) => value.is_truthy()
    None => false
  }
}

///|
fn TemplateValue::kind_name(self : TemplateValue) -> String {
  match self {
    Null => "a null value"
    Bool(_) => "a boolean"
    Int(_) => "a number"
    Text(_) => "a text"
    Sym(_) => "a symbol"
    Ref(_) => "a reference"
    Call(_) => "a function"
    List(_) => "a list"
    Record(_) => "a record"
  }
}

///|
/// Write the text to the output. When `align` is true, each line after the
/// first starts with the whitespace that starts the current line of the output.
fn write_aligned(out : StringBuilder, text : String, align : Bool) -> Unit {
  if !align || !text.contains("\n") {
    out.write_string(text)
    return
  }
  let written = out.to_string().to_array()
  let mut line_start = written.length()
  while line_start > 0 && written[line_start - 1] != '\n' {
    line_start -= 1
  }
  let prefix = StringBuilder()
  let mut at = line_start
  while at < written.length() && (written[at] == ' ' || written[at] == '\t') {
    prefix.write_char(written[at])
    at += 1
  }
  let prefix = prefix.to_string()
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  for index, line in lines {
    if index > 0 {
      out.write_char('\n')
      if !line.is_empty() {
        out.write_string(prefix)
      }
    }
    out.write_string(line)
  }
}

///|
/// Give the index of the argument of each expression of the template, or -1
/// for an expression without an argument. Relative arguments take their place
/// in the order of the expressions in the template, so a block that is not
/// rendered still uses its arguments. It marks the arguments that I use.
fn resolve_arguments(
  parsed : ParsedTemplate,
  template : String,
  args : Array[TemplateValue],
  used : Array[Bool],
) -> Array[Int32] raise CodegenError {
  let indexes : Array[Int32] = []
  // 0: no argument yet, 1: relative, 2: positional
  let mut mode = 0
  let mut next_relative = 0
  for token in parsed.tokens {
    match token {
      Expr(Relative, name, _, offset) => {
        if mode == 2 {
          raise template_error(
            "a relative argument mixed with positional arguments", offset, template,
          )
        }
        mode = 1
        if next_relative >= args.length() {
          raise template_error("no argument for `$\{name}`", offset, template)
        }
        used[next_relative] = true
        indexes.push(next_relative)
        next_relative += 1
      }
      Expr(Positional(index), name, _, offset) => {
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
        indexes.push(index - 1)
      }
      _ => indexes.push(-1)
    }
  }
  indexes
}

///|
/// Render a template to text with the arguments and the current state. It
/// writes nothing, so a bad template leaves the output as it was. It also
/// leaves the imports and the dependencies as they were when it raises.
fn CodeWriter::render(
  self : CodeWriter,
  template : String,
  args : Array[TemplateValue],
) -> String raise CodegenError {
  let mark = self.tracker.mark()
  errdefer self.tracker.rollback(mark)
  self.render_tokens(template, args)
}

///|
/// The rendering itself. It walks the tokens with an index and a stack of the
/// loops that run; it does not recurse.
fn CodeWriter::render_tokens(
  self : CodeWriter,
  template : String,
  args : Array[TemplateValue],
) -> String raise CodegenError {
  let parsed = parse_template(template)
  let used = Array::make(args.length(), false)
  let arg_index = resolve_arguments(parsed, template, args, used)
  let state = self.state()
  let frames : Array[LoopFrame] = []
  let out = StringBuilder()
  let mut pc = 0
  while pc < parsed.tokens.length() {
    match parsed.tokens[pc] {
      Literal(text) => out.write_string(text)
      Expr(source, name, align, offset) => {
        let value = match source {
          Relative | Positional(_) => args[arg_index[pc]]
          Named(key) =>
            match lookup_name(frames, state.context, key) {
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
              Ok(text) => write_aligned(out, text, align)
              Err(problem) => raise template_error(problem, offset, template)
            }
          Some(Nested) =>
            match value {
              Call(body) => {
                let child = self.child()
                body(child)
                let text = child.to_string()
                write_aligned(out, text.trim_end(chars="\n").to_owned(), align)
              }
              _ =>
                raise template_error(
                  "a value that `C` cannot format: only a function", offset, template,
                )
            }
          Some(Symbolic) =>
            match value {
              Sym(symbol) =>
                write_aligned(out, self.symbol_text(symbol, None), align)
              Ref(reference) =>
                write_aligned(
                  out,
                  self.symbol_text(reference.symbol, reference.alias),
                  align,
                )
              _ =>
                raise template_error(
                  "a value that `T` cannot format: only a symbol or a reference",
                  offset, template,
                )
            }
          Some(Custom(format)) => write_aligned(out, format(self, value), align)
        }
      }
      Open(If, name, _) =>
        if !name_is_truthy(frames, state.context, name) {
          pc = parsed.matching[pc]
        }
      Open(Unless, name, _) =>
        if name_is_truthy(frames, state.context, name) {
          pc = parsed.matching[pc]
        }
      Open(Loop(key_name, value_name), name, offset) => {
        let entries : Array[(TemplateValue, TemplateValue)] = []
        match lookup_name(frames, state.context, name) {
          Some(List(items)) =>
            for index, item in items {
              entries.push((Int(index), item))
            }
          Some(Record(fields)) =>
            for key, item in fields {
              entries.push((Text(key), item))
            }
          Some(other) =>
            raise template_error(
              "a loop over `\{name}`, which is \{other.kind_name()} and not a list or a record",
              offset,
              template,
            )
          None =>
            raise template_error(
              "a loop over `\{name}`, which has no value in the context",
              offset,
              template,
            )
        }
        if entries.is_empty() {
          pc = parsed.matching[pc]
        } else {
          let frame = {
            entries,
            key_name,
            value_name,
            index: 0,
            vars: Map([]),
          }
          frame.bind()
          frames.push(frame)
        }
      }
      Close =>
        if parsed.tokens[parsed.matching[pc]] is Open(Loop(_, _), _, _) {
          let frame = frames[frames.length() - 1]
          if frame.index + 1 < frame.entries.length() {
            frame.index += 1
            frame.bind()
            pc = parsed.matching[pc]
          } else {
            let _ = frames.pop()
          }
        }
    }
    pc += 1
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

///|
/// A named place in the generated code. A section can carry data for the
/// interceptors that change its text.
pub(all) struct Section {
  name : String
  data : Map[String, TemplateValue]
}

///|
pub fn Section::new(
  name : String,
  data~ : Map[String, TemplateValue] = Map([]),
) -> Section {
  { name, data, }
}

///|
/// A function that changes the text of the sections with one name. The
/// function gets a child writer, the section and the previous text. The text
/// of the child writer becomes the new text of the section.
pub struct Interceptor {
  priv section_name : String
  priv run : (CodeWriter, Section, String) -> Unit raise CodegenError
}

///|
pub fn Interceptor::new(
  section_name : String,
  run : (CodeWriter, Section, String) -> Unit raise CodegenError,
) -> Interceptor {
  { section_name, run, }
}

///|
/// An interceptor that keeps the previous text and writes after it.
pub fn Interceptor::appender(
  section_name : String,
  run : (CodeWriter, Section) -> Unit raise CodegenError,
) -> Interceptor {
  Interceptor::new(section_name, (child, section, previous) => {
    child.write_raw(previous)
    run(child, section)
  })
}

///|
/// An interceptor that keeps the previous text and writes before it.
pub fn Interceptor::prepender(
  section_name : String,
  run : (CodeWriter, Section) -> Unit raise CodegenError,
) -> Interceptor {
  Interceptor::new(section_name, (child, section, previous) => {
    run(child, section)
    child.write_raw(previous)
  })
}

///|
/// The name of the sections that the interceptor changes.
pub fn Interceptor::section_name(self : Interceptor) -> String {
  self.section_name
}

///|
/// A section that is open: its data and the number of states when it started.
priv struct OpenSection {
  section : Section
  depth : Int32
}

///|
/// Write the text as it is and end the line. It is not a template. Nothing is
/// written when the text is empty.
fn CodeWriter::write_raw(self : CodeWriter, text : String) -> Unit {
  if !text.is_empty() {
    self.emit(text, true)
  }
}

///|
/// Add an interceptor. It applies to the sections that this writer and its
/// child writers end. Interceptors run in the order that they were added.
pub fn CodeWriter::on_section(
  self : CodeWriter,
  interceptor : Interceptor,
) -> Unit {
  self.interceptors.push(interceptor)
}

///|
/// Start a section. It saves the state, as `push_state` does, with no
/// indentation and no newline prefix. Until `pop_section`, the writer captures
/// the text that it writes.
pub fn CodeWriter::push_section(self : CodeWriter, section : Section) -> Unit {
  self.push_state()
  let state = self.state()
  state.indent_level = 0
  state.newline_prefix = ""
  self.open_sections.push({ section, depth: self.states.length(), })
  self.buffers.push(OutputBuffer::new())
}

///|
/// End the section and restore the state. The interceptors of the section
/// change its text in the order that they were added. Then I write the text
/// with the indentation of the enclosing writer. I write nothing when the
/// text is empty. It raises `StateError` when no section is open, or when a
/// `push_state` inside the section is still open.
pub fn CodeWriter::pop_section(self : CodeWriter) -> Unit raise CodegenError {
  guard self.open_sections.last() is Some(open) else {
    raise StateError("I found pop_section with no open section.")
  }
  if open.depth != self.states.length() {
    raise StateError(
      "I could not end section `\{open.section.name}`: a push_state inside it is still open.",
    )
  }
  let _ = self.open_sections.pop()
  let captured = match self.buffers.pop() {
    Some(buffer) => buffer.out.to_string()
    None => ""
  }
  let _ = self.states.pop()
  let mut text = normalize_output(captured).trim_end(chars="\n").to_owned()
  // An interceptor can add interceptors, so I run a copy of the array.
  for interceptor in self.interceptors.copy() {
    if interceptor.section_name == open.section.name {
      let child = self.child()
      (interceptor.run)(child, open.section, text)
      text = child.to_string().trim_end(chars="\n").to_owned()
    }
  }
  self.write_raw(text)
}

///|
/// Start a section and end it at once, so the interceptors can add text.
pub fn CodeWriter::inject_section(
  self : CodeWriter,
  section : Section,
) -> Unit raise CodegenError {
  self.push_section(section)
  self.pop_section()
}

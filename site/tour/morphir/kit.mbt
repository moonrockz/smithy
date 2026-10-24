///|
fn kind_of_tag(name : String) -> Kind? {
  match name {
    "Name" => Some(Name)
    "Path" => Some(Path)
    "FQName" => Some(FQName)
    "Type" => Some(Type)
    "TypeAttributes" => Some(TypeAttributes)
    "SourceLocation" => Some(SourceLocation)
    _ => None
  }
}

///|
/// The step forms of the compatibility kit that carry JSON.
priv enum Step {
  /// A literal step with an example in the text.
  Literal(Json, Verdict)
  /// An outline step. The rows of the next table give the examples.
  Outline(value_column~ : String, verdict~ : (Map[String, String]) -> Verdict)
}

///|
fn parse_json(
  source : String,
  line : Int32,
  text : String,
) -> Json raise Failure {
  @json.parse(text) catch {
    _ => fail("\{source}:\{line}: I could not read the JSON \{text}")
  }
}

///|
/// Reads a step. None: the step does not name JSON. A step that names JSON
/// and fits no form is an error.
fn parse_step(
  source : String,
  line : Int32,
  text : String,
) -> Step? raise Failure {
  if !text.contains("JSON") && !text.contains("<format>") {
    return None
  }
  fn literal(prefix : String) -> String? {
    text.strip_prefix(prefix).map(fn(rest) { rest.to_owned() })
  }

  if literal("its canonical JSON spelling is ") is Some(json) {
    return Some(Literal(parse_json(source, line, json), Accepted))
  }
  if literal("a reader of JSON accepts ") is Some(rest) {
    if rest.rev_find(" with warning ") is Some(i) {
      let json = rest[:i].to_owned()
      let warning = rest[i + 14:].to_owned()
      return Some(Literal(parse_json(source, line, json), Legacy(warning)))
    }
    return Some(Literal(parse_json(source, line, rest), Accepted))
  }
  if literal("a reader of JSON rejects ") is Some(rest) {
    if rest.rev_find(" with ") is Some(i) {
      let json = rest[:i].to_owned()
      let diagnostic = rest[i + 6:].to_owned()
      return Some(Literal(parse_json(source, line, json), Rejected(diagnostic)))
    }
  }
  match text {
    "its canonical <format> spelling is <spelling>" =>
      Some(Outline(value_column="spelling", verdict=fn(_) { Accepted }))
    "a reader of <format> accepts <input>" =>
      Some(Outline(value_column="input", verdict=fn(_) { Accepted }))
    "a reader of <format> accepts <input> with warning <warning>" =>
      Some(
        Outline(value_column="input", verdict=fn(row) {
          Legacy(row.get("warning").unwrap_or(""))
        }),
      )
    "a reader of <format> rejects <input> with <diagnostic>" =>
      Some(
        Outline(value_column="input", verdict=fn(row) {
          Rejected(row.get("diagnostic").unwrap_or(""))
        }),
      )
    _ => fail("\{source}:\{line}: I do not know the step \{text}")
  }
}

///|
fn cells_of(row : String) -> Array[String] {
  let inner = row.trim()
  let inner = inner.strip_prefix("|").unwrap_or(inner)
  let inner = inner.strip_suffix("|").unwrap_or(inner)
  inner.split("|").map(fn(cell) { cell.trim().to_owned() }).collect()
}

///|
fn kit_examples_raise(
  source : String,
  text : String,
) -> Array[Example] raise Failure {
  let out = []
  let mut default_kind : Kind? = None
  let mut pending : Kind? = None
  let mut kind : Kind? = None
  let mut outline : Step? = None
  let mut header : Array[String]? = None
  let mut in_docstring = false
  for index, raw in text.split("\n").collect() {
    let line = index + 1
    let trimmed = raw.trim().to_owned()
    if trimmed.has_prefix("\"\"\"") {
      in_docstring = !in_docstring
      continue
    }
    if in_docstring || trimmed.is_empty() {
      continue
    }
    if trimmed.has_prefix("@") {
      for tag in trimmed.split(" ") {
        if tag.strip_prefix("@node:") is Some(name) {
          match kind_of_tag(name.to_owned()) {
            Some(_) as k => pending = k
            None => fail("\{source}:\{line}: I do not know the node \{name}")
          }
        }
      }
      continue
    }
    if trimmed.has_prefix("Feature:") {
      default_kind = pending
      pending = None
      continue
    }
    if trimmed.has_prefix("Scenario") {
      kind = match pending {
        Some(_) as k => k
        None => default_kind
      }
      pending = None
      outline = None
      header = None
      continue
    }
    if trimmed.has_prefix("|") {
      guard outline is Some(Outline(value_column~, verdict~)) else { continue }
      let cells = cells_of(trimmed)
      guard header is Some(names) else {
        header = Some(cells)
        continue
      }
      if cells.length() != names.length() {
        fail(
          "\{source}:\{line}: I expected \{names.length()} cells but found \{cells.length()}",
        )
      }
      let row : Map[String, String] = Map([])
      for i, name in names {
        row[name] = cells[i]
      }
      guard row.get("format") is Some(format) else {
        fail("\{source}:\{line}: the table has no format column")
      }
      if format != "JSON" {
        continue
      }
      guard row.get(value_column) is Some(json) else {
        fail("\{source}:\{line}: the table has no \{value_column} column")
      }
      guard kind is Some(k) else {
        fail("\{source}:\{line}: I found a row without a node tag")
      }
      out.push({
        source,
        at: "line \{line}",
        kind: k,
        verdict: verdict(row),
        value: parse_json(source, line, json),
      })
      continue
    }
    let step = ["Then ", "And ", "Given ", "When "].search_by(fn(p) {
      trimmed.has_prefix(p)
    })
    guard step is Some(i) else { continue }
    outline = None
    header = None
    let step_text = trimmed[["Then ", "And ", "Given ", "When "][i].length():].to_owned()
    match parse_step(source, line, step_text) {
      None => ()
      Some(Literal(json, verdict)) => {
        guard kind is Some(k) else {
          fail("\{source}:\{line}: I found a step without a node tag")
        }
        out.push({ source, at: "line \{line}", kind: k, verdict, value: json, })
      }
      Some(Outline(_)) as s => outline = s
    }
  }
  out
}

///|
/// The JSON rows of a compatibility kit file (Gherkin). A step or a row that
/// names JSON and fits no known form is an error that names the file and the
/// line.
pub fn kit_examples(
  source : String,
  text : String,
) -> Result[Array[Example], String] {
  Ok(kit_examples_raise(source, text)) catch {
    Failure(message) => Err(message)
  }
}

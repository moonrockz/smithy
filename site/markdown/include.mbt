///|
/// One line of an include block: `LABEL: PATH#NAME`.
pub(all) struct Include {
  label : String
  path : String
  name : String
} derive(Eq, Debug)

///|
/// A fenced code block of a source region; `lang` and `rest` split the info string
/// as `@cmark.CodeBlock::language_of_info_string` does ("mbt check" gives "mbt" and "check").
pub(all) struct Fence {
  lang : String
  rest : String
  code : String
} derive(Eq, Debug)

///|
fn lines_of(text : String) -> Array[String] {
  let out : Array[String] = []
  for line in text.split("\n") {
    let s = line.to_owned()
    out.push(if s.has_suffix("\r") { s[:s.length() - 1].to_owned() } else { s })
  }
  out
}

///|
fn valid_name(name : String) -> Bool {
  name != "" &&
  name.iter().all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')
}

///|
const TAB_LINE_HINT : String = "I expected `LABEL: PATH#NAME`"

///|
/// The tab lines of the body of an include fence.
pub fn parse_include(body : String) -> Result[Array[Include], String] {
  let out : Array[Include] = []
  for line in lines_of(body) {
    let text = line.trim().to_owned()
    if text == "" {
      continue
    }
    guard text.find(":") is Some(colon) else {
      return Err("\{TAB_LINE_HINT}, but found `\{text}`")
    }
    let label = text[:colon].trim().to_owned()
    let target = text[colon + 1:].trim().to_owned()
    guard target.rev_find("#") is Some(hash) else {
      return Err("\{TAB_LINE_HINT}, but found `\{text}`")
    }
    let path = target[:hash].trim().to_owned()
    let name = target[hash + 1:].trim().to_owned()
    if label == "" || path == "" {
      return Err("\{TAB_LINE_HINT}, but found `\{text}`")
    }
    if !valid_name(name) {
      return Err(
        "I expected a block name of [a-z0-9-]+ in `\{text}`, but found `\{name}`",
      )
    }
    if out.iter().any(i => i.label == label) {
      return Err("I found the label \{label} twice in the include block")
    }
    out.push({ label, path, name })
  }
  if out.length() == 0 {
    return Err("I found no tab line in the include block")
  }
  Ok(out)
}

///|
fn kind_of(block : @cmark.Block) -> String {
  match block {
    BlankLine(_) => "a blank line"
    BlockQuote(_) => "a quote"
    Blocks(_) => "a block group"
    CodeBlock(_) | ExtMathBlock(_) => "a code block"
    Heading(_) => "a heading"
    HtmlBlock(_) => "an HTML block"
    LinkRefDefinition(_) => "a link definition"
    List(_) => "a list"
    Paragraph(_) => "a paragraph"
    ThematicBreak(_) => "a thematic break"
    ExtTable(_) => "a table"
    ExtFootnoteDefinition(_) => "a footnote"
  }
}

///|
fn collect_fences(
  block : @cmark.Block,
  name : String,
  out : Array[Fence],
) -> String? {
  match block {
    Blocks({ v: bs, .. }) =>
      for b in bs.iter() {
        if collect_fences(b, name, out) is Some(e) {
          return Some(e)
        }
      }
    BlankLine(_) => ()
    CodeBlock({ v: cb, .. }) =>
      match cb.layout {
        Indented =>
          return Some(
            "I expected only fenced code blocks between the markers of \{name}, but found an indented code block",
          )
        Fenced(_) => {
          let (lang, rest) = match cb.info_string {
            Some({ v, .. }) =>
              @cmark.CodeBlock::language_of_info_string(v).unwrap_or(("", ""))
            None => ("", "")
          }
          out.push({ lang, rest, code: code_source(cb) })
        }
      }
    other =>
      return Some(
        "I expected only code blocks between the markers of \{name}, but found \{kind_of(other)}",
      )
  }
  None
}

///|
/// The fences between `<!-- tour:start NAME -->` and `<!-- tour:end NAME -->` of `source`.
pub fn region(source : String, name : String) -> Result[Array[Fence], String] {
  let start_marker = "<!-- tour:start \{name} -->"
  let end_marker = "<!-- tour:end \{name} -->"
  let lines = lines_of(source)
  let starts : Array[Int] = []
  for i, line in lines {
    if line.trim().to_owned() == start_marker {
      starts.push(i)
    }
  }
  if starts.length() == 0 {
    return Err("I could not find the marker `\{start_marker}`")
  }
  if starts.length() > 1 {
    return Err("I found the marker `\{start_marker}` twice")
  }
  let first = starts[0] + 1
  let mut end_at = -1
  for i = first; i < lines.length(); i = i + 1 {
    if lines[i].trim().to_owned() == end_marker {
      end_at = i
      break
    }
  }
  if end_at < 0 {
    return Err("I could not find the marker `\{end_marker}`")
  }
  let inner = lines[first:end_at].to_owned().join("\n")
  let doc = @cmark.Doc::from_string(strict=false, inner)
  let out : Array[Fence] = []
  if collect_fences(doc.block, name, out) is Some(e) {
    return Err(e)
  }
  if out.length() == 0 {
    return Err("I found no code block between the markers of \{name}")
  }
  Ok(out)
}

///|
/// The fence character and length of a fence line (up to 3 spaces of indent), or `None`.
fn fence_of(line : String) -> (Char, Int, Int, String)? {
  let mut i = 0
  while i < line.length() && line[i] == ' ' {
    i += 1
  }
  if i >= line.length() {
    return None
  }
  let ch = line[i].to_char().unwrap()
  if ch != '`' && ch != '~' {
    return None
  }
  let mut j = i
  while j < line.length() && line[j] == line[i] {
    j += 1
  }
  if j - i < 3 {
    return None
  }
  Some((ch, j - i, i, line[j:].trim().to_owned()))
}

///|
/// `text` with each top-level ```include fence replaced by `tabs_fence` of its tabs.
/// The error names the include line: "CLI: apps/smithy/README.md#x: <message of resolve>".
pub fn expand_includes(
  text : String,
  resolve : (Include) -> Result[Array[Snippet], String],
) -> Result[String, String] {
  let lines = text.split("\n").map(l => l.to_owned()).collect()
  let out : Array[String] = []
  let mut open : (Char, Int)? = None
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    let trimmed = if line.has_suffix("\r") {
      line[:line.length() - 1].to_owned()
    } else {
      line
    }
    match (open, fence_of(trimmed)) {
      (Some((ch, len)), Some((c, n, _, info))) => {
        if c == ch && n >= len && info == "" {
          open = None
        }
        out.push(line)
        i += 1
      }
      (Some(_), None) | (None, None) => {
        out.push(line)
        i += 1
      }
      (None, Some((c, n, indent, info))) =>
        if c == '`' && info == "include" {
          if indent > 0 {
            return Err(
              "I found an indented include fence at line \{i + 1}; I expected it at the start of a line",
            )
          }
          let body : Array[String] = []
          let mut j = i + 1
          let mut closed = false
          while j < lines.length() {
            let l = lines[j].trim().to_owned()
            if l.length() >= n && l.iter().all(ch => ch == '`') {
              closed = true
              break
            }
            body.push(lines[j])
            j += 1
          }
          if !closed {
            return Err(
              "I found an include fence at line \{i + 1} that is not closed",
            )
          }
          let includes = match parse_include(body.join("\n")) {
            Ok(v) => v
            Err(e) => return Err("line \{i + 1}: \{e}")
          }
          let tabs : Array[Tab] = []
          for inc in includes {
            let snippets = match resolve(inc) {
              Ok(v) => v
              Err(e) => return Err("\{inc.label}: \{inc.path}#\{inc.name}: \{e}")
            }
            tabs.push({ label: inc.label, snippets })
          }
          out.push(tabs_fence(tabs))
          i = j + 1
        } else {
          open = Some((c, n))
          out.push(line)
          i += 1
        }
    }
  }
  Ok(out.join("\n"))
}

///|
/// Calls `f` on each block of `blocks` and on each block nested in a quote or a list item.
pub fn walk_blocks(blocks : Array[Block], f : (Block) -> Unit) -> Unit {
  for b in blocks {
    f(b)
    match b {
      Quote(inner) => walk_blocks(inner, f)
      BulletList(items) | OrderedList(_, items) =>
        for item in items {
          walk_blocks(item, f)
        }
      _ => ()
    }
  }
}

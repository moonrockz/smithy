///|
/// The README files whose `console` and `LANG file=NAME` fences run. Keep it equal to
/// `readme_files` in scripts/test-cli.mbtx.
pub let cli_doc_files : Array[String] = ["apps/smithy/README.md"]

///|
fn untested(lang : String, rest : String) -> String {
  let found = if rest == "" { lang } else { "\{lang} \{rest}" }
  let files = cli_doc_files.join(" or ")
  "I can include only a tested block: `mbt check` in a .mbt.md file, or `console` and `LANG file=NAME` in \{files}. I found `\{found}`"
}

///|
fn has_test(code : String) -> Bool {
  code
  .split("\n")
  .any(line => {
    let t = line.trim().to_owned()
    t.has_prefix("test ") || t.has_prefix("test{") || t.has_prefix("async test")
  })
}

///|
/// The snippet of a tested fence, or why the fence is not tested.
pub fn tested_snippet(
  path : String,
  fence : @markdown.Fence,
  has_moon_pkg~ : Bool,
) -> Result[@markdown.Snippet, String] {
  if fence.lang == "mbt" && fence.rest == "check" {
    if !path.has_suffix(".mbt.md") {
      return Err(
        "I found an `mbt check` block in \{path}, but only a .mbt.md file is run by moon test",
      )
    }
    if !has_moon_pkg {
      return Err(
        "I found an `mbt check` block in \{path}, but the folder has no moon.pkg, so moon test does not run it",
      )
    }
    if !has_test(fence.code) {
      return Err(
        "I found an `mbt check` block with no test in \{path}; I expected a line that starts with `test `",
      )
    }
    return Ok({ lang: "mbt", file: None, code: fence.code, })
  }
  if cli_doc_files.contains(path) {
    // The runner runs a fence whose first info word is `console`, whatever follows,
    // so a `console` fence with more words is not a fixture. `status=N` (N from 1 to 125)
    // makes each command exit with N (scripts/test-cli.mbtx, `doc_console_status`).
    if fence.lang == "console" &&
      (fence.rest == "" || console_status_word(fence.rest)) {
      return Ok({ lang: "console", file: None, code: fence.code, })
    }
    if fence.lang != "console" &&
      fence.lang != "" &&
      fence.rest.has_prefix("file=") &&
      fence.rest.length() > 5 &&
      !fence.rest.contains(" ") {
      return Ok({
        lang: fence.lang,
        file: Some(fence.rest[5:].to_owned()),
        code: fence.code,
      })
    }
  }
  Err(untested(fence.lang, fence.rest))
}

///|
/// True when `rest` is exactly `status=N` with N from 1 to 125.
fn console_status_word(rest : String) -> Bool {
  guard rest.has_prefix("status=") else { return false }
  let digits = rest[7:].to_owned()
  if digits.is_empty() || digits.length() > 3 {
    return false
  }
  let mut n = 0
  for c in digits {
    if c < '0' || c > '9' {
      return false
    }
    n = n * 10 + (c.to_int() - 48)
  }
  n >= 1 && n <= 125
}

///|
fn check_path(path : String) -> Result[Unit, String] {
  let bad = path.has_prefix("/") ||
    path.contains("\\") ||
    path.split("/").any(s => s == "" || s == ".." || s == ".")
  if bad {
    return Err("I expected a path inside the repository, but found `\{path}`")
  }
  Ok(())
}

///|
/// The opening lines of the fences between the markers of `name`, in order: whether the line
/// is a fence that the CLI runner reads (three or more backticks at the start of a line), and
/// its info string. The fences are tracked from the first line, so a marker inside a fence is
/// code, as in `@markdown.region`.
fn region_openers(source : String, name : String) -> Array[(Bool, String)] {
  let lines = source.split("\n").map(l => l.trim_end(chars="\r").to_owned())
  let out : Array[(Bool, String)] = []
  let mut inside = false
  let mut closer : (Char, Int32)? = None
  for line in lines {
    let t = line.trim().to_owned()
    if closer is None && t == "<!-- tour:start \{name} -->" {
      inside = true
      continue
    }
    if closer is None && t == "<!-- tour:end \{name} -->" {
      if inside {
        break
      }
      continue
    }
    let body = line.trim_start().to_owned()
    let ch = if body.has_prefix("```") {
      '`'
    } else if body.has_prefix("~~~") {
      '~'
    } else {
      ' '
    }
    if ch == ' ' {
      continue
    }
    let n = body.iter().take_while(c => c == ch).count()
    match closer {
      Some((c, len)) =>
        if c == ch &&
          n >= len &&
          body.trim_start(chars="`~").trim().to_owned() == "" {
          closer = None
        }
      None => {
        closer = Some((ch, n))
        if inside {
          out.push(
            (
              line.has_prefix("```"),
              body.trim_start(chars="`~").trim().to_owned(),
            ),
          )
        }
      }
    }
  }
  out
}

///|
/// Reads `repo/path`, takes the region `name`, and checks each fence.
pub fn resolve_include(
  repo : String,
  inc : @markdown.Include,
) -> Result[Array[@markdown.Snippet], String] {
  let path = inc.path
  if check_path(path) is Err(e) {
    return Err(e)
  }
  let file = "\{repo}/\{path}"
  let source = @fs.read_file_to_string(file) catch {
    _ => return Err("I could not find the file \{path}")
  }
  let fences = match @markdown.region(source, inc.name) {
    Ok(f) => f
    Err(e) => return Err("\{e} in \{path}")
  }
  let folder = match path.rev_find("/") {
    Some(i) => path[:i].to_owned()
    None => ""
  }
  let pkg = if folder == "" {
    "\{repo}/moon.pkg"
  } else {
    "\{repo}/\{folder}/moon.pkg"
  }
  let has_moon_pkg = @fs.path_exists(pkg)
  let openers = region_openers(source, inc.name)
  let out : Array[@markdown.Snippet] = []
  for i, fence in fences {
    let snippet = match tested_snippet(path, fence, has_moon_pkg~) {
      Ok(s) => s
      Err(e) => return Err(e)
    }
    if snippet.lang == "console" || snippet.file is Some(_) {
      let info = if fence.rest == "" {
        fence.lang
      } else {
        "\{fence.lang} \{fence.rest}"
      }
      if i >= openers.length() || !openers[i].0 || openers[i].1 != info {
        return Err(
          "I found the fence `\{fence.lang} \{fence.rest}` in \{path}, but it does not start at the start of a line, so the CLI runner does not read it",
        )
      }
    }
    out.push(snippet)
  }
  Ok(out)
}

///|
let hand_written : Array[String] = [
  "console", "shell", "sh", "bash", "zsh", "mbt", "moonbit", "shell-session", "shellsession",
  "sh-session", "terminal", "powershell", "pwsh", "fish", "cmd", "bat",
]

///|
fn hand_written_error(lang : String) -> String {
  "I found a `\{lang}` block. A CLI or API block must come from a tested source: use an include block"
}

///|
fn is_lower_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || c.is_ascii_digit() || c == '_'
}

///|
fn is_word_char(c : Char) -> Bool {
  is_lower_ident_char(c) || (c >= 'A' && c <= 'Z')
}

///|
/// Whether `line` uses the API of a package: an `@` at the start of the line or after a
/// character that is not a letter, digit or `_`, then an alias `[a-z_][a-z0-9_]*`, then `.`,
/// then `[A-Za-z_][A-Za-z0-9_.]*` and anything but `#`. A qualified shape ID such as
/// `@smithy.api#documentation("x")` has a `#` there, an unqualified trait such as
/// `@length(min: 1)` has no `.` after its name, a trait name at the end of a sentence such
/// as `Add @required.` has no name after the `.`, and an e-mail address has a letter before
/// the `@`, so model text stays legal.
fn is_api_call(line : String) -> Bool {
  let cs = line.to_array()
  let n = cs.length()
  for i in 0..<n {
    if cs[i] != '@' || (i > 0 && is_word_char(cs[i - 1])) {
      continue
    }
    let mut j = i + 1
    if j >= n || !((cs[j] >= 'a' && cs[j] <= 'z') || cs[j] == '_') {
      continue
    }
    while j < n && is_lower_ident_char(cs[j]) {
      j = j + 1
    }
    if j >= n || cs[j] != '.' {
      continue
    }
    j = j + 1
    if j >= n || cs[j].is_ascii_digit() || !is_word_char(cs[j]) {
      continue
    }
    while j < n && (is_word_char(cs[j]) || cs[j] == '.') {
      j = j + 1
    }
    if !(j < n && cs[j] == '#') {
      return true
    }
  }
  false
}

///|
/// `line` without a shell prompt: `$`, `%`, `#` or `>` and the spaces after it, or the text up
/// to the first `>` of a PowerShell (`PS>`, `PS C:\\work>`) or a Windows (`C:\\work>`) prompt.
fn without_prompt(line : String) -> String {
  let cs = line.to_array()
  if cs.length() > 0 &&
    (cs[0] == '$' || cs[0] == '%' || cs[0] == '#' || cs[0] == '>') {
    return line[1:].trim_start().to_owned()
  }
  let windows = cs.length() > 2 &&
    cs[0].is_ascii_alphabetic() &&
    cs[1] == ':' &&
    cs[2] == '\\'
  if line.has_prefix("PS") || windows {
    if line.find(">") is Some(i) {
      return line[i + 1:].trim_start().to_owned()
    }
  }
  line
}

///|
/// The text of a line that looks like a CLI command of Smithy (after an optional shell
/// prompt) or an API call of a package, or `None`.
fn smithy_use(code : String) -> String? {
  for line in code.split("\n") {
    let t = line.trim().to_owned()
    let command = without_prompt(t)
    if command.has_prefix("smithy ") || command == "smithy" || is_api_call(t) {
      return Some(t)
    }
  }
  None
}

///|
/// `line` without its HTML tags.
fn without_tags(line : String) -> String {
  let buf = StringBuilder()
  let mut in_tag = false
  for c in line {
    if c == '<' {
      in_tag = true
    } else if c == '>' && in_tag {
      in_tag = false
    } else if !in_tag {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Err when `text` has a fence with a CLI, API or tabs language (at any depth), or a fence
/// of any other language whose text is a `smithy` command or a package API call.
pub fn check_hand_written(text : String) -> Result[Unit, String] {
  let doc = @markdown.parse(text, {
    source: "",
    resolve: _ => None,
    repo_url: "",
    git_ref: "",
  })
  let mut found : String? = None
  @markdown.walk_blocks(doc.blocks, block => {
    if found is None {
      match block {
        CodeBlock(lang, code) => {
          let l = lang.to_lower()
          if hand_written.contains(l) || l == "tabs" {
            found = Some(hand_written_error(l))
          } else if l != "include" {
            if smithy_use(code) is Some(line) {
              let kind = if l == "" { "a code block" } else { "a `\{l}` block" }
              found = Some(
                "I found \{kind} with the line `\{line}`. A CLI or API block must come from a tested source: use an include block",
              )
            }
          }
        }
        Tabs(_, _) => found = Some(hand_written_error("tabs"))
        _ => ()
      }
    }
  })
  if found is None {
    // The site does not show an HTML block, but GitHub shows the lesson file with it.
    for html in @markdown.html_blocks(text) {
      let plain = html
        .split("\n")
        .map(l => without_tags(l.to_owned()))
        .join("\n")
      if smithy_use(plain) is Some(line) {
        found = Some(
          "I found an HTML block with the line `\{line}`. A CLI or API block must come from a tested source: use an include block",
        )
        break
      }
    }
  }
  match found {
    Some(e) => Err(e)
    None => Ok(())
  }
}

///|
/// Err when the expanded `text` still has a code block of the language `include`, at any
/// depth. `@markdown.expand_includes` reads only a ```` ```include ```` fence at the start of a
/// line, so any other include block would show its raw text and its file would not be read.
pub fn check_expanded(text : String) -> Result[Unit, String] {
  let doc = @markdown.parse(text, {
    source: "",
    resolve: _ => None,
    repo_url: "",
    git_ref: "",
  })
  let mut found = false
  @markdown.walk_blocks(doc.blocks, block => {
    if block is CodeBlock(lang, _) && lang.to_lower() == "include" {
      found = true
    }
  })
  if found {
    Err(
      "I found an include block that I cannot expand: write it as ```include at the start of a line, outside a quote or a list, with no other word after `include`",
    )
  } else {
    Ok(())
  }
}

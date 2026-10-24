///|
/// The README files whose `console` and `LANG file=NAME` fences run. Keep it equal to
/// `readme_files` in scripts/test-cli.mbtx.
pub let cli_doc_files : Array[String] = ["apps/smithy/README.md"]

///|
fn untested(lang : String, rest : String) -> String {
  let found = if rest == "" { lang } else { "\{lang} \{rest}" }
  "I can include only a tested block: `mbt check` in a .mbt.md file, or `console` and `LANG file=NAME` in apps/smithy/README.md. I found `\{found}`"
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
    // so a `console` fence with more words is not a fixture.
    if fence.lang == "console" && fence.rest == "" {
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
/// its info string.
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
      break
    }
    if !inside {
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
        out.push(
          (
            line.has_prefix("```"),
            body.trim_start(chars="`~").trim().to_owned(),
          ),
        )
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
/// Whether `line` starts with `@smithy.`, an identifier and `(`: a call of the API. A qualified
/// shape ID such as `@smithy.api#documentation("x")` has a `#` before the `(`, so it is not a call.
fn is_api_call(line : String) -> Bool {
  if !line.has_prefix("@smithy.") {
    return false
  }
  let rest = line[8:].to_owned()
  let name = rest
    .iter()
    .take_while(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c.is_ascii_digit() ||
      c == '_' ||
      c == '.'
    })
    .count()
  name > 0 && rest[name:].to_owned().has_prefix("(")
}

///|
/// The text of a line that looks like a CLI command or an API call of Smithy, or `None`.
fn smithy_use(code : String) -> String? {
  for line in code.split("\n") {
    let t = line.trim().to_owned()
    if t.has_prefix("$ smithy") || t.has_prefix("smithy ") || is_api_call(t) {
      return Some(t)
    }
  }
  None
}

///|
/// Err when `text` has a fence with a CLI, API or tabs language (at any depth), or a fence
/// of any other language whose text is a `smithy` command or a `@smithy.` call.
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
  match found {
    Some(e) => Err(e)
    None => Ok(())
  }
}

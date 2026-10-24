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
/// Whether `source` has a fence line that the CLI runner reads: at the start of a line, with
/// three or more backticks, and the info string `lang` and `rest`.
fn runner_reads(source : String, lang : String, rest : String) -> Bool {
  let info = if rest == "" { lang } else { "\{lang} \{rest}" }
  source
  .split("\n")
  .any(l => {
    let line = l.trim_end(chars="\r").to_owned()
    line.has_prefix("```") &&
    line.trim_start(chars="`").trim().to_owned() == info
  })
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
  let out : Array[@markdown.Snippet] = []
  for fence in fences {
    let snippet = match tested_snippet(path, fence, has_moon_pkg~) {
      Ok(s) => s
      Err(e) => return Err(e)
    }
    if snippet.lang == "console" || snippet.file is Some(_) {
      if !runner_reads(source, fence.lang, fence.rest) {
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
  "console", "shell", "sh", "bash", "zsh", "mbt", "moonbit",
]

///|
fn hand_written_error(lang : String) -> String {
  "I found a `\{lang}` block. A CLI or API block must come from a tested source: use an include block"
}

///|
/// Err when `text` has a fence with a CLI, API or tabs language (at any depth).
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
        CodeBlock(lang, _) if hand_written.contains(lang) || lang == "tabs" =>
          found = Some(lang)
        Tabs(_, _) => found = Some("tabs")
        _ => ()
      }
    }
  })
  match found {
    Some(lang) => Err(hand_written_error(lang))
    None => Ok(())
  }
}

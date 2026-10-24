///|
fn contains_all(result : Result[Unit, String], part : String) -> Unit raise {
  match result {
    Ok(_) => fail("I expected an error with \"\{part}\", but found Ok")
    Err(msg) =>
      if !msg.contains(part) {
        fail("The error \"\{msg}\" does not contain \"\{part}\"")
      }
  }
}

///|
fn snippet_err(
  path : String,
  fence : @markdown.Fence,
  has_moon_pkg~ : Bool,
  part : String,
) -> Unit raise {
  contains_all(
    @source.tested_snippet(path, fence, has_moon_pkg~).map(_ => ()),
    part,
  )
}

///|
test "tested_snippet accepts only tested fences" {
  let mbt : @markdown.Fence = {
    lang: "mbt",
    rest: "check",
    code: "///|\ntest {\n}",
  }
  assert_eq(
    @source.tested_snippet("pkgs/smithy/README.mbt.md", mbt, has_moon_pkg=true),
    Ok({ lang: "mbt", file: None, code: mbt.code, }),
  )
  snippet_err("pkgs/smithy/README.mbt.md", mbt, has_moon_pkg=false, "moon.pkg")
  snippet_err("docs/guide/x.md", mbt, has_moon_pkg=true, ".mbt.md")
  snippet_err(
    "pkgs/smithy/README.mbt.md",
    { ..mbt, code: "///|\nfn f() -> Unit {}", },
    has_moon_pkg=true,
    "no test",
  )
  snippet_err(
    "pkgs/smithy/README.mbt.md",
    { lang: "mbt", rest: "", code: mbt.code, },
    has_moon_pkg=true,
    "a tested block",
  )
  snippet_err(
    "examples/json-rpc/README.md",
    { lang: "console", rest: "", code: "$ x", },
    has_moon_pkg=true,
    "a tested block",
  )
  snippet_err(
    "apps/smithy/README.md",
    { lang: "shell", rest: "", code: "$ x", },
    has_moon_pkg=true,
    "a tested block",
  )
  snippet_err(
    "apps/smithy/README.md",
    { lang: "console", rest: "file=x", code: "$ x", },
    has_moon_pkg=true,
    "a tested block",
  )
  let console : @markdown.Fence = { lang: "console", rest: "", code: "$ x", }
  assert_eq(
    @source.tested_snippet("apps/smithy/README.md", console, has_moon_pkg=false),
    Ok({ lang: "console", file: None, code: "$ x", }),
  )
  let fixture : @markdown.Fence = {
    lang: "smithy",
    rest: "file=greeting.smithy",
    code: "a",
  }
  assert_eq(
    @source.tested_snippet("apps/smithy/README.md", fixture, has_moon_pkg=false),
    Ok({ lang: "smithy", file: Some("greeting.smithy"), code: "a", }),
  )
}

///|
test "resolve_include reads the CLI and the API block of the repository" {
  let cli = @source.resolve_include("..", {
    label: "CLI",
    path: "apps/smithy/README.md",
    name: "convert-json-cli",
  }).unwrap()
  assert_eq(cli.length(), 2)
  assert_eq(cli[0].file, Some("greeting.smithy"))
  assert_true(
    cli[1].code.has_prefix("$ smithy convert --to json greeting.smithy\n{"),
  )
  let api = @source.resolve_include("..", {
    label: "MoonBit",
    path: "pkgs/smithy/README.mbt.md",
    name: "convert-json-api",
  }).unwrap()
  assert_eq(api.map(s => s.lang), ["mbt"])
}

///|
fn include_err(path : String, name : String, part : String) -> Unit raise {
  contains_all(
    @source.resolve_include("..", { label: "L", path, name, }).map(_ => ()),
    part,
  )
}

///|
test "resolve_include errors" {
  include_err(
    "apps/smithy/NOPE.md", "x", "I could not find the file apps/smithy/NOPE.md",
  )
  include_err(
    "apps/smithy/README.md", "no-such-block", "<!-- tour:start no-such-block -->",
  )
  for
    path in [
      "../secret.md", "/etc/passwd", "apps//README.md", "./x.md", "a\\b.md",
    ] {
    include_err(path, "x", "I expected a path inside the repository")
  }
}

///|
test "check_hand_written" {
  contains_all(
    @source.check_hand_written("# T\n\n```console\n$ smithy version\n```\n"),
    "`console`",
  )
  contains_all(
    @source.check_hand_written("# T\n\n```mbt\nlet x = 1\n```\n"),
    "`mbt`",
  )
  contains_all(
    @source.check_hand_written("# T\n\n- a\n\n  ```bash\n  x\n  ```\n"),
    "`bash`",
  )
  let tabs = @markdown.tabs_fence([
    { label: "A", snippets: [{ lang: "mbt", file: None, code: "x", }], },
  ])
  contains_all(@source.check_hand_written("# T\n\n" + tabs + "\n"), "tabs")
  assert_eq(
    @source.check_hand_written(
      "# T\n\n```smithy\nnamespace a\n```\n\n```json\n{}\n```\n\n```include\nCLI: a.md#x\n```\n",
    ),
    Ok(()),
  )
}

///|
/// Ties the include rule to the CLI runner (scripts/test-cli.mbtx, `doc_steps`): a console or
/// `file=` fence of an included region of a real README is one the runner reads, because
/// it starts a line. The mbtx cannot be imported here, so the runner side is its own tests.
test "every console and file fence of an included region is read by the CLI runner" {
  for file in @source.cli_doc_files {
    let text = @fs.read_file_to_string("../\{file}")
    let mut count = 0
    for line in text.split("\n") {
      let t = line.trim().to_owned()
      let prefix = "<!-- tour:start "
      if t.has_prefix(prefix) && t.has_suffix(" -->") {
        let name = t[prefix.length():t.length() - 4].to_owned()
        let snippets = match
          @source.resolve_include("..", { label: "L", path: file, name, }) {
          Ok(s) => s
          Err(e) => fail("\{file}#\{name}: \{e}")
        }
        count += snippets.length()
        for s in snippets {
          let info = match s.file {
            Some(f) => "\{s.lang} file=\{f}"
            None => s.lang
          }
          assert_true(
            text
            .split("\n")
            .any(l => l.trim_end(chars="\r").to_owned() == "```\{info}"),
            msg="\{file}#\{name}: no fence line starts with ```\{info}",
          )
        }
      }
    }
    assert_true(count > 0, msg="\{file} has no included region")
  }
}

///|
test "check_hand_written rejects other cases, aliases and command text" {
  for
    lang in [
      "Console", "BASH", "shell-session", "shellsession", "sh-session", "terminal",
      "powershell", "pwsh", "fish", "cmd", "bat", "MoonBit", "Mbt",
    ] {
    contains_all(
      @source.check_hand_written("# T\n\n```\{lang}\nx\n```\n"),
      "`\{lang.to_lower()}`",
    )
  }
  for fence in ["", "text", "plaintext", "txt"] {
    contains_all(
      @source.check_hand_written("# T\n\n```\{fence}\n$ smithy version\n```\n"),
      "smithy",
    )
    contains_all(
      @source.check_hand_written(
        "# T\n\n```\{fence}\n  smithy validate x\n```\n",
      ),
      "smithy",
    )
    contains_all(
      @source.check_hand_written("# T\n\n```\{fence}\n@smithy.parse(x)\n```\n"),
      "@smithy.",
    )
  }
  // A line that starts with the word `smithy` is a command; `smithy.api#x` is not.
  assert_eq(
    @source.check_hand_written(
      "# T\n\n```json\n{\"id\": \"smithy.api#String\"}\n```\n\n```smithy\nnamespace a\n```\n",
    ),
    Ok(()),
  )
}

///|
test "cli_doc_files equals readme_files of scripts/test-cli.mbtx" {
  let text = @fs.read_file_to_string("../scripts/test-cli.mbtx")
  let marker = "let readme_files : Array[String] = ["
  guard text.find(marker) is Some(at) else {
    fail("I could not find `\{marker}` in scripts/test-cli.mbtx")
  }
  let after = text[at + marker.length():].to_owned()
  guard after.find("]") is Some(close) else {
    fail("I could not find the end of readme_files in scripts/test-cli.mbtx")
  }
  let names : Array[String] = []
  for part in after[:close].to_owned().split(",") {
    let t = part.trim().to_owned()
    if t != "" {
      names.push(t.trim(chars="\"").to_owned())
    }
  }
  assert_eq(names, @source.cli_doc_files)
}

///|
test "a console fence that is not at the start of a line is rejected" {
  let dir = "tour/source/testdata/indented-readme"
  contains_all(
    @source.resolve_include(dir, {
      label: "L",
      path: "apps/smithy/README.md",
      name: "x",
    }).map(_ => ()),
    "does not start at the start of a line",
  )
}

///|
test "a qualified trait in a model fence is not an API call" {
  assert_eq(
    @source.check_hand_written(
      "# T\n\n```smithy\n@smithy.api#documentation(\"x\")\nstring A\n\n@smithy.example#x\nstring B\n```\n",
    ),
    Ok(()),
  )
  for fence in ["", "text"] {
    contains_all(
      @source.check_hand_written(
        "# T\n\n```\{fence}\n@smithy.parse(text)\n```\n",
      ),
      "@smithy.parse(text)",
    )
  }
}

///|
test "every MoonBit API use is rejected in an untyped and a text fence" {
  for fence in ["", "text"] {
    for
      code in [
        "@smithy.Loader::new()", "@smithy.Selector::parse(x)", "@smithy.parse (x)",
        "let r = @smithy.Loader::new()", "x(@smithy.parse)",
      ] {
      contains_all(
        @source.check_hand_written("# T\n\n```\{fence}\n\{code}\n```\n"),
        "@smithy.",
      )
    }
  }
  assert_eq(
    @source.check_hand_written(
      "# T\n\n```smithy\n@smithy.api#documentation(\"x\")\n@smithy.example#x\nstring A\n```\n\n```json\n{\"target\": \"smithy.api#String\"}\n```\n",
    ),
    Ok(()),
  )
}

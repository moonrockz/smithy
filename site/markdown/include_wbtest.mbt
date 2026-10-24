///|
fn err_has(r : Result[Unit, String], text : String) -> Bool {
  match r {
    Err(m) => m.contains(text)
    Ok(_) => false
  }
}

///|
fn parse_err(body : String, text : String) -> Bool {
  err_has(parse_include(body).map(_ => ()), text)
}

///|
fn region_err(src : String, text : String) -> Bool {
  err_has(region(src, "convert").map(_ => ()), text)
}

///|
test "parse_include reads one tab per line" {
  assert_eq(
    parse_include(
      "CLI: apps/smithy/README.md#convert-json-cli\nMoonBit: pkgs/smithy/README.mbt.md#convert-json-api\n",
    ),
    Ok([
      { label: "CLI", path: "apps/smithy/README.md", name: "convert-json-cli", },
      {
        label: "MoonBit",
        path: "pkgs/smithy/README.mbt.md",
        name: "convert-json-api",
      },
    ]),
  )
}

///|
test "parse_include errors" {
  assert_true(parse_err("", "I found no tab line"))
  assert_true(parse_err("CLI apps/x.md#a", "I expected `LABEL: PATH#NAME`"))
  assert_true(parse_err("CLI: apps/x.md", "I expected `LABEL: PATH#NAME`"))
  assert_true(parse_err("CLI: apps/x.md#Bad Name", "[a-z0-9-]"))
  assert_true(parse_err("CLI: a.md#x\nCLI: b.md#y", "the label CLI twice"))
}

///|
let source =
  #|# CLI
  #|
  #|<!-- tour:start convert -->
  #|```smithy file=greeting.smithy
  #|$version: "2"
  #|```
  #|
  #|```console
  #|$ smithy convert --to json greeting.smithy
  #|```
  #|<!-- tour:end convert -->

///|
test "region returns the fences between the markers" {
  assert_eq(
    region(source, "convert"),
    Ok([
      { lang: "smithy", rest: "file=greeting.smithy", code: "$version: \"2\"", },
      {
        lang: "console",
        rest: "",
        code: "$ smithy convert --to json greeting.smithy",
      },
    ]),
  )
}

///|
test "region reads CRLF text" {
  assert_eq(
    region(source.replace_all(old="\n", new="\r\n"), "convert"),
    region(source, "convert"),
  )
}

///|
test "region errors" {
  assert_true(
    region_err(
      "text\n", "I could not find the marker `<!-- tour:start convert -->`",
    ),
  )
  let start = "<!-- tour:start convert -->\n"
  assert_true(
    region_err(
      start + "```x\na\n```\n" + start,
      "I found the marker `<!-- tour:start convert -->` twice",
    ),
  )
  assert_true(
    region_err(
      start + "```x\na\n```\n",
      "I could not find the marker `<!-- tour:end convert -->`",
    ),
  )
  let end = "<!-- tour:end convert -->\n"
  assert_true(
    region_err(
      start + "Some text.\n" + end,
      "I expected only code blocks between the markers of convert, but found a paragraph",
    ),
  )
  assert_true(
    region_err(
      start + "\n\n" + end,
      "I found no code block between the markers of convert",
    ),
  )
  assert_true(
    region_err(start + "\n    indented\n\n" + end, "an indented code block"),
  )
}

///|
test "region keeps a line of three backticks in the code" {
  let src = "<!-- tour:start convert -->\n````mbt\nlet s = \"\"\"\n```\n\"\"\"\n````\n<!-- tour:end convert -->\n"
  assert_eq(
    region(src, "convert"),
    Ok([{ lang: "mbt", rest: "", code: "let s = \"\"\"\n```\n\"\"\"", }]),
  )
}

///|
test "expand_includes replaces the include fence with a tabs fence" {
  let snippet : Snippet = {
    lang: "console",
    file: None,
    code: "$ smithy version",
  }
  let text = "# T\n\nIntro.\n\n```include\nCLI: a.md#x\n```\n\nAfter.\n"
  assert_eq(
    expand_includes(text, _ => Ok([snippet])),
    Ok(
      "# T\n\nIntro.\n\n" +
      tabs_fence([{ label: "CLI", snippets: [snippet], }]) +
      "\n\nAfter.\n",
    ),
  )
}

///|
test "expand_includes leaves text without an include as it is" {
  let text = "# T\n\n```mbt\nlet x = 1\n```\n"
  assert_eq(expand_includes(text, _ => Err("no")), Ok(text))
}

///|
test "expand_includes names the include line in an error" {
  let r = expand_includes("```include\nCLI: a.md#x\n```\n", _ => {
    Err("I could not find the file a.md")
  })
  assert_true(err_has(r.map(_ => ()), "CLI: a.md#x"))
  assert_true(err_has(r.map(_ => ()), "I could not find the file a.md"))
}

///|
test "an include inside a longer fence is text" {
  let text = "````markdown\n```include\nCLI: a.md#x\n```\n````\n"
  assert_eq(expand_includes(text, _ => Err("resolve called")), Ok(text))
}

///|
test "an indented include fails" {
  let r = expand_includes("- item\n\n  ```include\n  CLI: a.md#x\n  ```\n", _ => {
    Ok([])
  })
  assert_true(err_has(r.map(_ => ()), "indented"))
}

///|
test "an include fence without a closing fence fails" {
  let r = expand_includes("```include\nCLI: a.md#x\n", _ => Ok([]))
  assert_true(err_has(r.map(_ => ()), "not closed"))
}

///|
test "walk_blocks visits nested blocks" {
  let seen : Array[String] = []
  walk_blocks(
    [Quote([CodeBlock("a", "x")]), BulletList([[CodeBlock("b", "y")]])],
    b => if b is CodeBlock(l, _) { seen.push(l) },
  )
  assert_eq(seen, ["a", "b"])
}

///|
test "a line that starts with an emoji does not panic" {
  let text = "😀 hi\n"
  assert_eq(expand_includes(text, _ => Err("no")), Ok(text))
}

///|
test "a backtick fence with a backtick in the info string is text" {
  let text = "```include `x`\nCLI: a.md#x\n```\n"
  assert_eq(expand_includes(text, _ => Err("resolve called")), Ok(text))
}

///|
test "expand_includes reads CRLF text" {
  let snippet : Snippet = {
    lang: "console",
    file: None,
    code: "$ smithy version",
  }
  let r = expand_includes("A\r\n```include\r\nCLI: a.md#x\r\n```\r\nB\r\n", _ => {
    Ok([snippet])
  })
  assert_eq(
    r,
    Ok(
      "A\r\n" + tabs_fence([{ label: "CLI", snippets: [snippet], }]) + "\nB\r\n",
    ),
  )
}

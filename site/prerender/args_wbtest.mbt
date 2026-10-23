///|
test "parse_args reads every flag" {
  let args = parse_args([
    "prerender", "--content", "../release", "--channel", "next", "--site-root", "/smithy/",
    "--release-version", "v0.5.0", "--ref", "abc", "--out", "dist/next",
  ])
  assert_eq(
    args,
    Ok({
      content: "../release",
      channel: Next,
      site_root: "/smithy/",
      base: None,
      release_version: "v0.5.0",
      git_ref: "abc",
      out: "dist/next",
    }),
  )
}

///|
test "parse_args rejects unknown flags and bad channels" {
  assert_true(parse_args(["prerender", "--bogus", "x"]) is Err(_))
  assert_true(parse_args(["prerender", "--channel", "beta"]) is Err(_))
}

///|
test "config_of derives bases from the site root" {
  let args = parse_args([
    "prerender", "--channel", "next", "--site-root", "/smithy",
  ]).unwrap()
  let c = config_of(args)
  assert_eq(c.base, "/smithy/next/")
  assert_eq(c.release_base, "/smithy/")
  assert_eq(c.version, "next")
}

///|
test "page_path places each route in its own directory" {
  assert_eq(page_path(Landing), "index.html")
  assert_eq(page_path(Doc("smithy-syntax")), "docs/smithy-syntax/index.html")
  assert_eq(page_path(DocsIndex), "docs/index.html")
}

///|
test "check_manifest rejects a manifest without pages" {
  let empty : @content.Manifest = { pages: [], }
  assert_eq(
    check_manifest(empty, "../nope"),
    Err("no docs pages found under ../nope"),
  )
}

///|
test "check_manifest accepts a manifest with only the CLI page" {
  let m : @content.Manifest = {
    pages: [
      {
        route: Doc("cli"),
        title: "C",
        source: "apps/smithy/README.md",
        group: Cli,
      },
    ],
  }
  assert_eq(check_manifest(m, "."), Ok(()))
}

///|
test "missing_sources names each fixed source that is not there" {
  let missing = missing_sources("/nonexistent-smithy-content", [
    "README.md", "docs/a.md",
  ])
  assert_eq(missing, ["README.md", "docs/a.md"])
}

///|
/// The landing page shows `site/landing/sample/`; the page text must equal the files.
test "the hero sample equals the files in landing/sample" {
  let sample = @shell.hero_sample()
  let read = path => {
    @fs.read_file_to_string("landing/sample/" + path) catch {
      _ => fail("I could not read landing/sample/\{path}")
    }
  }
  assert_eq(sample.model, read("order.smithy"))
  assert_eq(sample.value, read("order.json"))
  assert_eq(sample.command, read("command.txt"))
  assert_eq(sample.output, read("output.txt"))
}

///|
test "plan_sources fails when any fixed source is missing" {
  let all = @content.fixed_sources()
  assert_eq(plan_sources("/c", []), Ok(all))
  assert_eq(
    plan_sources("/c", ["README.md"]),
    Err("I could not find these source files under /c: README.md"),
  )
  assert_eq(
    plan_sources("/c", [all[0], all[1]]),
    Err("I could not find these source files under /c: \{all[0]}, \{all[1]}"),
  )
}

///|
test "parse_args reads --base and keeps it apart from the site root" {
  let args = parse_args([
    "prerender", "--channel", "next", "--site-root", "/smithy", "--base", "/smithy",
  ]).unwrap()
  let c = config_of(args)
  assert_eq(c.base, "/smithy/")
  assert_eq(c.channel, Next)
  assert_eq(c.version, "next")
  assert_eq(c.release_base, "/smithy/")
  assert_eq(c.next_base, "/smithy/next/")
}

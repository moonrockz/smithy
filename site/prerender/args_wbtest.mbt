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
      has_release: true,
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
/// The tests run with `site/` as the working directory, so `../README.md` is
/// the repository README.
test "missing_sources skips a file that exists" {
  let missing = missing_sources("..", ["README.md", "docs/nope-smithy.md"])
  assert_eq(missing, ["docs/nope-smithy.md"])
}

///|
/// The landing page shows `site/landing/sample/`; the page text must equal the files.
/// This test and the next ones read paths relative to `site/`: they assume that the
/// module root is the working directory.
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

///|
test "--no-release clears has_release, also as the last flag" {
  let args = parse_args(["prerender", "--no-release", "--channel", "next"]).unwrap()
  assert_eq(config_of(args).has_release, false)
  let last = parse_args(["prerender", "--channel", "next", "--no-release"]).unwrap()
  assert_eq(config_of(last).has_release, false)
  assert_eq(config_of(parse_args(["prerender"]).unwrap()).has_release, true)
}

///|
/// The examples of the repository, read as the build reads them. After the
/// examples task these are the six that had a README and the five that got one.
test "the repository examples with a README are the eleven documented ones" {
  let dirs = read_example_dirs("..") catch {
    _ => fail("I could not read ../examples")
  }
  let found = @content.Example::build(dirs)
  assert_eq(found.map(e => e.dir), [
    "authenticated-repositories", "github-release", "json-rpc", "maven-repository",
    "npm-archive", "npm-registry", "openrpc", "protocol-tests", "public-archive",
    "rpc-consumer", "validation-consumer",
  ])
  for e in found {
    assert_true(e.title != "", msg="\{e.dir} has no title")
    assert_true(e.summary != "", msg="\{e.dir} has no summary")
  }
  let rpc = found.iter().find_first(e => e.dir == "json-rpc").unwrap()
  assert_true(rpc.files.contains("transcripts/chat.json"))
  assert_true(rpc.files.contains("peers.smithy"))
  assert_true(!rpc.files.contains("README.md"))
  // A directory without a README is read but not published.
  assert_true(dirs.iter().any(d => d.dir == "local-resources"))
  assert_true(!found.iter().any(e => e.dir == "local-resources"))
}

///|
test "read_example_dirs: a tree without examples has none" {
  let dirs = read_example_dirs("/nonexistent-smithy-content") catch {
    _ => fail("a missing examples directory is not an error")
  }
  assert_eq(dirs.length(), 0)
}

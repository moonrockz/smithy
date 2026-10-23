///|
fn sample() -> SiteData {
  {
    config: {
      base: "/smithy/next/",
      version: "next",
      channel: Next,
      git_ref: "abc123",
      release_base: "/smithy/",
      next_base: "/smithy/next/",
      release_version: "v0.5.0",
    },
    pages: [
      {
        route: Doc("smithy-syntax"),
        title: "Configuration",
        source: "pkgs/smithy-syntax/README.mbt.md",
        group: Libraries,
      },
    ],
    route: Doc("smithy-syntax"),
    markdown: Some("# Configuration\n\nQuote \" < > & </script> done\n"),
  }
}

///|
test "encode and decode round-trip, including HTML-special text" {
  let data = sample()
  assert_eq(SiteData::decode(data.encode()), Some(data))
}

///|
test "decode rejects invalid input" {
  assert_eq(SiteData::decode(""), None)
  assert_eq(SiteData::decode("{\"config\": 1}"), None)
}

///|
test "link_context resolves published sources only" {
  let data = sample()
  let ctx = link_context(data.config, data.manifest(), "apps/smithy/README.md")
  assert_eq(
    (ctx.resolve)("pkgs/smithy-syntax/README.mbt.md"),
    Some(Doc("smithy-syntax")),
  )
  assert_eq((ctx.resolve)("docs/plans/x.md"), None)
  assert_eq(ctx.git_ref, "abc123")
  assert_eq(ctx.repo_url, github_repo)
}

///|
test "decode rejects an unknown channel" {
  let json = Json(sample())
  let text = json.stringify().replace_all(old="\"Next\"", new="\"Beta\"")
  assert_true(text != json.stringify())
  assert_eq(SiteData::decode(text), None)
}

///|
test "decode rejects a missing required field" {
  let text = Json(sample())
    .stringify()
    .replace_all(old="\"git_ref\"", new="\"git_reference\"")
  assert_eq(SiteData::decode(text), None)
}

///|
test "a release page without markdown round-trips" {
  let data : SiteData = {
    ..sample(),
    config: {
      base: "/smithy/",
      version: "v0.5.0",
      channel: Release,
      git_ref: "v0.5.0",
      release_base: "/smithy/",
      next_base: "/smithy/next/",
      release_version: "v0.5.0",
    },
    route: Doc("cli"),
    markdown: None,
  }
  assert_eq(SiteData::decode(data.encode()), Some(data))
}

///|
test "link_context carries the given source" {
  let data = sample()
  let ctx = link_context(data.config, data.manifest(), "docs/guide/x.md")
  assert_eq(ctx.source, "docs/guide/x.md")
  assert_eq(ctx.git_ref, "abc123")
}

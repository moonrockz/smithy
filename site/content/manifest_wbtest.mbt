///|
test "classify: guides, the CLI, libraries and the cookbook are published" {
  assert_eq(
    classify("docs/guide/getting-started.md"),
    Some((Doc("getting-started"), Guides)),
  )
  assert_eq(
    classify("./docs/guide/getting-started.mbt.md"),
    Some((Doc("getting-started"), Guides)),
  )
  assert_eq(classify("apps/smithy/README.md"), Some((Doc("cli"), Cli)))
  assert_eq(
    classify("pkgs/smithy-syntax/README.mbt.md"),
    Some((Doc("smithy-syntax"), Libraries)),
  )
  assert_eq(
    classify("pkgs/smithy-validation/rpc/README.mbt.md"),
    Some((Doc("smithy-validation-rpc"), Libraries)),
  )
  assert_eq(
    classify("pkgs/smithy/protocoltests/README.mbt.md"),
    Some((Doc("protocol-tests"), Libraries)),
  )
  assert_eq(
    classify("docs/cookbook/parsing.mbt.md"),
    Some((Doc("parsing"), Cookbook)),
  )
}

///|
test "classify: other files are not published" {
  assert_eq(classify("README.md"), None)
  assert_eq(classify("docs/guide/nested/x.md"), None)
  assert_eq(classify("docs/guide/Bad Name.md"), None)
  assert_eq(classify("docs/guide/start.txt"), None)
  assert_eq(classify("docs/cookbook/README.md"), None)
  assert_eq(classify("docs/migrations/2026-10-22-openrpc-library.md"), None)
  assert_eq(classify("pkgs/smithy-syntax/README.md"), None)
  assert_eq(classify("apps/smithy/OTHER.md"), None)
}

///|
test "classify: the never-publish list wins over every rule" {
  let paths = [
    "docs/superpowers/plans/x.md", "docs/superpowers/specs/x.md", "docs/spikes/x.md",
    ".dev/docs/x.md", ".dev/x.md", "pkgs/smithy-syntax/DESIGN.md", "docs/guide/DESIGN.md",
    "docs/guide/AGENTS.md", "docs/guide/CONTEXT.md", "AGENTS.md", "CONTEXT.md", "pkgs/smithy-syntax/tests/tck/x.md",
    "tests/tck/x.md",
  ]
  for p in paths {
    assert_eq(is_excluded(p), true)
    assert_eq(classify(p), None)
  }
  assert_eq(is_excluded("docs/guide/start.md"), false)
}

///|
test "excluded names are not published even when listed as a source" {
  let m = Manifest::build([
    { path: "docs/guide/DESIGN.md", title: "Design", },
    { path: "docs/guide/AGENTS.md", title: "Agents", },
    { path: "docs/superpowers/plans/p.md", title: "Plan", },
    { path: "tests/tck/x.md", title: "Tck", },
  ])
  assert_eq(m.pages.length(), 0)
}

///|
fn all_files() -> Array[SourceFile] {
  [
    { path: "docs/cookbook/diagnostics.mbt.md", title: "Report problems", },
    { path: "pkgs/smithy/README.mbt.md", title: "smithy", },
    { path: "docs/guide/zzz-extra.md", title: "Extra", },
    { path: "pkgs/smithy-syntax/README.mbt.md", title: "smithy-syntax", },
    { path: "docs/guide/install.mbt.md", title: "Install", },
    { path: "apps/smithy/README.md", title: "smithy CLI", },
    { path: "docs/cookbook/parsing.mbt.md", title: "Parse a model", },
    { path: "docs/plans/secret.md", title: "Secret", },
  ]
}

///|
test "build: guides by slug, then CLI, libraries and cookbook in table order" {
  let m = Manifest::build(all_files())
  assert_eq(m.pages.map(p => p.route), [
    Doc("install"),
    Doc("zzz-extra"),
    Doc("cli"),
    Doc("smithy-syntax"),
    Doc("smithy"),
    Doc("parsing"),
    Doc("diagnostics"),
  ])
  assert_eq(m.pages[0].source, "docs/guide/install.mbt.md")
  assert_eq(m.pages[0].title, "Install")
}

///|
test "build: a tree without docs/guide has no Guides group" {
  let m = Manifest::build(
    all_files().filter(f => !f.path.has_prefix("docs/guide/")),
  )
  assert_eq(m.pages.filter(p => p.group is Guides).length(), 0)
  assert_eq(m.pages[0].route, Doc("cli"))
  assert_eq(m.groups().map(g => g.0), [Cli, Libraries, Cookbook])
}

///|
test "build: a tree with docs/guide starts with the Guides group" {
  let m = Manifest::build(all_files())
  assert_eq(m.groups().map(g => g.0), [Guides, Cli, Libraries, Cookbook])
  assert_eq(m.groups()[0].1.map(p => p.route), [
    Doc("install"),
    Doc("zzz-extra"),
  ])
}

///|
test "build: an empty tree has no pages and no groups" {
  let m = Manifest::build([])
  assert_eq(m.pages.length(), 0)
  assert_eq(m.groups().length(), 0)
  assert_eq(m.default_route(), Doc("cli"))
}

///|
test "default_route: the first guide, or the CLI while Guides is empty" {
  assert_eq(Manifest::build(all_files()).default_route(), Doc("install"))
  let no_guides = Manifest::build(
    all_files().filter(f => !f.path.has_prefix("docs/guide/")),
  )
  assert_eq(no_guides.default_route(), Doc("cli"))
}

///|
test "resolve: only the docs index changes" {
  let m = Manifest::build(all_files())
  assert_eq(m.resolve(DocsIndex), Doc("install"))
  assert_eq(m.resolve(Doc("cli")), Doc("cli"))
  assert_eq(m.resolve(Landing), Landing)
}

///|
test "source_paths: the fixed pages in sidebar order" {
  let paths = fixed_sources()
  assert_eq(paths[0], "apps/smithy/README.md")
  assert_eq(paths.length(), 1 + 13 + 3)
  assert_eq(paths.contains("pkgs/smithy-validation/rpc/README.mbt.md"), true)
  assert_eq(paths.contains("pkgs/smithy/protocoltests/README.mbt.md"), true)
}

///|
test "find, find_source and neighbors" {
  let m = Manifest::build(all_files())
  assert_eq(m.find(Doc("smithy")).map(p => p.title), Some("smithy"))
  assert_eq(
    m.find_source("./pkgs/smithy-syntax/README.mbt.md").map(p => p.route),
    Some(Doc("smithy-syntax")),
  )
  assert_eq(m.find_source("docs/plans/secret.md"), None)
  let (prev, next) = m.neighbors(Doc("cli"))
  assert_eq(prev.map(p => p.route), Some(Doc("zzz-extra")))
  assert_eq(next.map(p => p.route), Some(Doc("smithy-syntax")))
  let (first_prev, _) = m.neighbors(Doc("install"))
  assert_eq(first_prev, None)
  let (_, last_next) = m.neighbors(Doc("diagnostics"))
  assert_eq(last_next, None)
  assert_eq(m.neighbors(Doc("nope")).0, None)
}

///|
test "Page round-trips through JSON" {
  let page : Page = {
    route: Doc("cli"),
    title: "smithy CLI",
    source: "apps/smithy/README.md",
    group: Cli,
  }
  let back : Page = @json.from_json(Json(page))
  assert_eq(back, page)
}

///|
fn site_ctx(source : String) -> LinkContext {
  {
    source,
    resolve: path => {
      match path {
        "pkgs/smithy-syntax/README.mbt.md" => Some(Doc("smithy-syntax"))
        "pkgs/smithy/README.mbt.md" => Some(Doc("smithy"))
        "docs/cookbook/parsing.mbt.md" => Some(Doc("parsing"))
        "apps/smithy/README.md" => Some(Doc("cli"))
        _ => None
      }
    },
    repo_url: "https://github.com/moonrockz/smithy",
    git_ref: "v0.5.0",
  }
}

///|
test "resolve_path normalizes relative paths" {
  assert_eq(resolve_path("docs/cookbook/a.md", "b.md"), "docs/cookbook/b.md")
  assert_eq(resolve_path("docs/cookbook/a.md", "./b.md"), "docs/cookbook/b.md")
  assert_eq(
    resolve_path(
      "docs/cookbook/parsing.mbt.md", "../../pkgs/smithy/README.mbt.md",
    ),
    "pkgs/smithy/README.mbt.md",
  )
  assert_eq(resolve_path("docs/cookbook/a.md", "../../README.md"), "README.md")
  assert_eq(resolve_path("docs/cookbook/a.md", "../../../x.md"), "x.md")
  assert_eq(resolve_path("", "docs/cookbook/a.md"), "docs/cookbook/a.md")
}

///|
test "links to published pages become site routes" {
  let ctx = site_ctx("docs/cookbook/diagnostics.mbt.md")
  assert_eq(rewrite_link("parsing.mbt.md", ctx), Internal(Doc("parsing"), None))
  assert_eq(
    rewrite_link("./parsing.mbt.md#parse-a-model", ctx),
    Internal(Doc("parsing"), Some("parse-a-model")),
  )
  assert_eq(
    rewrite_link("../../pkgs/smithy-syntax/README.mbt.md#scanner", ctx),
    Internal(Doc("smithy-syntax"), Some("scanner")),
  )
  assert_eq(
    rewrite_link("../../apps/smithy/README.md", ctx),
    Internal(Doc("cli"), None),
  )
  assert_eq(
    rewrite_link("/pkgs/smithy/README.mbt.md#version", ctx),
    Internal(Doc("smithy"), Some("version")),
  )
}

///|
test "a link between two libraries is a site route" {
  let ctx = site_ctx("pkgs/smithy-syntax/README.mbt.md")
  assert_eq(
    rewrite_link("../smithy/README.mbt.md#x", ctx),
    Internal(Doc("smithy"), Some("x")),
  )
}

///|
test "anchors and absolute URLs stay as they are" {
  let ctx = site_ctx("docs/cookbook/diagnostics.mbt.md")
  assert_eq(rewrite_link("#codegen-mode", ctx), Anchor("codegen-mode"))
  assert_eq(
    rewrite_link("https://mooncakes.io/", ctx),
    External("https://mooncakes.io/"),
  )
  assert_eq(rewrite_link("mailto:a@b.c", ctx), External("mailto:a@b.c"))
}

///|
test "other repository files become GitHub links at the build ref" {
  let ctx = site_ctx("docs/cookbook/diagnostics.mbt.md")
  assert_eq(
    rewrite_link("../superpowers/specs/x.md", ctx),
    External(
      "https://github.com/moonrockz/smithy/blob/v0.5.0/docs/superpowers/specs/x.md",
    ),
  )
  assert_eq(
    rewrite_link("../../pkgs/smithy-syntax/DESIGN.md#scanner", ctx),
    External(
      "https://github.com/moonrockz/smithy/blob/v0.5.0/pkgs/smithy-syntax/DESIGN.md#scanner",
    ),
  )
  assert_eq(
    rewrite_link("../../examples/json-rpc/peers.smithy", ctx),
    External(
      "https://github.com/moonrockz/smithy/blob/v0.5.0/examples/json-rpc/peers.smithy",
    ),
  )
  assert_eq(
    rewrite_link("../../examples/json-rpc/", ctx),
    External(
      "https://github.com/moonrockz/smithy/tree/v0.5.0/examples/json-rpc",
    ),
  )
  assert_eq(
    rewrite_link("unpublished.mbt.md", ctx),
    External(
      "https://github.com/moonrockz/smithy/blob/v0.5.0/docs/cookbook/unpublished.mbt.md",
    ),
  )
}

///|
test "relative images load from raw GitHub" {
  let ctx = site_ctx("docs/cookbook/parsing.mbt.md")
  assert_eq(
    image_src("img/flow.png", ctx),
    "https://raw.githubusercontent.com/moonrockz/smithy/v0.5.0/docs/cookbook/img/flow.png",
  )
  assert_eq(
    image_src("https://example.com/a.png", ctx),
    "https://example.com/a.png",
  )
  assert_eq(
    image_src("data:image/png;base64,AAA", ctx),
    "data:image/png;base64,AAA",
  )
  assert_eq(image_src("javascript:alert(1)", ctx), "")
  assert_eq(image_src("JavaScript:alert(1)", ctx), "")
  assert_eq(image_src("vbscript:x", ctx), "")
  assert_eq(image_src("data:text/html,x", ctx), "")
  assert_eq(
    image_src("data:image/svg+xml;base64,AA", ctx),
    "data:image/svg+xml;base64,AA",
  )
}

///|
test "parse applies link rewriting" {
  let doc = parse(
    "See [syntax](../../pkgs/smithy-syntax/README.mbt.md#x).",
    site_ctx("docs/cookbook/parsing.mbt.md"),
  )
  assert_eq(doc.blocks, [
    Paragraph([
      Text("See "),
      Link(Internal(Doc("smithy-syntax"), Some("x")), [Text("syntax")]),
      Text("."),
    ]),
  ])
}

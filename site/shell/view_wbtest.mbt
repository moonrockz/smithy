///|
/// `App::render` exists only on native; these tests skip the JS target.
#cfg(not(target="js"))
async fn render_route(route : @route.Route, markdown : String?) -> String {
  let data = site_data(route, markdown)
  let json = data.encode()
  @rabbita.new(() => component(data, json)).render(
    url="http://localhost" + @route.href(data.config.base, route),
  )
}

///|
#cfg(not(target="js"))
async test "landing page renders hero, sections and install tabs" {
  let html = render_route(Landing, None)
  assert_true(html.contains("Smithy IDL 2.0 for MoonBit"))
  assert_true(html.contains("<em>validated</em>"))
  assert_true(html.contains("mise use -g github:moonrockz/smithy"))
  assert_true(html.contains("name=\"smithy-data\""))
  assert_true(html.contains("/smithy/index.js"))
}

///|
#cfg(not(target="js"))
async test "landing page has every section heading and both buttons" {
  let html = render_route(Landing, None)
  for
    heading in [
      "Pick the job you came for", "One toolchain, every target", "Get the CLI or the library",
      "Start from a working project",
    ] {
    assert_true(html.contains("<h2>" + heading + "</h2>"))
  }
  assert_true(html.contains(">Get started</a>"))
  assert_true(html.contains(">Try the playground</a>"))
  assert_true(html.contains("href=\"/smithy/docs/\""))
  assert_true(html.contains("href=\"/smithy/docs/smithy-syntax/\""))
  assert_true(html.contains("href=\"/smithy/docs/smithy-validation/\""))
  assert_true(
    html.contains(
      "Smithy is an open source project by AWS. This is an independent MoonBit implementation.",
    ),
  )
}

///|
#cfg(not(target="js"))
async test "landing page has six feature tiles, one for the playground" {
  let html = render_route(Landing, None)
  assert_eq(html.split("class=\"ms-tile\"").count(), 7)
  assert_true(
    html.contains(
      "<h3>Runs in the browser</h3><p>The playground runs the same packages client-side. Nothing is uploaded.</p>",
    ),
  )
}

///|
#cfg(not(target="js"))
async test "landing page has the playground teaser before the examples" {
  let html = render_route(Landing, None)
  guard html.find("<h2>Try it without installing</h2>") is Some(teaser) else {
    fail("no playground teaser")
  }
  guard html.find("<h2>Start from a working project</h2>") is Some(examples) else {
    fail("no examples section")
  }
  assert_true(teaser < examples)
  assert_true(
    html.contains(
      "href=\"/smithy/playground/\" target=\"_self\" class=\"ms-btn ms-btn-primary\">Open the playground →</a>",
    ),
  )
  assert_true(html.contains("example.peers#Intger"))
}

///|
#cfg(not(target="js"))
async test "the nav and the hero button link to the playground" {
  let html = render_route(Landing, None)
  assert_true(
    html.contains(
      "<a href=\"/smithy/playground/\" target=\"_self\">Playground</a>",
    ),
  )
  assert_true(
    html.contains(
      "href=\"/smithy/playground/\" target=\"_self\" class=\"ms-btn\">Try the playground</a>",
    ),
  )
}

///|
#cfg(not(target="js"))
async test "the nav names Docs, Examples and API and has the GitHub icon button" {
  let html = render_route(Landing, None)
  assert_true(html.contains(">Docs</a>"))
  assert_true(html.contains(">Examples</a>"))
  assert_true(html.contains("https://mooncakes.io/docs/moonrockz/smithy"))
  assert_true(html.contains("aria-label=\"GitHub\""))
  assert_true(html.contains("smithy<span class=\"ms-accent\">.mbt</span>"))
  assert_true(!html.contains("moon<span"))
}

///|
#cfg(not(target="js"))
async test "no page shows the arrow character" {
  assert_true(!render_route(Landing, None).contains("↗"))
  assert_true(
    !render_route(Doc("smithy-syntax"), Some("# S\n")).contains("↗"),
  )
  assert_true(!render_route(Doc("nope"), None).contains("↗"))
}

///|
#cfg(not(target="js"))
async test "the hero shows the sample model, command and finding" {
  let html = render_route(Landing, None)
  let sample = hero_sample()
  assert_true(html.contains("order.smithy"))
  assert_true(html.contains("smithy validate value --shape example#Order"))
  assert_true(
    html.contains("<span class=\"ms-term-error\">error[Range]</span>"),
  )
  assert_true(
    html.contains("I expected the number to satisfy the modeled range."),
  )
  assert_eq(sample.output.trim_end().to_owned().split("\n").count(), 1)
}

///|
#cfg(not(target="js"))
async test "docs page renders sidebar, article, toc and edit link" {
  let md = "# Configuration\n\n## Config File\n\nSee [start](../../apps/smithy/README.md).\n\n```moonbit\nlet x = 1\n```\n"
  let html = render_route(Doc("smithy-syntax"), Some(md))
  assert_true(html.contains("smithy CLI"))
  assert_true(html.contains("id=\"config-file\""))
  assert_true(html.contains("href=\"/smithy/docs/cli/\""))
  assert_true(html.contains("On this page"))
  assert_true(html.contains("edit/main/pkgs/smithy-syntax/README.mbt.md"))
  assert_true(html.contains("tk-kw"))
}

///|
#cfg(not(target="js"))
async test "unknown pages render the not-found view" {
  let html = render_route(Doc("nope"), None)
  assert_true(html.contains("Page not found"))
  assert_true(html.contains("This page does not exist."))
  assert_true(html.contains("Docs (next)"))
  assert_true(html.contains("href=\"/smithy/next/docs/"))
  assert_true(html.contains("href=\"/smithy/docs/"))
  assert_true(!html.contains("does not exist in"))
}

///|
#cfg(not(target="js"))
async test "the menu button appears only where there is a sidebar" {
  assert_true(!render_route(Landing, None).contains("ms-menu"))
  assert_true(!render_route(Doc("nope"), None).contains("ms-menu"))
  assert_true(
    render_route(Doc("smithy-syntax"), Some("# C\n")).contains("ms-menu"),
  )
}

///|
#cfg(not(target="js"))
async test "an open phone menu renders a backdrop" {
  let m = Model::init(site_data(Doc("smithy-syntax"), Some("# C\n")))
  assert_true(!render_model(m).contains("ms-sidebar-backdrop"))
  assert_true(
    render_model({ ..m, menu_open: true, }).contains("ms-sidebar-backdrop"),
  )
}

///|
test "target_href" {
  assert_eq(
    target_href("/smithy/", Internal(Doc("x"), Some("a"))),
    "/smithy/docs/x/#a",
  )
  assert_eq(target_href("/smithy/", Anchor("a")), "#a")
  assert_eq(target_href("/smithy/", External("https://e.com")), "https://e.com")
}

///|
#cfg(not(target="js"))
async test "head starts with the stored-theme script" {
  let html = render_route(Landing, None)
  let head = html.find("<head>").unwrap()
  let script = html.find("localStorage.getItem('smithy-theme')").unwrap()
  let css = html.find("styles.css").unwrap()
  assert_true(head < script && script < css)
  assert_true(html.contains("dataset.theme"))
}

///|
#cfg(not(target="js"))
async test "initial_theme sets the theme attribute on the first render" {
  let data = site_data(Landing, None)
  let html = @rabbita.new(() => {
    component(data, data.encode(), initial_theme=Dark)
  }).render(url="http://localhost/smithy/")
  assert_true(html.contains("data-theme=\"dark\""))
}

///|
#cfg(not(target="js"))
async test "search dialog, install tabs and heading anchors carry ARIA" {
  let landing = render_route(Landing, None)
  assert_true(landing.contains("role=\"tablist\""))
  assert_true(landing.contains("aria-selected=\"true\""))
  assert_true(landing.contains("aria-selected=\"false\""))
  assert_true(landing.contains("id=\"ms-search-btn\""))
  let docs = render_route(Doc("smithy-syntax"), Some("# Configuration\n"))
  assert_true(docs.contains("aria-hidden=\"true\""))
  assert_true(docs.contains("tabindex=\"-1\""))
}

///|
/// Renders the page with the model's state fixed to `m`.
#cfg(not(target="js"))
async fn render_model(m : Model) -> String {
  let json = site_data(m.route, None).encode()
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state(m, update~)
    model.map(m => view(m, emit, json))
  }).render(url="http://localhost/smithy/")
}

///|
#cfg(not(target="js"))
async test "the open search dialog is modal and marks the selection" {
  let m = Model::init(site_data(Landing, None))
  let html = render_model({ ..m, search: { ..m.search, open: true, }, })
  assert_true(html.contains("role=\"dialog\""))
  assert_true(html.contains("aria-modal=\"true\""))
}

///|
#cfg(not(target="js"))
async test "the search modal marks the selected result and the hits" {
  let m = step(searching(), MoveSelection(1))
  let html = render_model(m)
  // One selected item, and it is the second result.
  let first = html.find("ms-search-selected").unwrap()
  assert_true(!html[first + 1:].to_owned().contains("ms-search-selected"))
  assert_true(
    html.contains(
      "href=\"/smithy/docs/smithy-syntax/#two\" target=\"_self\" class=\"ms-search-item ms-search-selected\"",
    ),
  )
  assert_true(html.contains("<mark>needle</mark>"))
  assert_true(html.contains("ms-search-item"))
}

///|
#cfg(not(target="js"))
async test "the next banner appears only on the next channel" {
  let m = Model::init(site_data(Doc("smithy-syntax"), Some("# C\n")))
  assert_true(!render_model(m).contains("ms-banner"))
  let next : Model = {
    ..m,
    config: {
      ..m.config,
      channel: Next,
      base: "/smithy/next/",
      version: "next",
    },
  }
  let html = render_model(next)
  assert_true(html.contains("ms-banner"))
  assert_true(html.contains("docs for main (unreleased)"))
  assert_true(html.contains("Go to the v0.5.0 docs."))
}

///|
#cfg(not(target="js"))
async test "the version picker marks the current version" {
  let m = Model::init(site_data(Doc("smithy-syntax"), Some("# C\n")))
  let release = render_model(m)
  assert_true(release.contains("ms-version-link ms-version-current"))
  assert_true(
    release.contains("class=\"ms-version-link ms-version-current\">v0.5.0</a>"),
  )
  assert_true(!release.contains("ms-version-current\">next"))
  let next = render_model({
    ..m,
    config: { ..m.config, channel: Next, base: "/smithy/next/", },
  })
  assert_true(
    next.contains(
      "href=\"/smithy/next/docs/smithy-syntax/\" target=\"_self\" class=\"ms-version-link ms-version-current\">next</a>",
    ),
  )
  // The release link is the same page on the release channel.
  assert_true(
    next.contains(
      "href=\"/smithy/docs/smithy-syntax/\" target=\"_self\" class=\"ms-version-link\">v0.5.0</a>",
    ),
  )
}

///|
#cfg(not(target="js"))
async test "loading and failed pages render their texts" {
  let m = Model::init(site_data(Doc("smithy-syntax"), None))
  assert_true(render_model(m).contains("Loading…"))
  let failed = render_model({ ..m, page: PageFailed, })
  assert_true(failed.contains("This page could not be loaded."))
  assert_true(failed.contains("Read it on GitHub"))
}

///|
#cfg(not(target="js"))
async test "each install tab shows its own commands" {
  let m = Model::init(site_data(Landing, None))
  let moonx = "moonx moonrockz/smithy-cli@latest --help"
  assert_true(!render_model(m).contains(moonx))
  assert_true(render_model({ ..m, install_tab: Moonx, }).contains(moonx))
  assert_true(
    render_model({ ..m, install_tab: Library, }).contains(
      "moon add moonrockz/smithy-syntax",
    ),
  )
  assert_true(
    render_model({ ..m, install_tab: Download, }).contains(
      "releases/latest/download/smithy-linux-x64.tar.gz",
    ),
  )
}

///|
#cfg(not(target="js"))
async test "sidebar shows the groups that have pages, then the reference links" {
  let html = render_route(Doc("smithy-syntax"), Some("# S\n"))
  assert_true(html.contains(">CLI<"))
  assert_true(html.contains(">Libraries<"))
  assert_true(!html.contains(">Guides<"))
  assert_true(!html.contains(">Migration<"))
  assert_true(html.contains("CHANGELOG.md"))
  assert_true(html.contains("Releases"))
}

///|
#cfg(not(target="js"))
async test "the next banner links to the same page in the release docs" {
  let m = Model::init(site_data(Doc("smithy-syntax"), Some("# C\n")))
  let next = render_model({
    ..m,
    config: {
      ..m.config,
      channel: Next,
      base: "/smithy/next/",
      version: "next",
    },
  })
  assert_true(next.contains("href=\"/smithy/docs/smithy-syntax/\""))
  assert_true(next.contains("Go to the v0.5.0 docs."))
}

///|
#cfg(not(target="js"))
async test "with no release, the root and next name no release and link to none" {
  let m = Model::init(site_data(Doc("smithy-syntax"), Some("# C\n")))
  for base in ["/smithy/", "/smithy/next/"] {
    let html = render_model({
      ..m,
      config: {
        ..m.config,
        channel: Next,
        base,
        version: "next",
        git_ref: "abc",
        has_release: false,
      },
    })
    assert_true(html.contains("No release has docs yet."))
    assert_true(!html.contains(">v0.5.0<"))
    assert_true(!html.contains("Go to the"))
    assert_true(html.contains("ms-version-current\">next</span>"))
  }
}

///|
#cfg(not(target="js"))
async test "with no release, the not found page links only to the next docs" {
  let m = Model::init(site_data(NotFound("/x/"), None))
  let html = render_model({
    ..m,
    config: { ..m.config, channel: Next, has_release: false, },
  })
  assert_true(!html.contains("Docs (v0.5.0)"))
  assert_true(html.contains("Docs (next)"))
}

///|
#cfg(not(target="js"))
async test "the examples index has one card for each example" {
  let html = render_route(Examples, None)
  assert_true(html.contains("<h1>Start from a working project</h1>"))
  assert_true(html.contains("href=\"/smithy/examples/openrpc/\""))
  assert_true(html.contains("href=\"/smithy/examples/json-rpc/\""))
  assert_true(html.contains("<b>Export a service as OpenRPC</b>"))
  assert_true(
    html.contains("Generate an OpenRPC 1.3.2 document from a service."),
  )
  assert_true(html.contains("<title>Examples — smithy</title>"))
  assert_true(!html.contains("ms-menu"))
}

///|
#cfg(not(target="js"))
async test "an example page shows the README, then the files at the build ref" {
  let html = render_route(
    Example("openrpc"),
    Some(
      "# Export a service as OpenRPC\n\nSee [JSON-RPC](../json-rpc/README.md).\n",
    ),
  )
  assert_true(html.contains("Export a service as OpenRPC"))
  assert_true(html.contains("href=\"/smithy/examples/json-rpc/\""))
  assert_true(html.contains("<h2>Files</h2>"))
  assert_true(
    html.contains(
      "href=\"https://github.com/moonrockz/smithy/blob/v0.5.0/examples/openrpc/model.smithy\"",
    ),
  )
  assert_true(
    html.contains(
      "href=\"https://github.com/moonrockz/smithy/tree/v0.5.0/examples/openrpc\"",
    ),
  )
  assert_true(!html.contains("/tree/main/"))
  assert_true(
    html.contains("<title>Export a service as OpenRPC — smithy</title>"),
  )
  assert_true(html.contains("href=\"/smithy/examples/\""))
}

///|
#cfg(not(target="js"))
async test "an example without other files has no Files section" {
  let html = render_route(Example("json-rpc"), Some("# Validate JSON-RPC\n"))
  assert_true(!html.contains("<h2>Files</h2>"))
}

///|
#cfg(not(target="js"))
async test "an unknown example renders the not-found view" {
  assert_true(render_route(Example("nope"), None).contains("Page not found"))
}

///|
#cfg(not(target="js"))
async test "the nav, the hero button and the cards use the examples routes" {
  let html = render_route(Landing, None)
  assert_true(
    html.contains("<a href=\"/smithy/examples/\" target=\"_self\">Examples</a>"),
  )
  assert_true(html.contains("href=\"/smithy/examples/openrpc/\""))
  assert_true(html.contains("href=\"/smithy/examples/json-rpc/\""))
  assert_true(html.contains("2 examples with a README."))
  // No page for this directory in the test data: the card links to GitHub at the ref.
  assert_true(
    html.contains(
      "href=\"https://github.com/moonrockz/smithy/tree/v0.5.0/examples/ion-validation-consumer\"",
    ),
  )
  assert_true(!html.contains("/tree/main/"))
}

///|
test "the download tab shows a command for GNU and one for macOS" {
  assert_true(
    install_download.contains("sha256sum -c --ignore-missing checksums.txt"),
  )
  assert_true(
    install_download.contains("shasum -a 256 -c --ignore-missing checksums.txt"),
  )
}

///|
#cfg(not(target="js"))
async fn next_view(
  route : @route.Route,
  counterpart : Counterpart,
  markdown : String?,
) -> String {
  let m = Model::init(site_data(route, markdown))
  render_model({
    ..m,
    config: { ..m.config, channel: Next, base: "/smithy/next/", },
    counterpart,
  })
}

///|
#cfg(not(target="js"))
async fn render_playground() -> String {
  let data = {
    ..site_data(Playground, None),
    playground: Some({
      version: "0.0.1",
      worker: "/smithy/playground/worker.js",
      samples: [
        { title: "Good", path: "a.smithy", model: "namespace a\n", },
        {
          title: "With a mistake",
          path: "b.smithy",
          model: "namespace b\nstructure S {",
        },
      ],
      selected: 1,
    }),
  }
  @rabbita.new(() => component(data, data.encode())).render(
    url="http://localhost/smithy/playground/",
  )
}

///|
#cfg(not(target="js"))
async test "a next page the release lacks links the release to its docs index" {
  let html = next_view(
    Doc("smithy-syntax"),
    Missing(Doc("smithy-syntax")),
    Some("# C\n"),
  )
  assert_true(
    html.contains(
      "href=\"/smithy/docs/\" target=\"_self\" class=\"ms-version-link\">v0.5.0</a>",
    ),
  )
  assert_true(
    html.contains(
      "href=\"/smithy/docs/\" target=\"_self\">Go to the v0.5.0 docs.",
    ),
  )
  assert_true(!html.contains("href=\"/smithy/docs/smithy-syntax/\""))
  // The current channel still links to itself.
  assert_true(html.contains("href=\"/smithy/next/docs/smithy-syntax/\""))
}

///|
#cfg(not(target="js"))
async test "the playground page has the empty workbench and its script" {
  let html = render_playground()
  assert_true(html.contains("<title>Playground — smithy</title>"))
  assert_true(html.contains("id=\"pg-app\""))
  assert_true(html.contains("id=\"pg-editor\""))
  assert_true(
    html.contains("<option value=\"1\" selected>With a mistake</option>"),
  )
  for label in ["Validate", "Transform", "Transcript", "Runs in your browser"] {
    assert_true(html.contains(label))
  }
  assert_true(html.contains("smithy 0.0.1 · no server"))
  assert_true(html.contains("The model is being checked."))
  // The Transform tab is in the page, and its output editor has its element.
  for
    text in [
      "id=\"pg-output\"", "id=\"pg-output-kind\"", "<option value=\"openapi-3.1.0\">OpenAPI 3.1.0</option>",
      "CLI: smithy convert --to json model.smithy", "id=\"pg-run\"", "Choose an output, then select Run.",
    ] {
    assert_true(html.contains(text))
  }
  assert_true(html.contains("src=\"/smithy/playground/ui.js\""))
  // The site nav is on the page.
  assert_true(html.contains("class=\"ms-nav\""))
}

///|
#cfg(not(target="js"))
async test "a next page the release lacks outside the docs links the release home" {
  let html = next_view(Examples, Missing(Examples), None)
  assert_true(
    html.contains(
      "href=\"/smithy/\" target=\"_self\" class=\"ms-version-link\">v0.5.0</a>",
    ),
  )
  assert_true(!html.contains("href=\"/smithy/examples/\""))
}

///|
#cfg(not(target="js"))
async test "unknown, present or stale results link page for page" {
  for c in [Unknown, Present(Doc("smithy-syntax")), Missing(Doc("cli"))] {
    let html = next_view(Doc("smithy-syntax"), c, Some("# C\n"))
    assert_true(
      html.contains(
        "href=\"/smithy/docs/smithy-syntax/\" target=\"_self\" class=\"ms-version-link\">v0.5.0</a>",
      ),
    )
    assert_true(
      html.contains(
        "href=\"/smithy/docs/smithy-syntax/\" target=\"_self\">Go to the v0.5.0 docs.",
      ),
    )
  }
}

///|
#cfg(not(target="js"))
async test "no other page loads the playground script" {
  for
    page in [
      render_route(Landing, None),
      render_route(Doc("smithy-syntax"), Some("# S\n")),
      render_route(Examples, None),
      render_route(Doc("nope"), None),
    ] {
    assert_false(page.contains("playground/ui.js"))
    assert_false(page.contains("id=\"pg-app\""))
  }
}

///|
#cfg(not(target="js"))
async test "a release page the next lacks links next to its docs index" {
  let m = Model::init(site_data(Doc("cli"), Some("# C\n")))
  let html = render_model({ ..m, counterpart: Missing(Doc("cli")), })
  assert_true(
    html.contains(
      "href=\"/smithy/next/docs/\" target=\"_self\" class=\"ms-version-link\">next</a>",
    ),
  )
}

///|
#cfg(not(target="js"))
async test "the playground page without its data shows a message" {
  let html = render_route(Playground, None)
  assert_true(html.contains("The playground could not start"))
}

///|
fn noop_emit() -> @rabbita.Emit[Msg] {
  @cmd.Emit(_ => @rabbita.none)
}

///|
fn site_data(route : @route.Route, markdown : String?) -> @data.SiteData {
  {
    config: {
      base: "/smithy/",
      version: "v0.5.0",
      channel: Release,
      git_ref: "v0.5.0",
      release_base: "/smithy/",
      next_base: "/smithy/next/",
      release_version: "v0.5.0",
      has_release: true,
    },
    pages: [
      {
        route: Doc("cli"),
        title: "smithy CLI",
        source: "apps/smithy/README.md",
        group: Cli,
      },
      {
        route: Doc("smithy-syntax"),
        title: "Configuration",
        source: "pkgs/smithy-syntax/README.mbt.md",
        group: Libraries,
      },
    ],
    examples: [
      {
        dir: "openrpc",
        title: "Export a service as OpenRPC",
        summary: "Generate an OpenRPC 1.3.2 document from a service.",
        files: ["model.smithy", "smithy-build.json"],
      },
      { dir: "json-rpc", title: "Validate JSON-RPC", summary: "S", files: [], },
    ],
    route,
    markdown,
    playground: None,
  }
}

///|
fn step(m : Model, msg : Msg) -> Model {
  update(m, msg, noop_emit()).0
}

///|
test "init parses the current page" {
  let m = Model::init(
    site_data(Doc("smithy-syntax"), Some("# Configuration\n\n## A\n")),
  )
  match m.page {
    Ready(doc) => assert_eq(doc.title, "Configuration")
    _ => fail("expected a ready page")
  }
  assert_eq(Model::init(site_data(Landing, None)).page, NoContent)
}

///|
test "url changes inside the base switch routes" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/docs/smithy-syntax")),
  )
  assert_eq(m2.route, Doc("smithy-syntax"))
  assert_eq(m2.page, Loading)
  let m3 = step(
    m2,
    ContentLoaded(Doc("smithy-syntax"), Ok("# Configuration\n")),
  )
  assert_true(m3.page is Ready(_))
}

///|
test "url changes with a trailing slash switch routes" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/docs/smithy-syntax/")),
  )
  assert_eq(m2.route, Doc("smithy-syntax"))
  let config = m.config
  assert_eq(
    site_path(config, "/smithy/docs/smithy-syntax/"),
    Some("docs/smithy-syntax/"),
  )
  assert_eq(site_path(config, "/smithy/next/docs/x/"), None)
}

///|
test "url changes outside the base are ignored" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/next/docs/smithy-syntax")),
  )
  assert_eq(m2.route, Landing)
}

///|
test "unknown pages have no content" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(m, UrlChanged(@url.parse("http://localhost/smithy/docs/nope")))
  assert_eq(m2.route, Doc("nope"))
  assert_eq(m2.page, NoContent)
}

///|
test "stale content for another route is dropped" {
  let m = Model::init(
    site_data(Doc("smithy-syntax"), Some("# Configuration\n")),
  )
  let m2 = step(m, ContentLoaded(Doc("cli"), Ok("# Other\n")))
  assert_eq(m2.page, m.page)
}

///|
test "search opens, filters and closes" {
  let m = Model::init(site_data(Landing, None))
  let opened = step(m, OpenSearch)
  assert_true(opened.search.open)
  assert_eq(opened.search.index, LoadingIndex)
  let entries : Array[@search.Entry] = [
    {
      route: Doc("smithy-syntax"),
      anchor: "test_kind-string",
      page: "Configuration",
      path: ["test_kind (string)"],
      text: "kind of test file",
    },
  ]
  let ready = step(opened, IndexLoaded(Ok(Json(entries).stringify())))
  assert_true(ready.search.index is IndexReady(_))
  let typed = step(ready, SearchInput("test kind"))
  assert_eq(current_results(typed).length(), 1)
  let closed = step(typed, CloseSearch)
  assert_false(closed.search.open)
}

///|
test "a broken index shows the failure state" {
  let m = step(Model::init(site_data(Landing, None)), OpenSearch)
  assert_eq(step(m, IndexLoaded(Ok("not json"))).search.index, IndexFailed)
}

///|
test "selection stays within the results" {
  let m = Model::init(site_data(Landing, None))
  let moved = step(step(m, OpenSearch), MoveSelection(5))
  assert_eq(moved.search.selected, 0)
}

///|
test "theme cycles auto, dark, light" {
  let m = Model::init(site_data(Landing, None))
  assert_eq(step(m, ToggleTheme).theme, Dark)
  assert_eq(step(step(m, ToggleTheme), ToggleTheme).theme, Light)
  assert_eq(
    step(step(step(m, ToggleTheme), ToggleTheme), ToggleTheme).theme,
    Auto,
  )
  assert_eq(Theme::parse("dark"), Dark)
  assert_eq(Theme::parse("bogus"), Auto)
}

///|
test "entry_href builds route and anchor" {
  let config = site_data(Landing, None).config
  let e : @search.Entry = {
    route: Doc("smithy-syntax"),
    anchor: "a-b",
    page: "C",
    path: [],
    text: "",
  }
  assert_eq(entry_href(config, e), "/smithy/docs/smithy-syntax/#a-b")
  assert_eq(
    entry_href(config, { ..e, anchor: "", }),
    "/smithy/docs/smithy-syntax/",
  )
}

///|
test "a fragment waits for the content of another page" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(
    m,
    UrlChanged(
      @url.parse("http://localhost/smithy/docs/smithy-syntax#test_kind"),
    ),
  )
  assert_eq(m2.page, Loading)
  assert_eq(m2.pending_anchor, Some("test_kind"))
  let m3 = step(
    m2,
    ContentLoaded(Doc("smithy-syntax"), Ok("# Configuration\n")),
  )
  assert_true(m3.page is Ready(_))
  assert_eq(m3.pending_anchor, None)
}

///|
test "no fragment leaves nothing pending" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/docs/smithy-syntax")),
  )
  assert_eq(m2.pending_anchor, None)
}

///|
test "a same-page fragment scrolls at once and stays unpended" {
  let m = Model::init(
    site_data(Doc("smithy-syntax"), Some("# Configuration\n")),
  )
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/docs/smithy-syntax#a")),
  )
  assert_eq(m2.pending_anchor, None)
  assert_eq(m2.page, m.page)
}

///|
fn key(k : String, meta~ : Bool = false) -> Msg {
  KeyDown(
    @common.Keyboard::new(
      key=k,
      code="",
      alt_key=false,
      ctrl_key=false,
      shift_key=false,
      meta_key=meta,
      is_composing=false,
      repeat=false,
      location=0,
    ),
  )
}

///|
fn three_entries() -> Array[@search.Entry] {
  ["one", "two", "three"].map(a => {
    route: Doc("smithy-syntax"),
    anchor: a,
    page: "Configuration",
    path: [a],
    text: "needle in " + a,
  })
}

///|
/// A model with the search open, the index ready and three results for "needle".
fn searching() -> Model {
  let m = step(Model::init(site_data(Landing, None)), OpenSearch)
  let ready = step(m, IndexLoaded(Ok(Json(three_entries()).stringify())))
  step(ready, SearchInput("needle"))
}

///|
test "internal link requests inside the base keep the model" {
  let m = Model::init(site_data(Landing, None))
  let req = UrlRequested(
    Internal(@url.parse("http://localhost/smithy/docs/smithy-syntax/")),
  )
  assert_eq(step(m, req), m)
}

///|
test "link requests into the other channel keep the model" {
  let m = Model::init(site_data(Landing, None))
  let req = UrlRequested(
    Internal(@url.parse("http://localhost/smithy/next/docs/smithy-syntax/")),
  )
  assert_eq(step(m, req), m)
  assert_eq(step(m, req).route, Landing)
}

///|
test "ctrl or meta K and slash open search" {
  let m = Model::init(site_data(Landing, None))
  assert_true(step(m, key("k", meta=true)).search.open)
  assert_true(step(m, key("/")).search.open)
  assert_false(step(m, key("k")).search.open)
}

///|
test "Escape closes search" {
  let opened = step(Model::init(site_data(Landing, None)), key("/"))
  assert_true(opened.search.open)
  assert_false(step(opened, key("Escape")).search.open)
}

///|
test "MoveSelection wraps around the results" {
  let m = searching()
  assert_eq(flat_results(m).length(), 3)
  assert_eq(m.search.selected, 0)
  assert_eq(step(m, MoveSelection(-1)).search.selected, 2)
  assert_eq(
    step(step(m, MoveSelection(-1)), MoveSelection(1)).search.selected,
    0,
  )
  assert_eq(step(m, MoveSelection(1)).search.selected, 1)
}

///|
test "OpenSelected closes search" {
  let m = searching()
  assert_true(m.search.open)
  assert_false(step(m, OpenSelected).search.open)
}

///|
test "failed loads set the failure states" {
  let m = Model::init(site_data(Doc("smithy-syntax"), None))
  assert_eq(m.page, Loading)
  assert_eq(
    step(m, ContentLoaded(Doc("smithy-syntax"), Err(Failure("x")))).page,
    PageFailed,
  )
  let s = step(m, OpenSearch)
  assert_eq(step(s, IndexLoaded(Err(Failure("x")))).search.index, IndexFailed)
}

///|
test "a same-route fragment change keeps the page ready" {
  let m = Model::init(
    site_data(Doc("smithy-syntax"), Some("# Configuration\n\n## A\n")),
  )
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/docs/smithy-syntax/#a")),
  )
  assert_true(m2.page is Ready(_))
  assert_eq(m2.page, m.page)
  assert_eq(m2.route, m.route)
}

///|
test "Escape closes the phone menu when search is closed" {
  let m = { ..Model::init(site_data(Landing, None)), menu_open: true, }
  assert_false(step(m, key("Escape")).menu_open)
  // Other keys leave the menu alone.
  assert_true(step(m, key("x")).menu_open)
}

///|
test "opening search closes the phone menu" {
  let m = { ..Model::init(site_data(Landing, None)), menu_open: true, }
  let s = step(m, OpenSearch)
  assert_true(s.search.open)
  assert_false(s.menu_open)
  assert_false(step(m, key("/")).menu_open)
}

///|
test "init shows an example README, and nothing for the examples index" {
  let m = Model::init(
    site_data(Example("openrpc"), Some("# Export a service as OpenRPC\n")),
  )
  match m.page {
    Ready(doc) => assert_eq(doc.title, "Export a service as OpenRPC")
    _ => fail("expected a ready page")
  }
  assert_eq(Model::init(site_data(Examples, None)).page, NoContent)
  assert_eq(Model::init(site_data(Example("nope"), None)).page, NoContent)
}

///|
test "navigating to an example loads its README" {
  let m = Model::init(site_data(Landing, None))
  let m2 = step(
    m,
    UrlChanged(@url.parse("http://localhost/smithy/examples/openrpc/")),
  )
  assert_eq(m2.route, Example("openrpc"))
  assert_eq(m2.page, Loading)
  let m3 = step(
    m2,
    ContentLoaded(Example("openrpc"), Ok("# Export a service as OpenRPC\n")),
  )
  assert_true(m3.page is Ready(_))
  let index = step(
    m3,
    UrlChanged(@url.parse("http://localhost/smithy/examples/")),
  )
  assert_eq(index.route, Examples)
  assert_eq(index.page, NoContent)
  let missing = step(
    m3,
    UrlChanged(@url.parse("http://localhost/smithy/examples/nope")),
  )
  assert_eq(missing.page, NoContent)
}

///|
test "source_of: documentation pages and examples have one, other routes none" {
  let m = Model::init(site_data(Landing, None))
  assert_eq(
    source_of(m.manifest, m.examples, Example("openrpc")),
    Some("examples/openrpc/README.md"),
  )
  assert_eq(
    source_of(m.manifest, m.examples, Doc("cli")),
    Some("apps/smithy/README.md"),
  )
  assert_eq(source_of(m.manifest, m.examples, Example("nope")), None)
  assert_eq(source_of(m.manifest, m.examples, Examples), None)
  assert_eq(source_of(m.manifest, m.examples, Landing), None)
}

///|
fn doc_model(route : @route.Route) -> Model {
  Model::init(site_data(route, None))
}

///|
fn repr(cmd : @rabbita.Cmd) -> String {
  @debug.to_string(cmd)
}

///|
test "probe: only a 404 says the page is gone" {
  assert_eq(classify_probe(None), Found)
  assert_eq(
    classify_probe(Some(@http.RequestError("HTTP 404 Not Found"))),
    Gone,
  )
  assert_eq(classify_probe(Some(@http.RequestError("HTTP 404"))), Gone)
  assert_eq(classify_probe(Some(@http.RequestError("HTTP 500"))), Failed)
  assert_eq(classify_probe(Some(@http.RequestError("Failed to fetch"))), Failed)
}

///|
test "counterpart: a 404 for the current route sets Missing" {
  let m = doc_model(Doc("cli"))
  let m = step(m, CounterpartChecked(Doc("cli"), Gone))
  assert_eq(m.counterpart, Missing(Doc("cli")))
}

///|
test "counterpart: a 200 for the current route sets Present" {
  let m = step(doc_model(Doc("cli")), CounterpartChecked(Doc("cli"), Found))
  assert_eq(m.counterpart, Present(Doc("cli")))
}

///|
test "counterpart: an error keeps Unknown" {
  let m = step(doc_model(Doc("cli")), CounterpartChecked(Doc("cli"), Failed))
  assert_eq(m.counterpart, Unknown)
}

///|
test "counterpart: a result for another route changes nothing" {
  let m = doc_model(Doc("cli"))
  let after = step(m, CounterpartChecked(Doc("smithy-syntax"), Gone))
  assert_eq(after, m)
}

///|
test "counterpart: a route change drops the old result and a late one is ignored" {
  let m = step(doc_model(Doc("cli")), CounterpartChecked(Doc("cli"), Gone))
  let url = @url.parse("http://localhost/smithy/docs/smithy-syntax/")
  let m = step(m, UrlChanged(url))
  assert_eq(m.route, Doc("smithy-syntax"))
  assert_eq(m.counterpart, Unknown)
  let late = step(m, CounterpartChecked(Doc("cli"), Gone))
  assert_eq(late.counterpart, Unknown)
}

///|
test "counterpart: the request is issued for a route of a site with a release" {
  let m = doc_model(Doc("cli"))
  assert_true(repr(check_counterpart(m, noop_emit())) != repr(@rabbita.none))
}

///|
test "counterpart: no request without a release or for a missing page" {
  let m = doc_model(Doc("cli"))
  let none = repr(@rabbita.none)
  let no_release = { ..m, config: { ..m.config, has_release: false, }, }
  assert_eq(repr(check_counterpart(no_release, noop_emit())), none)
  let missing = { ..m, route: NotFound("/x/"), }
  assert_eq(repr(check_counterpart(missing, noop_emit())), none)
}

///|
test "a link into or out of the playground is a full page load" {
  let landing = Model::init(site_data(Landing, None))
  let playground = Model::init(site_data(Playground, None))
  assert_true(link_action(landing, "/smithy/playground/") is Load)
  assert_true(link_action(landing, "/smithy/docs/cli/") is Push)
  assert_true(link_action(playground, "/smithy/docs/cli/") is Load)
  assert_true(link_action(playground, "/smithy/") is Load)
  assert_true(link_action(landing, "/smithy/next/docs/cli/") is Load)
  // The request keeps the model: the page loads the URL.
  let req = UrlRequested(
    Internal(@url.parse("http://localhost/smithy/playground/")),
  )
  assert_eq(step(landing, req), landing)
}

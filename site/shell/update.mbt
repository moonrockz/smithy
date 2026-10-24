///|
pub fn entry_href(config : @data.SiteConfig, entry : @search.Entry) -> String {
  let path = @route.href(config.base, entry.route)
  if entry.anchor == "" {
    path
  } else {
    path + "#" + entry.anchor
  }
}

///|
/// Search results grouped by page, in display order.
pub fn current_results(m : Model) -> Array[(String, Array[@search.Match])] {
  match m.search.index {
    IndexReady(index) =>
      @search.group_by_page(@search.search(index, m.search.query))
    _ => []
  }
}

///|
fn flat_results(m : Model) -> Array[@search.Match] {
  let out : Array[@search.Match] = []
  for group in current_results(m) {
    for x in group.1 {
      out.push(x)
    }
  }
  out
}

///|
fn url_href(url : @url.Url) -> String {
  let query = match url.query {
    Some(q) => "?" + q
    None => ""
  }
  let fragment = match url.fragment {
    Some(f) => "#" + f
    None => ""
  }
  "/" + url.path + query + fragment
}

///|
/// The route text of `path` when it belongs to this site. The other
/// channel's site can live below this one (`/smithy/next/` below
/// `/smithy/`); its paths are not ours.
fn site_path(config : @data.SiteConfig, path : String) -> String? {
  let other = match config.channel {
    Release => config.next_base
    Next => config.release_base
  }
  if other != config.base &&
    other.has_prefix(config.base) &&
    @route.strip_base(other, path) is Some(_) {
    return None
  }
  @route.strip_base(config.base, path)
}

///|
/// How the page follows a link to a path of the site.
priv enum LinkAction {
  /// Show the route in this page.
  Push
  /// Load the URL as a new page.
  Load
}

///|
/// The playground page and a lesson load their own script, so a link into or
/// out of them loads the new page. The site data of a tour page holds only
/// that page, so a link into the tour contents loads it too. A link to a
/// heading of the same tour page only scrolls. A link into the other channel
/// loads it too.
fn link_action(m : Model, path : String) -> LinkAction {
  match site_path(m.config, path) {
    None => Load
    Some(rest) => {
      // A search result gives its heading as a fragment.
      let page = match rest.find("#") {
        Some(i) => rest[:i].to_owned()
        None => rest
      }
      let target = @route.Route::parse(page)
      if target == m.route && target is (Tour | Lesson(_)) {
        Push
      } else if loads_own_page(m.route) || loads_own_page(target) {
        Load
      } else {
        Push
      }
    }
  }
}

///|
/// The routes whose page the site cannot show without a page load.
fn loads_own_page(route : @route.Route) -> Bool {
  route is (Playground | Tour | Lesson(_))
}

///|
fn fetch_page(
  config : @data.SiteConfig,
  route : @route.Route,
  source : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @http.get(config.base + "content/" + source).expect_text(
    emit.map(r => ContentLoaded(route, r)),
  )
}

///|
/// The route to link in the other channel: the same page, or its docs
/// index or home when a check found that page missing there.
fn other_channel_route(m : Model) -> @route.Route {
  let route = match m.route {
    NotFound(_) => @route.Landing
    r => r
  }
  match m.counterpart {
    Missing(r) if r == m.route =>
      match route {
        DocsIndex | Doc(_) => @route.DocsIndex
        _ => @route.Landing
      }
    _ => route
  }
}

///|
fn other_channel_base(config : @data.SiteConfig) -> String {
  match config.channel {
    Release => config.next_base
    Next => config.release_base
  }
}

///|
/// Asks the other channel whether it has the page of `route`. Each channel
/// is a separate build, so only a request can tell. A page that is not a
/// route of this site (404) has a counterpart at its home, so it is not
/// checked.
pub fn check_counterpart(m : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  if !m.config.has_release || m.route is NotFound(_) {
    return @rabbita.none
  }
  let route = m.route
  @http.get(@route.href(other_channel_base(m.config), route)).expect_empty(
    emit.map(e => CounterpartChecked(route, classify_probe(e))),
  )
}

///|
/// Only a 404 says the page is missing. Another status or a network error
/// says nothing, so the page-for-page link stays.
pub fn classify_probe(error : Error?) -> Probe {
  match error {
    None => Found
    Some(e) => if e.to_string().contains("HTTP 404") { Gone } else { Failed }
  }
}

///|
fn open_search(m : Model, emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  let focus_cmd = run_effect(fn() { focus("ms-search-input") })
  match m.search.index {
    NotLoaded | IndexFailed => {
      let search = { ..m.search, open: true, selected: 0, index: LoadingIndex, }
      let m = { ..m, menu_open: false, }
      let load = @http.get(m.config.base + "search-index.json").expect_text(
        emit.map(r => IndexLoaded(r)),
      )
      ({ ..m, search, }, @rabbita.batch([load, focus_cmd]))
    }
    _ =>
      (
        {
          ..m,
          search: { ..m.search, open: true, selected: 0, },
          menu_open: false,
        },
        focus_cmd,
      )
  }
}

///|
fn on_url_changed(
  m : Model,
  url : @url.Url,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  guard site_path(m.config, url.path) is Some(rest) else {
    return (m, @rabbita.none)
  }
  let route = m.manifest.resolve(@route.Route::parse(rest))
  let anchor = match url.fragment {
    Some(id) if id != "" => Some(id)
    _ => None
  }
  let closed = { ..m, search: { ..m.search, open: false, }, menu_open: false, }
  if route == m.route {
    return (closed, scroll_cmd(anchor))
  }
  let next = { ..closed, route, counterpart: Unknown, }
  let check = check_counterpart(next, emit)
  match source_of(m.manifest, m.examples, m.tour, route) {
    Some(source) =>
      // The anchor is not in the DOM until the content is Ready.
      (
        { ..next, page: Loading, pending_anchor: anchor, },
        @rabbita.batch([fetch_page(m.config, route, source, emit), check]),
      )
    None =>
      (
        { ..next, page: NoContent, pending_anchor: None, },
        @rabbita.batch([@nav.scroll_to_top(), check]),
      )
  }
}

///|
fn scroll_cmd(anchor : String?) -> @rabbita.Cmd {
  match anchor {
    Some(id) => @nav.scroll_to(id)
    None => @nav.scroll_to_top()
  }
}

///|
pub fn update(
  m : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    UrlChanged(url) => on_url_changed(m, url, emit)
    UrlRequested(Internal(url)) =>
      match link_action(m, url.path) {
        Push => (m, @nav.push_url(url_href(url)))
        Load => (m, @nav.load(url_href(url)))
      }
    UrlRequested(External(href)) => (m, @nav.load(href))
    ContentLoaded(route, result) => {
      guard route == m.route else { return (m, @rabbita.none) }
      let page = match result {
        Ok(md) =>
          Ready(parse_page(m.config, m.manifest, m.examples, m.tour, route, md))
        Err(_) => PageFailed
      }
      ({ ..m, page, pending_anchor: None, }, scroll_cmd(m.pending_anchor))
    }
    ToggleTheme => {
      let theme = match m.theme {
        Auto => Dark
        Dark => Light
        Light => Auto
      }
      ({ ..m, theme, }, run_effect(fn() { store_theme(theme) }))
    }
    OpenSearch => open_search(m, emit)
    CloseSearch =>
      (
        { ..m, search: { ..m.search, open: false, }, },
        run_effect(fn() { focus("ms-search-btn") }),
      )
    SearchInput(query) =>
      ({ ..m, search: { ..m.search, query, selected: 0, }, }, @rabbita.none)
    IndexLoaded(Ok(text)) => {
      let index = match parse_index(text) {
        Some(entries) => IndexReady(@search.Index::new(entries))
        None => IndexFailed
      }
      ({ ..m, search: { ..m.search, index, }, }, @rabbita.none)
    }
    IndexLoaded(Err(_)) =>
      ({ ..m, search: { ..m.search, index: IndexFailed, }, }, @rabbita.none)
    MoveSelection(delta) => {
      let count = flat_results(m).length()
      let selected = if count == 0 {
        0
      } else {
        (m.search.selected + delta + count) % count
      }
      ({ ..m, search: { ..m.search, selected, }, }, run_effect(scroll_selected))
    }
    OpenSelected =>
      match flat_results(m).get(m.search.selected) {
        Some(hit) => {
          let href = entry_href(m.config, hit.entry)
          let closed = { ..m, search: { ..m.search, open: false, }, }
          match link_action(m, href) {
            Push => (closed, @nav.push_url(href))
            Load => (closed, @nav.load(href))
          }
        }
        None => (m, @rabbita.none)
      }
    KeyDown(key) => on_key(m, key, emit)
    SelectTab(tab) => ({ ..m, install_tab: tab, }, @rabbita.none)
    ToggleMenu => ({ ..m, menu_open: !m.menu_open, }, @rabbita.none)
    CounterpartChecked(route, probe) => {
      guard route == m.route else { return (m, @rabbita.none) }
      let counterpart = match probe {
        Found => Present(route)
        Gone => Missing(route)
        Failed => Unknown
      }
      ({ ..m, counterpart, }, @rabbita.none)
    }
  }
}

///|
fn parse_index(text : String) -> Array[@search.Entry]? {
  let json = @json.parse(text) catch { _ => return None }
  let entries : Array[@search.Entry] = @json.from_json(json) catch {
    _ => return None
  }
  Some(entries)
}

///|
fn on_key(
  m : Model,
  key : @common.Keyboard,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  let k = key.key()
  if !m.search.open {
    if ((k == "k" || k == "K") && (key.meta_key() || key.ctrl_key())) ||
      k == "/" {
      return open_search(m, emit)
    }
    if k == "Escape" && m.menu_open {
      return update(m, ToggleMenu, emit)
    }
    return (m, @rabbita.none)
  }
  match k {
    "Escape" => update(m, CloseSearch, emit)
    "ArrowDown" => update(m, MoveSelection(1), emit)
    "ArrowUp" => update(m, MoveSelection(-1), emit)
    "Enter" => update(m, OpenSelected, emit)
    _ => (m, @rabbita.none)
  }
}

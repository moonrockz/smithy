///|
fn class_if(base : String, extra : String, on : Bool) -> String {
  if on {
    base + " " + extra
  } else {
    base
  }
}

///|
fn theme_icon(theme : Theme) -> String {
  match theme {
    Auto => "◐"
    Dark => "☾"
    Light => "☀"
  }
}

///|
/// The route in the release site that matches `route` of the next site. A page of
/// main may not exist in the last release, so a docs page links to the docs index.
fn release_route(channel : @data.Channel, route : @route.Route) -> @route.Route {
  match (channel, route) {
    (Next, Doc(_)) => DocsIndex
    _ => route
  }
}

///|
fn version_picker(m : Model) -> Html {
  let c = m.config
  // A missing page has no counterpart in the other version: link to its home.
  let route = match m.route {
    NotFound(_) => @route.Landing
    r => r
  }
  @html.div(class="ms-version", [
    @html.a(
      class=class_if(
        "ms-version-link",
        "ms-version-current",
        c.channel == Release,
      ),
      href=@route.href(c.release_base, release_route(c.channel, route)),
      c.release_version,
    ),
    @html.a(
      class=class_if("ms-version-link", "ms-version-current", c.channel == Next),
      href=@route.href(c.next_base, route),
      "next",
    ),
  ])
}

///|
/// Only documentation pages have a sidebar for the phone menu to open.
fn has_sidebar(m : Model) -> Bool {
  match (m.route, m.manifest.find(m.route)) {
    (Landing, _) | (_, None) => false
    (_, Some(_)) => true
  }
}

///|
fn nav_bar(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let base = m.config.base
  @html.header(class="ms-nav", [
    if has_sidebar(m) {
      @html.button(
        class="ms-menu",
        title="Menu",
        on_click=emit(ToggleMenu),
        "☰",
      )
    } else {
      @html.nothing
    },
    @html.a(class="ms-brand", href=base, [
      @html.img(
        class="ms-avatar",
        src=base + "moonrockz.png",
        alt="moonrockz",
        width=28,
        height=28,
      ),
      @html.span(class="ms-word", [
        @html.text("moon"),
        @html.span(class="ms-accent", "spec"),
      ]),
    ]),
    @html.nav(class="ms-links", [
      @html.a(href=@route.href(base, DocsIndex), "Docs"),
      @html.a(href=@data.api_docs_url, "API ↗"),
      @html.a(href=@data.github_repo, "GitHub ↗"),
    ]),
    @html.button(
      id="ms-search-btn",
      class="ms-search-btn",
      on_click=emit(OpenSearch),
      [@html.span("Search docs"), @html.kbd("⌘K")],
    ),
    version_picker(m),
    @html.button(
      class="ms-theme",
      title="Theme: " + m.theme.to_string(),
      on_click=emit(ToggleTheme),
      theme_icon(m.theme),
    ),
  ])
}

///|
fn footer_view(m : Model) -> Html {
  let base = m.config.base
  @html.footer(class="ms-footer", [
    @html.img(src=base + "moonrockz.png", alt="moonrockz", width=56, height=56),
    @html.span(
      "A moonrockz project · Apache-2.0 · smithy " + @smithy.version(),
    ),
    @html.a(href=@data.api_docs_url, "mooncakes.io ↗"),
    @html.a(href=@data.github_repo, "GitHub ↗"),
  ])
}

///|
/// The one `404.html` is served for every missing path, whichever version
/// it is under, so this view names no version.
fn not_found_view(m : Model) -> Html {
  let c = m.config
  let docs = @route.DocsIndex
  @html.section(class="ms-notfound", [
    @html.h1("Page not found"),
    @html.p("This page does not exist."),
    @html.p([
      @html.a(href=c.base, "Home"),
      @html.text(" · "),
      @html.a(
        href=@route.href(c.release_base, docs),
        "Docs (\{c.release_version})",
      ),
      @html.text(" · "),
      @html.a(href=@route.href(c.next_base, docs), "Docs (next)"),
    ]),
  ])
}

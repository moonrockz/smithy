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
fn version_picker(m : Model) -> Html {
  let c = m.config
  // A missing page has no counterpart in the other version: link to its home.
  let route = match m.route {
    NotFound(_) => @route.Landing
    r => r
  }
  if !c.has_release {
    // No release has docs yet: the only version is main, and it links nowhere.
    return @html.div(class="ms-version", [
      @html.span(class="ms-version-link ms-version-current", "next"),
    ])
  }
  @html.div(class="ms-version", [
    @html.a(
      class=class_if(
        "ms-version-link",
        "ms-version-current",
        c.channel == Release,
      ),
      href=@route.href(c.release_base, route),
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
      @html.span(class="ms-logo", ([] : Array[Html])),
      @html.span(class="ms-word", [
        @html.text("smithy"),
        @html.span(class="ms-accent", ".mbt"),
      ]),
    ]),
    @html.nav(class="ms-links", [
      @html.a(href=@route.href(base, DocsIndex), "Docs"),
      @html.a(href=@route.href(base, Examples), "Examples"),
      @html.a(class="ms-extlink", href=@data.api_docs_url, [
        @html.text("API"),
        icon_external(),
      ]),
    ]),
    @html.a(
      class="ms-iconbtn",
      href=@data.github_repo,
      title="GitHub",
      attrs=@html.Attrs::build().aria_label("GitHub"),
      [icon_github()],
    ),
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
/// An inline icon, hidden from assistive technology: the link names it.
fn icon(width : Int32, d : String, class~ : String = "ms-icon") -> Html {
  @html.span(class~, attrs=@html.Attrs::build().aria_hidden("true"), [
    @svg.svg(width~, height=width, view_box="0 0 16 16", [
      @svg.path(d~, fill="currentColor"),
    ]),
  ])
}

///|
fn icon_external() -> Html {
  icon(
    12,
    "M9 2h5v5h-1.5V4.56L7.53 9.53 6.47 8.47l4.97-4.97H9V2ZM3.5 4A1.5 1.5 0 0 0 2 5.5v7A1.5 1.5 0 0 0 3.5 14h7a1.5 1.5 0 0 0 1.5-1.5V9h-1.5v3.5h-7v-7H7V4H3.5Z",
    class="ms-ext",
  )
}

///|
fn icon_github() -> Html {
  icon(
    18, "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z",
  )
}

///|
fn footer_view() -> Html {
  @html.footer(class="ms-footer", [
    @html.span("smithy.mbt · moonrockz · smithy " + @smithy.version()),
    @html.span("Apache-2.0"),
    @html.a(href=@data.github_repo, "GitHub"),
    @html.a(href=@data.api_docs_url, "mooncakes.io"),
    @html.a(href=changelog_url, "Changelog"),
    @html.span(
      class="ms-footer-note",
      "Smithy is an open source project by AWS. This is an independent MoonBit implementation.",
    ),
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
    @html.p(
      [
        @html.a(href=c.base, "Home"),
        @html.text(" · "),
        ..if c.has_release {
          [
            @html.a(
              href=@route.href(c.release_base, docs),
              "Docs (\{c.release_version})",
            ),
            @html.text(" · "),
          ]
        } else {
          []
        },
        @html.a(href=@route.href(c.next_base, docs), "Docs (next)"),
      ],
    ),
  ])
}

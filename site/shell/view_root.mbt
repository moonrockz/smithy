///|
using @html {type Html, html, head, body, meta, title, link, script, main_}

///|
fn theme_attrs(theme : Theme) -> @html.Attrs {
  match theme {
    Auto => @html.Attrs::build()
    Light => @html.Attrs::build().data_set("theme", "light")
    Dark => @html.Attrs::build().data_set("theme", "dark")
  }
}

///|
/// Runs before the first paint: applies the stored theme so a reader who
/// chose one never sees the other. Static text, so the pre-rendered and the
/// hydrated head are identical.
let theme_script : String =
  #|try{var t=localStorage.getItem('smithy-theme');if(t==='light'||t==='dark'){document.documentElement.dataset.theme=t}}catch(e){}

///|
fn page_title(m : Model) -> String {
  match (m.route, m.manifest.find(m.route)) {
    (Landing, _) => "Smithy for MoonBit"
    (Playground, _) => "Playground — smithy"
    (Examples, _) => "Examples — smithy"
    (Example(dir), _) =>
      match @content.Example::find(m.examples, dir) {
        Some(e) => e.title + " — smithy"
        None => "Page not found — smithy"
      }
    (_, Some(page)) => page.title + " — smithy"
    (_, None) => "Page not found — smithy"
  }
}

///|
/// The whole document. `site_json` is the encoded first-render data; it is
/// constant, so the pre-rendered `<meta>` and the hydrated one match.
pub fn view(m : Model, emit : @rabbita.Emit[Msg], site_json : String) -> Html {
  let base = m.config.base
  html(lang="en", attrs=theme_attrs(m.theme), [
    head([
      script(theme_script),
      meta(charset="utf-8"),
      meta(name="viewport", content="width=device-width, initial-scale=1"),
      title(page_title(m)),
      meta(
        name="description",
        content="Smithy for MoonBit: load, validate, build and diff Smithy models.",
      ),
      link(rel="icon", href=base + "favicon.ico", sizes="16x16 32x32 48x48"),
      link(
        rel="icon",
        type_="image/png",
        href=base + "favicon-32.png",
        sizes="32x32",
      ),
      link(rel="apple-touch-icon", href=base + "apple-touch-icon.png"),
      link(rel="manifest", href=base + "manifest.json"),
      link(rel="preconnect", href="https://fonts.googleapis.com"),
      link(
        rel="stylesheet",
        href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;600;800&display=swap",
      ),
      link(rel="stylesheet", href=base + "styles.css"),
      meta(name="smithy-data", content=site_json),
      script(src=base + "index.js", type_="module", ([] : Array[Html])),
      // Only the playground page loads the playground. It runs after
      // index.js, which hydrates the page first.
      if m.route == Playground {
        script(
          src=m.config.versioned(base + "playground/ui.js"),
          type_="module",
          ([] : Array[Html]),
        )
      } else {
        @html.nothing
      },
    ]),
    body([
      nav_bar(m, emit),
      main_(class="ms-main", [content_view(m, emit)]),
      footer_view(),
      search_view(m, emit),
    ]),
  ])
}

///|
fn content_view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  match (m.route, m.manifest.find(m.route)) {
    (Landing, _) => landing_view(m, emit)
    (Playground, _) => playground_view(m)
    (Examples, _) => examples_index_view(m)
    (Example(dir), _) =>
      match @content.Example::find(m.examples, dir) {
        Some(e) => example_view(m, e)
        None => not_found_view(m)
      }
    (_, Some(page)) => docs_view(m, page, emit)
    (_, None) => not_found_view(m)
  }
}

///|
/// The site component: one state, one view of the whole document.
/// `initial_theme` is the theme the head script already applied; the
/// pre-render uses `Auto`.
pub fn component(
  data : @data.SiteData,
  site_json : String,
  initial_theme~ : Theme = Auto,
  probe_other~ : Bool = false,
) -> @rabbita.Val[Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let m = { ..Model::init(data), theme: initial_theme, }
      // Only the hydrated page asks: the pre-render has no network.
      (m, if probe_other { check_counterpart(m, emit) } else { @rabbita.none })
    },
    update~,
    subscriptions=(_m, emit) => {
      @sub.batch([
        @sub.on_url_changed(emit.map(u => UrlChanged(u))),
        @sub.on_url_request(emit.map(r => UrlRequested(r))),
        @sub.on_key_down(emit.map(k => KeyDown(k))),
      ])
    },
  )
  model.map(m => view(m, emit, site_json))
}

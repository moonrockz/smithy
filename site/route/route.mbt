///|
/// A page of the site, without the base path.
pub(all) enum Route {
  Landing
  /// `/docs/`. The manifest says which page it opens.
  DocsIndex
  Doc(String)
  /// `/examples/`: the cards of the examples that have a README.
  Examples
  /// `/examples/<dir>`: the README of `examples/<dir>` and its files.
  Example(String)
  /// `/playground/`: the workbench that runs Smithy in the browser.
  Playground
  /// `/tour/`: the contents of the language tour.
  Tour
  /// `/tour/<slug>`: one lesson of the tour.
  Lesson(String)
  NotFound(String)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Route with Eq::{equal, not_equal}

///|
pub extend Route with @debug.Debug::{to_repr}

///|
pub extend Route with ToJson::{to_json}

///|
pub extend Route with FromJson::{from_json}

///|
/// Non-empty path segments; a trailing `index.html` is dropped.
fn segments(path : String) -> Array[String] {
  let out : Array[String] = []
  for part in path.split("/") {
    let s = part.to_owned()
    if s != "" {
      out.push(s)
    }
  }
  if out.last() == Some("index.html") {
    ignore(out.pop())
  }
  out
}

///|
/// Route of a path after the base path, for example `docs/configuration`.
pub fn Route::parse(path : String) -> Route {
  let segs = segments(path)
  match segs {
    [] => Landing
    ["docs"] => DocsIndex
    ["docs", slug] => Doc(slug)
    ["examples"] => Examples
    ["examples", dir] => Example(dir)
    ["playground"] => Playground
    ["tour"] => Tour
    ["tour", slug] => Lesson(slug)
    _ => NotFound(segs.join("/"))
  }
}

///|
/// The path of the route after the base path, without leading or trailing `/`.
pub fn Route::to_path(self : Route) -> String {
  match self {
    Landing => ""
    DocsIndex => "docs"
    Doc(slug) => "docs/" + slug
    Examples => "examples"
    Example(dir) => "examples/" + dir
    Playground => "playground"
    Tour => "tour"
    Lesson(slug) => "tour/" + slug
    NotFound(path) => path
  }
}

///|
/// The URL path of `route` under `base` (which ends with `/`). Pages other than
/// the landing page end with `/`: GitHub Pages redirects the other form.
pub fn href(base : String, route : Route) -> String {
  match route {
    Landing => base
    _ => base + route.to_path() + "/"
  }
}

///|
/// The part of an URL path after `base`, or `None` when the path is not under
/// `base`. `path` may lack its leading `/` (rabbita's `Url.path` does).
pub fn strip_base(base : String, path : String) -> String? {
  let p = if path.has_prefix("/") { path } else { "/" + path }
  if p.has_prefix(base) {
    Some(p[base.length():].to_owned())
  } else if p + "/" == base {
    Some("")
  } else {
    None
  }
}

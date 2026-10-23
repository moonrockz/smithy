///|
pub(all) enum Theme {
  Auto
  Light
  Dark
} derive(Eq, Debug)

///|
pub extend Theme with Eq::{equal, not_equal}

///|
pub extend Theme with @debug.Debug::{to_repr}

///|
pub fn Theme::parse(s : String) -> Theme {
  match s {
    "light" => Light
    "dark" => Dark
    _ => Auto
  }
}

///|
pub fn Theme::to_string(self : Theme) -> String {
  match self {
    Auto => "auto"
    Light => "light"
    Dark => "dark"
  }
}

///|
pub(all) enum PageState {
  /// The landing page and pages that do not exist.
  NoContent
  Loading
  Ready(@markdown.Document)
  PageFailed
} derive(Eq, Debug)

///|
pub extend PageState with Eq::{equal, not_equal}

///|
pub extend PageState with @debug.Debug::{to_repr}

///|
pub(all) enum IndexState {
  NotLoaded
  LoadingIndex
  IndexReady(@search.Index)
  IndexFailed
} derive(Eq, Debug)

///|
pub extend IndexState with Eq::{equal, not_equal}

///|
pub extend IndexState with @debug.Debug::{to_repr}

///|
pub(all) enum InstallTab {
  Mise
  Moonx
  Library
  Download
} derive(Eq, Debug)

///|
pub extend InstallTab with Eq::{equal, not_equal}

///|
pub extend InstallTab with @debug.Debug::{to_repr}

///|
pub(all) struct SearchState {
  open : Bool
  query : String
  selected : Int32
  index : IndexState
} derive(Eq, Debug)

///|
pub extend SearchState with Eq::{equal, not_equal}

///|
pub extend SearchState with @debug.Debug::{to_repr}

///|
/// What a check found at the same route in the other channel. The route
/// keys the result: a result for any other route is stale.
pub(all) enum Counterpart {
  Unknown
  Present(@route.Route)
  Missing(@route.Route)
} derive(Eq, Debug)

///|
pub extend Counterpart with Eq::{equal, not_equal}

///|
pub extend Counterpart with @debug.Debug::{to_repr}

///|
/// The outcome of one request for the other channel's page.
pub(all) enum Probe {
  Found
  Gone
  Failed
} derive(Eq, Debug)

///|
pub extend Probe with Eq::{equal, not_equal}

///|
pub extend Probe with @debug.Debug::{to_repr}

///|
pub(all) struct Model {
  config : @data.SiteConfig
  manifest : @content.Manifest
  examples : Array[@content.Example]
  route : @route.Route
  page : PageState
  theme : Theme
  search : SearchState
  install_tab : InstallTab
  menu_open : Bool
  counterpart : Counterpart
  // Fragment to scroll to once the page being loaded is ready.
  pending_anchor : String?
  /// The data of the playground page; `None` on every other page.
  playground : @workbench.PlaygroundData?
} derive(Eq, Debug)

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
pub(all) enum Msg {
  UrlChanged(@url.Url)
  UrlRequested(@url.UrlRequest)
  ContentLoaded(@route.Route, Result[String, Error])
  ToggleTheme
  OpenSearch
  CloseSearch
  SearchInput(String)
  IndexLoaded(Result[String, Error])
  MoveSelection(Int32)
  OpenSelected
  KeyDown(@common.Keyboard)
  SelectTab(InstallTab)
  ToggleMenu
  CounterpartChecked(@route.Route, Probe)
}

///|
let closed_search : SearchState = {
  open: false,
  query: "",
  selected: 0,
  index: NotLoaded,
}

///|
/// The repository path of the Markdown file that a route shows, or `None`
/// for a route with no such file (the landing page, the examples index, 404).
fn source_of(
  manifest : @content.Manifest,
  examples : Array[@content.Example],
  route : @route.Route,
) -> String? {
  match route {
    Example(dir) => @content.Example::find(examples, dir).map(e => e.source())
    _ => manifest.find(route).map(p => p.source)
  }
}

///|
fn parse_page(
  config : @data.SiteConfig,
  manifest : @content.Manifest,
  examples : Array[@content.Example],
  route : @route.Route,
  markdown : String,
) -> @markdown.Document {
  let source = source_of(manifest, examples, route).unwrap_or("")
  @markdown.parse(
    markdown,
    @data.link_context(config, manifest, examples, source),
  )
}

///|
pub fn Model::init(data : @data.SiteData) -> Model {
  let manifest = data.manifest()
  let page = match
    (source_of(manifest, data.examples, data.route), data.markdown) {
    (None, _) => NoContent
    (Some(_), Some(md)) =>
      Ready(parse_page(data.config, manifest, data.examples, data.route, md))
    (Some(_), None) => Loading
  }
  {
    config: data.config,
    manifest,
    examples: data.examples,
    route: data.route,
    page,
    theme: Auto,
    search: closed_search,
    install_tab: Mise,
    menu_open: false,
    counterpart: Unknown,
    pending_anchor: None,
    playground: data.playground,
  }
}

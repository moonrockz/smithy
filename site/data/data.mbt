///|
pub let github_repo : String = "https://github.com/moonrockz/smithy"

///|
/// The API reference on mooncakes.io (verified in Task 8, Step 3).
pub let api_docs_url : String = "https://mooncakes.io/docs/moonrockz/smithy"

///|
pub(all) enum Channel {
  Release
  Next
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Channel with Eq::{equal, not_equal}

///|
pub extend Channel with @debug.Debug::{to_repr}

///|
pub extend Channel with ToJson::{to_json}

///|
pub extend Channel with FromJson::{from_json}

///|
/// The name of the channel on the command line and in storage keys.
pub fn Channel::name(self : Channel) -> String {
  match self {
    Release => "release"
    Next => "next"
  }
}

///|
/// The channel of `name`, or `None` for another name.
pub fn Channel::parse(name : String) -> Channel? {
  [Release, Next].iter().find_first(c => c.name() == name)
}

///|
/// One built version of the site.
pub(all) struct SiteConfig {
  /// Base path of this version, for example "/smithy/next/".
  base : String
  /// "v0.5.0" for the release, "next" for main.
  version : String
  channel : Channel
  /// Tag or commit SHA used for GitHub links.
  git_ref : String
  release_base : String
  next_base : String
  /// Label of the release version, for the version picker.
  release_version : String
  /// False while no release has a site: the release entry is then left out.
  has_release : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend SiteConfig with Eq::{equal, not_equal}

///|
pub extend SiteConfig with @debug.Debug::{to_repr}

///|
pub extend SiteConfig with ToJson::{to_json}

///|
pub extend SiteConfig with FromJson::{from_json}

///|
/// Everything the component needs for its first render. The pre-render puts
/// it in `<meta name="smithy-data">`; the browser reads it back for hydration.
pub(all) struct SiteData {
  config : SiteConfig
  pages : Array[@content.Page]
  /// The examples that have a README.
  examples : Array[@content.Example]
  route : @route.Route
  /// Markdown of the current page; `None` for the landing page and 404.
  markdown : String?
  /// The samples and the Worker of the playground page; `None` on every other page.
  playground : @workbench.PlaygroundData?
  /// The contents or the lesson of a tour page; `None` on every other page.
  tour : @model.TourPage?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend SiteData with Eq::{equal, not_equal}

///|
pub extend SiteData with @debug.Debug::{to_repr}

///|
pub extend SiteData with ToJson::{to_json}

///|
pub extend SiteData with FromJson::{from_json}

///|
pub fn SiteData::encode(self : SiteData) -> String {
  Json(self).stringify()
}

///|
pub fn SiteData::decode(s : String) -> SiteData? {
  let json = @json.parse(s) catch { _ => return None }
  let data : SiteData = @json.from_json(json) catch { _ => return None }
  Some(data)
}

///|
pub fn SiteData::manifest(self : SiteData) -> @content.Manifest {
  { pages: self.pages, }
}

///|
/// The repository path that a tour lesson links to open the playground.
pub let playground_source : String = "site/playground/README.md"

///|
/// The link context for the page whose repository path is `source`.
pub fn link_context(
  config : SiteConfig,
  manifest : @content.Manifest,
  examples : Array[@content.Example],
  source : String,
) -> @markdown.LinkContext {
  {
    source,
    resolve: path => {
      if path == playground_source {
        return Some(Playground)
      }
      match manifest.find_source(path) {
        Some(page) => Some(page.route)
        None =>
          match @model.slug_of_source(path) {
            Some(slug) => Some(Lesson(slug))
            None =>
              @content.Example::find_source(examples, path).map(e => {
                Example(e.dir)
              })
          }
      }
    },
    repo_url: github_repo,
    git_ref: config.git_ref,
  }
}

///|
/// `path` with the git ref of this build as its query. Pages caches each file
/// for some minutes, so a page of a new build could otherwise run a script of
/// the build before it.
pub fn SiteConfig::versioned(self : SiteConfig, path : String) -> String {
  path + "?v=" + query_value(self.git_ref)
}

///|
/// `text` with each character outside the unreserved set of RFC 3986 written
/// as `%XX` of its UTF-8 bytes.
fn query_value(text : String) -> String {
  let out = StringBuilder()
  for byte in @utf8.encode(text) {
    let c = byte.to_int()
    if (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
      (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '-'.to_int() ||
      c == '.'.to_int() ||
      c == '_'.to_int() ||
      c == '~'.to_int() {
      out.write_char(c.unsafe_to_char())
    } else {
      let hex = "0123456789ABCDEF"
      out.write_char('%')
      out.write_char(hex[c / 16].unsafe_to_char())
      out.write_char(hex[c % 16].unsafe_to_char())
    }
  }
  out.to_string()
}

///|
pub(all) enum Group {
  Guides
  Cli
  Libraries
  Cookbook
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Group with Eq::{equal, not_equal}

///|
pub extend Group with @debug.Debug::{to_repr}

///|
pub extend Group with ToJson::{to_json}

///|
pub extend Group with FromJson::{from_json}

///|
/// A published page. `source` is the repository path of its Markdown file.
pub(all) struct Page {
  route : @route.Route
  title : String
  source : String
  group : Group
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Page with Eq::{equal, not_equal}

///|
pub extend Page with @debug.Debug::{to_repr}

///|
pub extend Page with ToJson::{to_json}

///|
pub extend Page with FromJson::{from_json}

///|
/// A Markdown file found in the content tree, with the text of its first `#` heading.
pub(all) struct SourceFile {
  path : String
  title : String
} derive(Eq, Debug)

///|
pub extend SourceFile with Eq::{equal, not_equal}

///|
pub extend SourceFile with @debug.Debug::{to_repr}

///|
/// The published pages of one version, in sidebar order.
pub(all) struct Manifest {
  pages : Array[Page]
} derive(Eq, Debug)

///|
pub extend Manifest with Eq::{equal, not_equal}

///|
pub extend Manifest with @debug.Debug::{to_repr}

///|
/// A repository path without a leading `./`.
pub fn normalize_path(path : String) -> String {
  let mut p = path
  while p.has_prefix("./") {
    p = p[2:].to_owned()
  }
  p
}

///|
fn is_slug(s : String) -> Bool {
  s != "" &&
  s
  .iter()
  .all(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')
}

///|
/// The sidebar label of a group.
pub fn Group::label(self : Group) -> String {
  match self {
    Guides => "Guides"
    Cli => "CLI"
    Libraries => "Libraries"
    Cookbook => "Cookbook"
  }
}

///|
/// The pages other than guides: route slug, repository path and group, in sidebar order.
let fixed_pages : Array[(String, String, Group)] = [
  ("cli", "apps/smithy/README.md", Cli),
  ("smithy-syntax", "pkgs/smithy-syntax/README.mbt.md", Libraries),
  ("smithy", "pkgs/smithy/README.mbt.md", Libraries),
  ("smithy-validation", "pkgs/smithy-validation/README.mbt.md", Libraries),
  (
    "smithy-validation-rpc",
    "pkgs/smithy-validation/rpc/README.mbt.md",
    Libraries,
  ),
  (
    "smithy-ion-validation",
    "pkgs/smithy-ion-validation/README.mbt.md",
    Libraries,
  ),
  ("smithy-build", "pkgs/smithy-build/README.mbt.md", Libraries),
  ("smithy-diff", "pkgs/smithy-diff/README.mbt.md", Libraries),
  ("smithy-jsonschema", "pkgs/smithy-jsonschema/README.mbt.md", Libraries),
  ("smithy-openapi", "pkgs/smithy-openapi/README.mbt.md", Libraries),
  ("smithy-openrpc", "pkgs/smithy-openrpc/README.mbt.md", Libraries),
  ("jmespath", "pkgs/jmespath/README.mbt.md", Libraries),
  ("artifact-resources", "pkgs/artifact-resources/README.mbt.md", Libraries),
  ("protocol-tests", "pkgs/smithy/protocoltests/README.mbt.md", Libraries),
  ("parsing", "docs/cookbook/parsing.mbt.md", Cookbook),
  ("traversal", "docs/cookbook/traversal.mbt.md", Cookbook),
  ("diagnostics", "docs/cookbook/diagnostics.mbt.md", Cookbook),
]

///|
/// The repository paths of the pages that are not guides.
pub fn fixed_sources() -> Array[String] {
  fixed_pages.map(p => p.1)
}

///|
let excluded_prefixes : Array[String] = [
  "docs/superpowers/", "docs/spikes/", ".dev/", "tests/tck/",
]

///|
let excluded_names : Array[String] = ["DESIGN.md", "AGENTS.md", "CONTEXT.md"]

///|
/// Whether a file is never published: working documents, design notes,
/// agent instructions and the vendored test corpus.
pub fn is_excluded(path : String) -> Bool {
  let p = normalize_path(path)
  let parts = p.split("/").map(s => s.to_owned()).collect()
  excluded_names.contains(parts.last().unwrap_or("")) ||
  excluded_prefixes.iter().any(x => p.has_prefix(x)) ||
  parts.contains(".dev") ||
  p.contains("/tests/tck/")
}

///|
/// The slug of `docs/guide/<slug>.md` or `<slug>.mbt.md`.
fn guide_slug(p : String) -> String? {
  let name = match p.strip_prefix("docs/guide/") {
    Some(rest) => rest.to_owned()
    None => return None
  }
  let stem = if name.has_suffix(".mbt.md") {
    name[:name.length() - 7].to_owned()
  } else if name.has_suffix(".md") {
    name[:name.length() - 3].to_owned()
  } else {
    return None
  }
  if is_slug(stem) {
    Some(stem)
  } else {
    None
  }
}

///|
/// The route and group of a published source file, or `None` when the file
/// is not published (for example anything under `docs/superpowers/`).
pub fn classify(path : String) -> (@route.Route, Group)? {
  let p = normalize_path(path)
  guard !is_excluded(p) else { return None }
  if guide_slug(p) is Some(slug) {
    return Some((Doc(slug), Guides))
  }
  for page in fixed_pages {
    if page.1 == p {
      return Some((Doc(page.0), page.2))
    }
  }
  None
}

///|
fn fixed_rank(route : @route.Route) -> Int32 {
  for i, page in fixed_pages {
    if @route.Route::Doc(page.0) == route {
      return i
    }
  }
  fixed_pages.length()
}

///|
/// The manifest of the published files among `files`.
pub fn Manifest::build(files : Array[SourceFile]) -> Manifest {
  let guides : Array[Page] = []
  let others : Array[Page] = []
  for f in files {
    match classify(f.path) {
      Some((route, group)) => {
        let page : Page = {
          route,
          title: f.title,
          source: normalize_path(f.path),
          group,
        }
        if group is Guides {
          guides.push(page)
        } else {
          others.push(page)
        }
      }
      None => ()
    }
  }
  guides.sort_by((a, b) => a.route.to_path().compare(b.route.to_path()))
  others.sort_by((a, b) => fixed_rank(a.route) - fixed_rank(b.route))
  { pages: [..guides, ..others], }
}

///|
/// The non-empty groups with their pages, in sidebar order.
pub fn Manifest::groups(self : Manifest) -> Array[(Group, Array[Page])] {
  let out : Array[(Group, Array[Page])] = []
  for group in [Guides, Cli, Libraries, Cookbook] {
    let pages = self.pages.filter(p => p.group == group)
    if !pages.is_empty() {
      out.push((group, pages))
    }
  }
  out
}

///|
/// The page that `/docs/` opens: the first guide, or the CLI while there is none.
pub fn Manifest::default_route(self : Manifest) -> @route.Route {
  match self.pages.iter().find_first(p => p.group is Guides) {
    Some(page) => page.route
    None => Doc("cli")
  }
}

///|
/// `DocsIndex` becomes the page it opens. Other routes stay.
pub fn Manifest::resolve(self : Manifest, route : @route.Route) -> @route.Route {
  match route {
    DocsIndex => self.default_route()
    _ => route
  }
}

///|
pub fn Manifest::find(self : Manifest, route : @route.Route) -> Page? {
  for page in self.pages {
    if page.route == route {
      return Some(page)
    }
  }
  None
}

///|
pub fn Manifest::find_source(self : Manifest, source : String) -> Page? {
  let wanted = normalize_path(source)
  for page in self.pages {
    if page.source == wanted {
      return Some(page)
    }
  }
  None
}

///|
/// The pages before and after `route` in sidebar order.
pub fn Manifest::neighbors(
  self : Manifest,
  route : @route.Route,
) -> (Page?, Page?) {
  for i, page in self.pages {
    if page.route == route {
      let prev = if i > 0 { Some(self.pages[i - 1]) } else { None }
      let next = if i + 1 < self.pages.length() {
        Some(self.pages[i + 1])
      } else {
        None
      }
      return (prev, next)
    }
  }
  (None, None)
}

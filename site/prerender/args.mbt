///|
pub(all) struct Args {
  content : String
  channel : @data.Channel
  site_root : String
  /// The base of this build when it is not the one the channel implies.
  base : String?
  release_version : String
  /// False when no release has a site, so the pages name no release.
  has_release : Bool
  git_ref : String
  out : String
} derive(Eq, Debug)

///|
fn with_slashes(path : String) -> String {
  let p = if path.has_prefix("/") { path } else { "/" + path }
  if p.has_suffix("/") {
    p
  } else {
    p + "/"
  }
}

///|
/// Parses the command line (`argv[0]` is the program name).
pub fn parse_args(argv : Array[String]) -> Result[Args, String] {
  let mut args : Args = {
    content: ".",
    channel: Next,
    site_root: "/smithy/",
    base: None,
    release_version: "v0.0.0",
    has_release: true,
    git_ref: "main",
    out: "dist",
  }
  let mut i = 1
  while i < argv.length() {
    if argv[i] == "--no-release" {
      args = { ..args, has_release: false, }
      i = i + 1
      continue
    }
    guard i + 1 < argv.length() else {
      return Err("missing value for \{argv[i]}")
    }
    let value = argv[i + 1]
    match argv[i] {
      "--content" => args = { ..args, content: value, }
      "--channel" =>
        match @data.Channel::parse(value) {
          Some(channel) => args = { ..args, channel, }
          None => return Err("--channel must be release or next, got \{value}")
        }
      "--site-root" => args = { ..args, site_root: with_slashes(value), }
      "--base" => args = { ..args, base: Some(with_slashes(value)), }
      "--release-version" => args = { ..args, release_version: value, }
      "--ref" => args = { ..args, git_ref: value, }
      "--out" => args = { ..args, out: value, }
      flag => return Err("unknown flag \{flag}")
    }
    i = i + 2
  }
  Ok(args)
}

///|
pub fn config_of(args : Args) -> @data.SiteConfig {
  let release_base = with_slashes(args.site_root)
  let next_base = release_base + "next/"
  match args.channel {
    Release =>
      {
        base: args.base.unwrap_or(release_base),
        version: args.release_version,
        channel: Release,
        git_ref: args.git_ref,
        release_base,
        next_base,
        release_version: args.release_version,
        has_release: args.has_release,
      }
    Next =>
      {
        base: args.base.unwrap_or(next_base),
        version: "next",
        channel: Next,
        git_ref: args.git_ref,
        release_base,
        next_base,
        release_version: args.release_version,
        has_release: args.has_release,
      }
  }
}

///|
/// The output file of a route, relative to the output directory.
pub fn page_path(route : @route.Route) -> String {
  match route.to_path() {
    "" => "index.html"
    path => path + "/index.html"
  }
}

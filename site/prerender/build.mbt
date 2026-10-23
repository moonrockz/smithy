///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[:i].to_owned()
    None => "."
  }
}

///|
fn ensure_dir(dir : String) -> Unit {
  if dir == "." || dir == "" || dir == "/" || @fs.path_exists(dir) {
    return
  }
  ensure_dir(dirname(dir))
  @fs.create_dir(dir) catch {
    _ => ()
  }
}

///|
fn write_file(path : String, content : String) -> Unit raise {
  ensure_dir(dirname(path))
  @fs.write_string_to_file(path, content)
}

///|
/// Markdown files under `dir`, as (repository path, text).
fn read_markdown_dir(
  content : String,
  dir : String,
) -> Array[(String, String)] raise {
  let full = content + "/" + dir
  if !@fs.path_exists(full) {
    return []
  }
  let names = @fs.read_dir(full).to_owned()
  names.sort()
  let out : Array[(String, String)] = []
  for name in names {
    if name.has_suffix(".md") {
      out.push((dir + "/" + name, @fs.read_file_to_string(full + "/" + name)))
    }
  }
  out
}

///|
/// The files among `paths` that do not exist under `content`.
fn missing_sources(content : String, paths : Array[String]) -> Array[String] {
  paths.filter(path => !@fs.path_exists(content + "/" + path))
}

///|
/// The fixed sources to read. Every channel builds its own checkout, so a missing
/// source is a broken build, not an older release.
fn plan_sources(
  content : String,
  missing : Array[String],
) -> Result[Array[String], String] {
  if missing.is_empty() {
    Ok(@content.fixed_sources())
  } else {
    Err(
      "I could not find these source files under \{content}: \{missing.join(", ")}",
    )
  }
}

///|
/// The files `paths` under `content`, as (repository path, text). Each file must exist.
fn read_markdown_files(
  content : String,
  paths : Array[String],
) -> Array[(String, String)] raise {
  let out : Array[(String, String)] = []
  for path in paths {
    out.push((path, @fs.read_file_to_string(content + "/" + path)))
  }
  out
}

///|
async fn render_page(data : @data.SiteData) -> String {
  let json = data.encode()
  let html = @rabbita.new(() => @shell.component(data, json)).render(
    url="http://localhost" + @route.href(data.config.base, data.route),
  )
  html
}

///|
/// A build without any docs page is a wrong `--content` path, not a site.
fn check_manifest(
  manifest : @content.Manifest,
  content : String,
) -> Result[Unit, String] {
  if manifest.pages.is_empty() {
    Err("no docs pages found under \{content}")
  } else {
    Ok(())
  }
}

///|
/// Builds one version of the site into `args.out`.
pub async fn build_site(args : Args) -> Unit {
  let config = config_of(args)
  let missing = missing_sources(args.content, @content.fixed_sources())
  let sources = match plan_sources(args.content, missing) {
    Ok(sources) => sources
    Err(message) => {
      println("prerender: " + message)
      @sys.exit(1)
      return
    }
  }
  let files = [
    ..read_markdown_dir(args.content, "docs/guide"),
    ..read_markdown_files(args.content, sources),
  ]
  let manifest = @content.Manifest::build(
    files.map(f => { path: f.0, title: @markdown.title_of(f.1), }),
  )
  match check_manifest(manifest, args.content) {
    Ok(_) => ()
    Err(message) => {
      println("prerender: " + message)
      @sys.exit(1)
    }
  }
  let texts : Map[String, String] = Map([])
  for f in files {
    texts.set(f.0, f.1)
  }
  let entries : Array[@search.Entry] = []
  let routes : Array[String] = [""]
  write_file(
    args.out + "/index.html",
    render_page({
      config,
      pages: manifest.pages,
      route: Landing,
      markdown: None,
    }),
  )
  for page in manifest.pages {
    let text = texts.get(page.source).unwrap_or("")
    write_file(
      args.out + "/" + page_path(page.route),
      render_page({
        config,
        pages: manifest.pages,
        route: page.route,
        markdown: Some(text),
      }),
    )
    write_file(args.out + "/content/" + page.source, text)
    let doc = @markdown.parse(
      text,
      @data.link_context(config, manifest, page.source),
    )
    for e in @search.entries_for(page.title, page.route, doc) {
      entries.push(e)
    }
    routes.push(page.route.to_path())
  }
  // `/docs/` shows the default page; GitHub Pages needs a real file for it.
  let default_route = manifest.default_route()
  match manifest.find(default_route) {
    Some(page) => {
      write_file(
        args.out + "/docs/index.html",
        render_page({
          config,
          pages: manifest.pages,
          route: default_route,
          markdown: Some(texts.get(page.source).unwrap_or("")),
        }),
      )
      routes.push("docs")
    }
    None => ()
  }
  write_file(
    args.out + "/404.html",
    render_page({
      config,
      pages: manifest.pages,
      route: NotFound("404"),
      markdown: None,
    }),
  )
  write_file(args.out + "/search-index.json", Json(entries).stringify())
  write_file(args.out + "/routes.json", Json(routes).stringify())
  println(
    "Built \{routes.length()} pages for \{config.version} at \{config.base} into \{args.out}",
  )
}

///|
/// Names that are build output or tool state, not part of an example.
fn is_skipped_name(name : String) -> Bool {
  name.has_prefix(".") || name == "_build" || name == "build"
}

///|
/// Every file under `dir` as a path relative to `dir`, skipping hidden entries
/// and build output.
fn list_files(dir : String, rel : String, out : Array[String]) -> Unit raise {
  let names = @fs.read_dir(dir).to_owned()
  names.sort_by(@content.lex_compare)
  for name in names {
    if is_skipped_name(name) {
      continue
    }
    let full = dir + "/" + name
    let relative = if rel == "" { name } else { rel + "/" + name }
    if @fs.is_dir(full) {
      list_files(full, relative, out)
    } else {
      out.push(relative)
    }
  }
}

///|
/// The directories of `<content>/examples`, each with its files and the title
/// of its README. A tree without `examples/` has none.
fn read_example_dirs(content : String) -> Array[@content.ExampleDir] raise {
  let root = content + "/examples"
  if !@fs.path_exists(root) {
    return []
  }
  let names = @fs.read_dir(root).to_owned()
  names.sort_by(@content.lex_compare)
  let out : Array[@content.ExampleDir] = []
  for name in names {
    let full = root + "/" + name
    if is_skipped_name(name) || !@fs.is_dir(full) {
      continue
    }
    let files : Array[String] = []
    list_files(full, "", files)
    let title = if files.contains("README.md") {
      @markdown.title_of(@fs.read_file_to_string(full + "/README.md"))
    } else {
      ""
    }
    out.push({ dir: name, title, files, })
  }
  out
}

///|
/// Writes `/examples/` and the page and the content copy of each example. Adds
/// the search entries and the routes. The index has one entry of its own: it has
/// no Markdown.
async fn write_examples(
  args : Args,
  config : @data.SiteConfig,
  manifest : @content.Manifest,
  examples : Array[@content.Example],
  texts : Map[String, String],
  entries : Array[@search.Entry],
  routes : Array[String],
) -> Unit {
  if examples.is_empty() {
    return
  }
  write_file(
    args.out + "/" + page_path(@route.Examples),
    render_page({
      config,
      pages: manifest.pages,
      examples,
      route: @route.Examples,
      markdown: None,
      playground: None,
    }),
  )
  entries.push({
    route: @route.Examples,
    anchor: "",
    page: "Examples",
    path: ["Examples"],
    text: examples.map(e => e.title + ". " + e.summary).join(" "),
  })
  routes.push(@route.Examples.to_path())
  for e in examples {
    let route : @route.Route = Example(e.dir)
    let text = texts.get(e.source()).unwrap_or("")
    write_file(
      args.out + "/" + page_path(route),
      render_page({
        config,
        pages: manifest.pages,
        examples,
        route,
        markdown: Some(text),
        playground: None,
      }),
    )
    write_file(args.out + "/content/" + e.source(), text)
    let doc = @markdown.parse(
      text,
      @data.link_context(config, manifest, examples, e.source()),
    )
    for entry in @search.entries_for(e.title, route, doc) {
      entries.push(entry)
    }
    routes.push(route.to_path())
  }
}

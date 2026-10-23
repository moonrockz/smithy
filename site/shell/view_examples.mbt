///|
/// One example card: a title, a line of text and a small label.
fn example_card(
  href : String,
  title : String,
  text : String,
  label : String,
) -> Html {
  @html.a(class="ms-excard", href~, [
    @html.b(title),
    @html.span(text),
    @html.i(label),
  ])
}

///|
/// The GitHub page of `examples/<dir>` at the ref of this build. The page is
/// a directory, so GitHub shows it as a `tree`.
fn example_tree_url(config : @data.SiteConfig, dir : String) -> String {
  examples_url(config) + "/" + dir
}

///|
/// The GitHub page of a file of an example at the ref of this build.
fn example_file_url(
  config : @data.SiteConfig,
  dir : String,
  file : String,
) -> String {
  @data.github_repo +
  "/blob/" +
  config.git_ref +
  "/examples/" +
  dir +
  "/" +
  file
}

///|
/// `/examples/`: one card for each example that has a README.
fn examples_index_view(m : Model) -> Html {
  let base = m.config.base
  @html.div(class="ms-example", [
    @html.p(class="ms-eyebrow", "Examples"),
    @html.h1("Start from a working project"),
    @html.p(
      class="ms-lead",
      "Each example is a directory of the repository. Its README gives the command to run it and the output to expect.",
    ),
    @html.div(
      class="ms-ex",
      m.examples.map(e => {
        example_card(
          @route.href(base, Example(e.dir)),
          e.title,
          e.summary,
          e.dir,
        )
      }),
    ),
  ])
}

///|
/// The link into the playground with the state of the example. It is a plain
/// link, so it works with no script: the pre-render knows the fragment.
fn playground_button(m : Model, e : @content.Example) -> Html {
  match e.playground {
    Some(fragment) =>
      @html.p(class="ms-example-playground", [
        @html.a(
          id="ms-open-playground",
          class="ms-btn ms-btn-primary",
          href=@route.href(m.config.base, Playground) + "#" + fragment,
          "Open in playground",
        ),
        @html.span(
          class="ms-hint",
          " Validate the model of this example in your browser. Nothing goes to a server.",
        ),
      ])
    None => @html.nothing
  }
}

///|
fn example_files_view(m : Model, e : @content.Example) -> Html {
  if e.files.is_empty() {
    return @html.nothing
  }
  @html.section(class="ms-example-files", [
    @html.h2("Files"),
    @html.ul(
      e.files.map(f => {
        @html.li([@html.a(href=example_file_url(m.config, e.dir, f), f)])
      }),
    ),
  ])
}

///|
/// `/examples/<dir>`: the README, then the other files of the directory.
fn example_view(m : Model, e : @content.Example) -> Html {
  let base = m.config.base
  let source_url = example_file_url(m.config, e.dir, "README.md")
  let body = match m.page {
    Ready(doc) => md_view(base, doc.blocks)
    Loading => @html.p(class="ms-loading", "Loading…")
    PageFailed =>
      @html.div(class="ms-error", [
        @html.p("This page could not be loaded."),
        @html.a(href=source_url, "Read it on GitHub"),
      ])
    NoContent => @html.nothing
  }
  @html.article(class="ms-example", [
    next_banner(m),
    @html.div(class="ms-crumbs", [
      @html.a(href=@route.href(base, Examples), "Examples"),
      @html.text(" / " + e.title),
    ]),
    playground_button(m, e),
    body,
    example_files_view(m, e),
    @html.p(class="ms-example-links", [
      @html.a(
        href=example_tree_url(m.config, e.dir),
        "View this example on GitHub",
      ),
      @html.text(" · "),
      @html.a(
        href=@data.github_repo + "/edit/main/" + e.source(),
        "Edit this page on GitHub",
      ),
    ]),
  ])
}

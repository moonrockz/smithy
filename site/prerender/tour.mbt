///|
/// The lessons of the checkout `content`. Every channel builds its own
/// checkout, so a lessons folder that does not read is a broken build.
fn load_tour(content : String) -> Result[@model.Tour, String] {
  @source.read_tour(content + "/" + @model.lessons_root, repo=content)
}

///|
fn link_of(lesson : @model.Lesson) -> @model.LessonLink {
  { slug: lesson.slug, title: lesson.title, }
}

///|
/// The contents of the tour: the sections in order, each with its lessons.
fn tour_contents(tour : @model.Tour) -> @model.TourContents {
  { sections: tour.sections().map(s => (s.0, s.1.map(link_of))), }
}

///|
/// The href of the `spec` of a lesson: a smithy.io URL as it is, or the docs
/// page of a repository path.
fn spec_href(config : @data.SiteConfig, spec : String) -> String {
  match @content.doc_route(spec) {
    Some(route) => @route.href(config.base, route)
    None => spec
  }
}

///|
/// The data of the page of `lesson`.
fn lesson_page(
  config : @data.SiteConfig,
  tour : @model.Tour,
  lesson : @model.Lesson,
) -> @model.LessonPage {
  let (previous, next) = tour.neighbours(lesson)
  {
    slug: lesson.slug,
    title: lesson.title,
    section: lesson.section,
    number: lesson.number,
    total: tour.lessons.length(),
    engine: lesson.engine,
    output: lesson.output,
    selector: lesson.selector,
    spec: spec_href(config, lesson.spec),
    files: lesson.files,
    digest: @model.digest(lesson.files),
    previous: previous.map(link_of),
    next: next.map(link_of),
    worker: worker_url(config),
    storage_key: "smithy-tour:" + config.channel.name() + ":" + lesson.slug,
    // The playground holds one model. It validates without the protocol
    // definitions, so it marks an OpenAPI model with an error (smithy-2qe.41.22).
    playground: if lesson.files.length() == 1 &&
      !(lesson.output is Some(OpenApi30 | OpenApi31)) {
      Some(@route.href(config.base, Playground))
    } else {
      None
    },
  }
}

///|
/// The search entry of the contents page. It has no Markdown.
fn tour_entry(tour : @model.Tour) -> @search.Entry {
  {
    route: Tour,
    anchor: "",
    page: "Tour",
    path: ["Tour"],
    text: "A tour of the Smithy language. Each lesson has a model that you can edit. Lessons: " +
    tour.lessons.map(l => l.title).join(", ") +
    ".",
  }
}

///|
/// Writes `/tour/` and the page of each lesson. Adds the search entries and
/// the routes.
async fn write_tour(
  args : Args,
  config : @data.SiteConfig,
  manifest : @content.Manifest,
  examples : Array[@content.Example],
  tour : @model.Tour,
  entries : Array[@search.Entry],
  routes : Array[String],
) -> Unit {
  write_file(
    args.out + "/" + page_path(@route.Tour),
    render_page({
      config,
      pages: manifest.pages,
      examples,
      route: Tour,
      markdown: None,
      playground: None,
      tour: Some(Contents(tour_contents(tour))),
    }),
  )
  entries.push(tour_entry(tour))
  routes.push(@route.Tour.to_path())
  for lesson in tour.lessons {
    let route : @route.Route = Lesson(lesson.slug)
    write_file(
      args.out + "/" + page_path(route),
      render_page({
        config,
        pages: manifest.pages,
        examples,
        route,
        markdown: Some(lesson.text),
        playground: None,
        tour: Some(Page(lesson_page(config, tour, lesson))),
      }),
    )
    let doc = @markdown.parse(
      lesson.text,
      @data.link_context(
        config,
        manifest,
        examples,
        @model.lesson_source(lesson.number, lesson.slug),
      ),
    )
    for entry in @search.entries_for(lesson.title, route, doc) {
      entries.push(entry)
    }
    routes.push(route.to_path())
  }
}

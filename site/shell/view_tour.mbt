///|
/// `/tour/`: one list for each section, the lessons numbered across the tour.
fn tour_contents_view(m : Model, contents : @model.TourContents) -> Html {
  let base = m.config.base
  let lists : Array[Html] = []
  let mut start = 1
  for section in contents.sections {
    let (name, lessons) = section
    lists.push(@html.h2(name))
    lists.push(
      @html.ol(
        class="tour-list",
        start~,
        lessons.map(l => {
          @html.li([@html.a(href=@route.href(base, Lesson(l.slug)), l.title)])
        }),
      ),
    )
    start = start + lessons.length()
  }
  @html.div(
    class="tour-contents",
    [
      @html.p(class="ms-eyebrow", "Tour"),
      @html.h1("The Smithy language tour"),
      @html.p(
        class="ms-lead",
        "Each lesson has a model that you can edit. The findings and the output change while you type. Everything runs in your browser.",
      ),
      ..lists,
    ],
  )
}

///|
/// The link to a neighbour lesson, or a plain label at the start or the end
/// of the tour.
fn lesson_link(
  base : String,
  link : @model.LessonLink?,
  label : String,
) -> Html {
  match link {
    Some(l) =>
      @html.a(
        class="tour-step",
        href=@route.href(base, Lesson(l.slug)),
        title=l.title,
        label,
      )
    None => @html.span(class="tour-step tour-step-off", label)
  }
}

///|
/// `/tour/<slug>`: the top bar, the lesson text and the empty panes. The tour
/// script mounts the lesson component into `tour-app`, starts the editor in
/// `tour-editor` and shows the output in `tour-output`.
fn lesson_view(m : Model, page : @model.LessonPage) -> Html {
  let base = m.config.base
  let text = match m.page {
    Ready(doc) => md_view(base, doc.blocks)
    _ => @html.nothing
  }
  @html.div(class="tour-lesson", [
    @html.header(class="tour-bar", [
      @html.a(
        class="tour-contents-link",
        href=@route.href(base, Tour),
        "Contents",
      ),
      @html.span(
        class="tour-place",
        "\{page.number} / \{page.total} · \{page.title}",
      ),
      @html.span(class="tour-steps", [
        lesson_link(base, page.previous, "← Back"),
        @html.text(" · "),
        lesson_link(base, page.next, "Next →"),
      ]),
    ]),
    @html.div(
      class=if page.is_static() { "tour-body tour-static" } else { "tour-body" },
      [
        @html.article(class="tour-text", [
          text,
          @html.p(class="tour-spec", [
            if page.spec.has_prefix(@model.spec_url_prefix) {
              @html.a(href=page.spec, [
                @html.text("Read this subject in the Smithy specification"),
                icon_external(),
              ])
            } else {
              @html.a(href=page.spec, [
                @html.text("Read the documentation of this feature"),
              ])
            },
          ]),
        ]),
        ..if page.is_static() {
          []
        } else {
          [
            @html.div(id="tour-app", class="tour-app", [
              @html.div(
                id="tour-editor",
                class="tour-editor",
                ([] : Array[Html]),
              ),
              @html.div(
                id="tour-output",
                class="tour-output",
                ([] : Array[Html]),
              ),
            ]),
          ]
        },
      ],
    ),
  ])
}

///|
/// A tour route: its page when the site data holds it, else not found.
fn tour_view(m : Model) -> Html {
  match current_tour(m.route, m.tour) {
    Some(Contents(contents)) => tour_contents_view(m, contents)
    Some(Page(page)) => lesson_view(m, page)
    None => not_found_view(m)
  }
}

///|
/// The title of a tour route, or `None` when the site data lacks its page.
fn tour_title(m : Model) -> String? {
  match current_tour(m.route, m.tour) {
    Some(Contents(_)) => Some("Tour")
    Some(Page(page)) => Some(page.title)
    None => None
  }
}

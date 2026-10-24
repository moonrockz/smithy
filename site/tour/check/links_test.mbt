///|
/// The links of the blocks and of the inlines, in order.
fn links_of(blocks : Array[@markdown.Block]) -> Array[@markdown.Target] {
  let result : Array[@markdown.Target] = []
  let stack : Array[@markdown.Inline] = []
  let inlines = fn(xs : Array[@markdown.Inline]) {
    for x in xs.rev() {
      stack.push(x)
    }
    while stack.pop() is Some(x) {
      match x {
        Link(target, xs) => {
          result.push(target)
          for y in xs.rev() {
            stack.push(y)
          }
        }
        Emph(xs) | Strong(xs) | Strike(xs) =>
          for y in xs.rev() {
            stack.push(y)
          }
        _ => ()
      }
    }
  }
  let todo : Array[@markdown.Block] = blocks.rev()
  while todo.pop() is Some(block) {
    match block {
      Heading(_, _, xs) | Paragraph(xs) => inlines(xs)
      Quote(bs) => todo.append(bs.rev())
      BulletList(items) | OrderedList(_, items) =>
        for item in items.rev() {
          todo.append(item.rev())
        }
      Table(head, rows) => {
        head.each(inlines)
        rows.each(row => row.each(inlines))
      }
      CodeBlock(_, _) | Rule => ()
    }
  }
  result
}

///|
/// A link from a lesson into the lessons folder must open a lesson page. A
/// link that the site sends to GitHub is a folder or a file that the site
/// does not publish, and a relative link to a lesson folder breaks on GitHub.
test "every link of a lesson into the lessons folder opens a lesson page" {
  let tour = match @source.read_tour(lessons_root) {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  let config : @data.SiteConfig = {
    base: "/smithy/",
    version: "next",
    channel: Next,
    git_ref: "main",
    release_base: "/smithy/",
    next_base: "/smithy/next/",
    release_version: "next",
    has_release: false,
  }
  let into_lessons = @data.github_repo + "/"
  for lesson in tour.lessons {
    let source = @model.lesson_source(lesson.number, lesson.slug)
    let doc = @markdown.parse(
      lesson.text,
      @data.link_context(config, { pages: [], }, [], source),
    )
    for target in links_of(doc.blocks) {
      guard target is External(url) && url.has_prefix(into_lessons) else {
        continue
      }
      if url.contains("/" + @model.lessons_root + "/") ||
        url.has_suffix("/" + @model.lessons_root) {
        fail(
          source +
          ": the link to " +
          url +
          " does not open a lesson page. Link to the lesson.md of the lesson, for example ../04-shape-ids/lesson.md",
        )
      }
    }
  }
}

///|
/// The diagnostics of one lesson case, of every severity.
fn case_diagnostics(
  dir : String,
  name : String,
) -> Array[@core.Diagnostic] raise {
  let tour = match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  guard tour.lessons.search_by(l => l.dir == dir) is Some(i) else {
    fail("I cannot find the lesson " + dir)
  }
  let lesson = tour.lessons[i]
  guard lesson.cases.search_by(c => c.name == name) is Some(j) else {
    fail("I cannot find the case " + dir + "/" + name)
  }
  let files = files_of(
    @model.model_files(lesson.engine, lesson.case_files(lesson.cases[j])),
  )
  match @core.handle(@core.Session::new(), ValidateFiles(seq=1, files~)) {
    Diagnostics(items~, ..) => items
    _ => fail(dir + "/" + name + ": unexpected answer")
  }
}

///|
/// Lesson 5 says that the Findings tab still lists a suppressed event, marked
/// SUPPRESSED. The level 1 check compares WARNING, DANGER and ERROR only.
test "the suppressed case of Reading findings lists the event as SUPPRESSED" {
  let items = case_diagnostics("05-reading-findings", "suppressed")
  assert_eq(items.map(d => (d.code, d.severity, d.shape)), [
    (
      "DeprecatedShape.example#Fahrenheit",
      "SUPPRESSED",
      Some("example#Reading$temperature"),
    ),
  ])
}

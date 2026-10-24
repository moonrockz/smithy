///|
/// The view of the model as HTML. `App::render` exists only on native.
#cfg(not(target="js"))
async fn render(m : Model) -> String {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state(m, update=(m, _, _) => {
      (m, @rabbita.none)
    })
    // The renderer needs a whole document.
    model.map(m => {
      @html.html([@html.head(([] : Array[Html])), @html.body([view(m, emit)])])
    })
  }).render(url="http://localhost/smithy/tour/hello-smithy/")
}

///|
#cfg(not(target="js"))
async test "the view has one tab per file and the tabs Findings and the output name" {
  let (m, _) = Model::start(two_file_page(), None)
  let html = render(m)
  assert_true(html.contains(">a.smithy</button>"))
  assert_true(html.contains(">b.smithy</button>"))
  assert_true(html.contains(">Findings"))
  assert_true(html.contains(">JSON AST</button>"))
  assert_eq(html.split("role=\"tab\"").count() - 1, 4)
  // The editors mount in these elements.
  assert_true(html.contains("id=\"\{EDITOR_ID}\""))
  assert_true(html.contains("id=\"\{OUTPUT_ID}\""))
}

///|
#cfg(not(target="js"))
async test "a lesson about findings has only the Findings tab" {
  let (m, _) = Model::start(findings_page(), None)
  let html = render(m)
  assert_true(html.contains(">Findings"))
  assert_false(html.contains(">JSON AST</button>"))
  assert_eq(html.split("role=\"tab\"").count() - 1, 2)
  // The output editor keeps its element, hidden.
  assert_true(html.contains("id=\"\{OUTPUT_ID}\""))
}

///|
#cfg(not(target="js"))
async test "the view hides Open in playground when page.playground is None" {
  let (m, _) = Model::start(two_file_page(), None)
  assert_false(render(m).contains("Open in playground"))
  let (m, _) = Model::start(page(), None)
  assert_true(render(m).contains("Open in playground"))
  assert_true(render(m).contains("Reset"))
}

///|
#cfg(not(target="js"))
async test "the view lists the findings with their place" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 2)])),
  )
  let html = render(m)
  assert_true(html.contains("model.smithy:2:1"))
  assert_true(html.contains("Model"))
  assert_true(html.contains("ERROR"))
  assert_true(html.contains("1 finding"))
}

///|
#cfg(not(target="js"))
async test "the view shows the blocked reason in place of the output" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(
    m,
    Answered(seq=1, answer=Checked([error_in("model.smithy", 2)])),
  )
  let (m, _) = update(m, SelectPane(OutputPane))
  let html = render(m)
  assert_true(
    html.contains(
      "The model has 1 error, so I did not make the JSON AST. The Findings tab shows the error.",
    ),
  )
  assert_true(html.contains("tour-outwrap tour-off"))
}

///|
/// The start tag of the button with this label.
#cfg(not(target="js"))
fn button_tag(html : String, label : String) -> String {
  guard html.find(">" + label + "</button>") is Some(end) else { return "" }
  guard html[:end].rev_find("<button") is Some(start) else { return "" }
  html[start:end].to_owned()
}

///|
#cfg(not(target="js"))
async test "the view marks the selected tabs" {
  let (m, _) = Model::start(two_file_page(), None)
  let (m, _) = update(m, SelectFile(1))
  let html = render(m)
  assert_true(button_tag(html, "b.smithy").contains("aria-selected=\"true\""))
  assert_true(button_tag(html, "b.smithy").contains("tour-tab-on"))
  assert_true(button_tag(html, "a.smithy").contains("aria-selected=\"false\""))
  assert_true(button_tag(html, "JSON AST").contains("aria-selected=\"true\""))
}

///|
test "each output has a tab name" {
  assert_eq(output_label(JsonAst), "JSON AST")
  assert_eq(output_label(JsonSchema), "JSON Schema")
  assert_eq(output_label(Selector), "Selector")
}

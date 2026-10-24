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

///|
/// The text of the start tag of the expand button of a pane, "" when it has none.
#cfg(not(target="js"))
fn expand_tag(html : String, name : String) -> String {
  guard html.find("aria-label=\"" + name + "\"") is Some(at) else { return "" }
  guard html[:at].rev_find("<button") is Some(start) else { return "" }
  guard html[at:].find(">") is Some(end) else { return "" }
  html[start:at + end + 1].to_owned()
}

///|
#cfg(not(target="js"))
async test "each pane has an expand button with a name, a title and a state" {
  let (m, _) = Model::start(page(), None)
  let html = render(m)
  assert_true(html.contains("class=\"tour-panes\""))
  let editor = expand_tag(html, "Expand the editor")
  let output = expand_tag(html, "Expand the output")
  for tag in [editor, output] {
    assert_true(tag.contains("tour-expand"))
    assert_true(tag.contains("type=\"button\""))
    assert_true(tag.contains("aria-pressed=\"false\""))
  }
  assert_true(editor.contains("title=\"Expand the editor\""))
  assert_true(output.contains("title=\"Expand the output\""))
  assert_eq(html.split("class=\"tour-expand\"").count() - 1, 2)
}

///|
#cfg(not(target="js"))
async test "the pressed button keeps its name, and its tooltip says Show both panes" {
  let (m, _) = Model::start(page(), None)
  let (m, _) = update(m, ToggleExpand(EditorSide))
  let html = render(m)
  assert_true(html.contains("class=\"tour-panes tour-editor-only\""))
  let pressed = expand_tag(html, "Expand the editor")
  assert_true(pressed.contains("aria-pressed=\"true\""))
  assert_true(pressed.contains("title=\"Show both panes\""))
  let other = expand_tag(html, "Expand the output")
  assert_true(other.contains("aria-pressed=\"false\""))
  assert_true(other.contains("title=\"Expand the output\""))
  assert_false(html.contains("aria-label=\"Show both panes\""))
  let (m, _) = update(m, ToggleExpand(OutputSide))
  let html = render(m)
  assert_true(html.contains("class=\"tour-panes tour-output-only\""))
  assert_true(
    expand_tag(html, "Expand the output").contains("aria-pressed=\"true\""),
  )
  assert_true(
    expand_tag(html, "Expand the editor").contains("aria-pressed=\"false\""),
  )
}

///|
#cfg(not(target="js"))
async test "both panes and both editor elements stay in the DOM in every layout" {
  let (m, _) = Model::start(page(), None)
  for layout in [Split, EditorOnly, OutputOnly] {
    let html = render({ ..m, layout, })
    assert_true(html.contains("tour-pane tour-edit"))
    assert_true(html.contains("tour-pane tour-out"))
    assert_true(html.contains("id=\"\{EDITOR_ID}\""))
    assert_true(html.contains("id=\"\{OUTPUT_ID}\""))
  }
}

///|
using @html {type Html}

///|
fn plural(n : Int32, one : String, many : String) -> String {
  if n == 1 {
    "1 " + one
  } else {
    "\{n} " + many
  }
}

///|
fn tab(on : Bool, click : @rabbita.Cmd, label : Array[Html]) -> Html {
  @html.button(
    class=if on { "tour-tab tour-tab-on" } else { "tour-tab" },
    attrs=@html.Attrs::build()
      .role("tab")
      .aria_selected(if on { "true" } else { "false" }),
    on_click=click,
    label,
  )
}

///|
fn file_tabs(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  @html.div(
    class="tour-tabs",
    attrs=@html.Attrs::build().role("tablist").aria_label("Files"),
    m.files.mapi((i, file) => {
      tab(i == m.selected, emit(SelectFile(i)), [@html.text(file.name)])
    }),
  )
}

///|
fn actions(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let open : Array[Html] = match m.page.playground {
    Some(_) =>
      [
        @html.button(
          class="tour-btn",
          title="Open the model in the playground",
          on_click=emit(OpenPlayground),
          "Open in playground",
        ),
      ]
    None => []
  }
  let problem : Array[Html] = match m.link_problem {
    Some(text) => [@html.span(class="tour-note", text)]
    None => []
  }
  @html.div(
    class="tour-actions",
    [
      @html.button(
        class="tour-btn",
        title="Restore the starting files of the lesson",
        on_click=emit(Reset),
        "Reset",
      ),
      ..open,
      ..problem,
    ],
  )
}

///|
fn editor_pane(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  @html.section(class="tour-pane tour-edit", [
    file_tabs(m, emit),
    // The editor owns the children of this element. It must stay at the
    // same place, with the same attributes, in every render.
    @html.div(id=EDITOR_ID, class="tour-editor", ([] : Array[Html])),
    actions(m, emit),
  ])
}

///|
fn location(d : @core.Diagnostic) -> String {
  if d.start_line > 0 {
    "\{d.file}:\{d.start_line}:\{d.start_column}"
  } else if d.file != "" {
    d.file
  } else {
    "no place in the model"
  }
}

///|
fn finding(d : @core.Diagnostic) -> Html {
  @html.li(class="tour-finding tour-sev-" + d.severity.to_lower(), [
    @html.span(class="tour-sev", d.severity),
    @html.code(class="tour-code", d.code),
    @html.span(class="tour-place", location(d)),
    @html.span(class="tour-message", d.message),
  ])
}

///|
fn findings_panel(m : Model) -> Array[Html] {
  match m.findings {
    Unchecked => [@html.p(class="tour-note", "I am checking the model.")]
    Found([]) => [@html.p(class="tour-note", "The model has no findings.")]
    Found(items) =>
      [
        @html.p(
          class="tour-note",
          plural(items.length(), "finding", "findings"),
        ),
        @html.ul(class="tour-findings", items.map(finding)),
      ]
    NotChecked(reason) => [@html.p(class="tour-note tour-err", reason)]
  }
}

///|
fn output_notice(m : Model) -> Array[Html] {
  match (m.output, m.page.output) {
    (NoOutput, Some(output)) =>
      [@html.p(class="tour-note", "I am making the \{output_label(output)}.")]
    (NotShown(reason), _) => [@html.p(class="tour-note tour-err", reason)]
    _ => []
  }
}

///|
fn panel(on : Bool, children : Array[Html]) -> Html {
  @html.div(
    class=if on { "tour-panel" } else { "tour-panel tour-off" },
    attrs=@html.Attrs::build().role("tabpanel"),
    children,
  )
}

///|
fn output_pane(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let count = match m.findings {
    Found(items) if items.length() > 0 =>
      [@html.span(class="tour-count", " \{items.length()}")]
    _ => []
  }
  let output_tab = match m.page.output {
    Some(output) =>
      [
        tab(m.pane == OutputPane, emit(SelectPane(OutputPane)), [
          @html.text(output_label(output)),
        ]),
      ]
    None => []
  }
  let busy = if m.busy() {
    [@html.span(class="tour-busy", "checking…")]
  } else {
    []
  }
  let on_output = m.page.output is Some(_) && m.pane == OutputPane
  @html.section(class="tour-pane tour-out", [
    @html.div(
      class="tour-tabs",
      attrs=@html.Attrs::build().role("tablist").aria_label("Results"),
      [
        tab(
          m.pane == FindingsPane,
          emit(SelectPane(FindingsPane)),
          [@html.text("Findings"), ..count],
        ),
        ..output_tab,
        ..busy,
      ],
    ),
    panel(m.pane == FindingsPane, findings_panel(m)),
    // The output editor owns the children of its element. Every slot stays
    // at the same place in every render, so the editor keeps its element;
    // a lesson without an output keeps it hidden.
    panel(on_output, [
      @html.div(class="tour-notices", output_notice(m)),
      @html.div(
        class=if m.output is Shown(..) {
          "tour-outwrap"
        } else {
          "tour-outwrap tour-off"
        },
        [@html.div(id=OUTPUT_ID, class="tour-output", ([] : Array[Html]))],
      ),
    ]),
  ])
}

///|
/// The right-hand panes of a lesson: the editor with a tab for each file,
/// and the output with the Findings tab and the tab of the lesson output.
pub fn view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  @html.div(class="tour-panes", [editor_pane(m, emit), output_pane(m, emit)])
}

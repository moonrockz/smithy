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
/// The button that expands a pane to the column, or gives the split view back.
fn expand_button(
  m : Model,
  side : Expandable,
  emit : @rabbita.Emit[Msg],
) -> Html {
  // The name stays the same; aria-pressed tells the state. The tooltip says
  // what a press does.
  let name = match side {
    EditorSide => "Expand the editor"
    OutputSide => "Expand the output"
  }
  let pressed = match (side, m.layout) {
    (EditorSide, EditorOnly) | (OutputSide, OutputOnly) => true
    _ => false
  }
  @html.button(
    class="tour-expand",
    title=if pressed { "Show both panes" } else { name },
    on_click=emit(ToggleExpand(side)),
    attrs=@html.Attrs::build()
      .type_("button")
      .aria_label(name)
      .aria_pressed(if pressed { "true" } else { "false" }),
    [
      @html.span(
        class="tour-expand-icon",
        attrs=@html.Attrs::build().aria_hidden("true"),
        if pressed {
          "⤡"
        } else {
          "⤢"
        },
      ),
    ],
  )
}

///|
/// The header of a pane: its tabs and its expand button.
fn head(
  tabs : Html,
  m : Model,
  side : Expandable,
  emit : @rabbita.Emit[Msg],
) -> Html {
  @html.div(class="tour-head", [tabs, expand_button(m, side, emit)])
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
    head(file_tabs(m, emit), m, EditorSide, emit),
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
  match (m.output, output_label(m.page.engine, m.page.output)) {
    (NoOutput, Some(label)) =>
      [@html.p(class="tour-note", "I am making the \{label}.")]
    (NotShown(reason), _) => [@html.p(class="tour-note tour-err", reason)]
    _ => []
  }
}

///|
/// The message of an entry, cut to `MESSAGE_CHARS` characters.
fn short_message(message : String) -> String {
  let chars = message.to_array()
  if chars.length() > MESSAGE_CHARS {
    String::from_array(chars[:MESSAGE_CHARS]) + " …"
  } else {
    message
  }
}

///|
/// The lines of the CLI for the findings of one entry, or of no entry.
fn line_items(lines : Array[String], changed : Array[String]) -> Array[Html] {
  lines.map(line => {
    @html.li(
      class=if changed.contains(line) {
        "tour-finding tour-changed"
      } else {
        "tour-finding"
      },
      [@html.code(class="tour-cli", line)],
    )
  })
}

///|
fn entry_row(
  t : Transcript,
  file : String,
  changed : Array[String],
  entry : @core.EntryView,
) -> Html {
  let own = t.findings.filter(f => f.entry == Some(entry.index))
  let lines = own.map(f => f.cli_line(file~))
  let pending = entry.index >= t.checked
  let route = match entry.receiver {
    Some(receiver) => "\{entry.sender} → \{receiver}"
    None => "\{entry.sender} → reply"
  }
  let mark : Array[Html] = if !pending && own.is_empty() {
    [@html.span(class="tour-check", "✓")]
  } else {
    []
  }
  @html.li(
    class=if pending { "tour-entry tour-entry-pending" } else { "tour-entry" },
    [
      @html.div(
        class="tour-entry-head",
        [
          @html.span(class="tour-entry-no", "#\{entry.index}"),
          @html.span(class="tour-entry-route", route),
          ..mark,
        ],
      ),
      @html.div(class="tour-entry-message", short_message(entry.message)),
      @html.ul(class="tour-findings", line_items(lines, changed)),
    ],
  )
}

///|
fn verdict(summary : @core.SummaryView) -> Html {
  let valid = if summary.valid { "valid" } else { "not valid" }
  let complete = if summary.complete { "complete" } else { "partial" }
  @html.div(class="tour-verdict", [
    @html.strong("\{valid}, \{complete}"),
    @html.span(
      class="tour-counts",
      " · " +
      plural(summary.entries, "entry checked", "entries checked") +
      ", " +
      plural(summary.errors, "error finding", "error findings") +
      ", " +
      plural(
        summary.outstanding,
        "call without a reply",
        "calls without a reply",
      ),
    ),
  ])
}

///|
/// The buttons Step and Run all.
fn step_buttons(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let off = m.busy() || m.transcript.map(t => t.done).unwrap_or(true)
  @html.div(class="tour-steps", [
    @html.button(
      id="tour-step",
      class="tour-btn",
      disabled=off,
      title="Check the next entry",
      on_click=emit(StepClicked),
      "Step",
    ),
    @html.button(
      id="tour-runall",
      class="tour-btn",
      disabled=off,
      title="Check all the entries that are left",
      on_click=emit(RunAllClicked),
      "Run all",
    ),
  ])
}

///|
/// The Transcript tab: the entries of the transcript with the CLI lines of
/// their findings, then the findings with no entry, then the verdict.
fn transcript_panel(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  let buttons = step_buttons(m, emit)
  match (m.transcript, m.not_run) {
    (Some(t), _) => {
      let file = m.transcript_file()
      let changed = t.changed_lines(file)
      let loose = t.findings
        .filter(f => f.entry is None)
        .map(f => f.cli_line(file~))
      let expect : Array[String] = match t.summary {
        Some({ expectations: Some(expectations), .. }) =>
          expectations.cli_lines(file~)
        _ => []
      }
      let rest : Array[Html] = []
      if !loose.is_empty() {
        rest.push(@html.p(class="tour-note", "Findings with no entry"))
        rest.push(@html.ul(class="tour-findings", line_items(loose, changed)))
      }
      if !expect.is_empty() {
        rest.push(@html.p(class="tour-note", "Expectations"))
        rest.push(@html.ul(class="tour-findings", line_items(expect, changed)))
      }
      if t.summary is Some(summary) {
        rest.push(verdict(summary))
      }
      [
        buttons,
        @html.p(
          class="tour-note tour-progress",
          "\{t.checked} of \{t.entries.length()} entries checked",
        ),
        @html.ul(
          class="tour-entries",
          t.entries.map(entry => entry_row(t, file, changed, entry)),
        ),
        ..rest,
      ]
    }
    (None, Some(reason)) =>
      [buttons, @html.p(class="tour-note tour-err", reason)]
    (None, None) =>
      [buttons, @html.p(class="tour-note", "I am checking the transcript.")]
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
  let output_tab = match output_label(m.page.engine, m.page.output) {
    Some(label) =>
      [
        tab(m.pane == OutputPane, emit(SelectPane(OutputPane)), [
          @html.text(label),
        ]),
      ]
    None => []
  }
  let transcript_tab = if m.transcript_setup() is Some(_) {
    [
      tab(m.pane == TranscriptPane, emit(SelectPane(TranscriptPane)), [
        @html.text("Transcript"),
      ]),
    ]
  } else {
    []
  }
  let busy = if m.busy() {
    [@html.span(class="tour-busy", "checking…")]
  } else {
    []
  }
  let on_output = has_output_pane(m.page) && m.pane == OutputPane
  @html.section(
    class="tour-pane tour-out",
    [
      head(
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
            ..transcript_tab,
            ..busy,
          ],
        ),
        m,
        OutputSide,
        emit,
      ),
      panel(m.pane == FindingsPane, findings_panel(m)),
      ..if m.transcript_setup() is Some(_) {
        [panel(m.pane == TranscriptPane, transcript_panel(m, emit))]
      } else {
        []
      },
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
    ],
  )
}

///|
/// The right-hand panes of a lesson: the editor with a tab for each file,
/// and the output with the Findings tab and the tab of the lesson output.
pub fn view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  // Both panes stay in the DOM in every layout: the editors own their
  // elements, so a class hides a pane.
  let class_ = match m.layout {
    Split => "tour-panes"
    EditorOnly => "tour-panes tour-editor-only"
    OutputOnly => "tour-panes tour-output-only"
  }
  @html.div(class=class_, [editor_pane(m, emit), output_pane(m, emit)])
}

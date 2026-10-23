///|
using @html {type Html}

///|
/// The most diagnostics that the list shows. A large model can have
/// thousands; the editor still marks all of them.
pub const MAX_LISTED : Int32 = 200

///|
fn plural(n : Int32, one : String, many : String) -> String {
  if n == 1 {
    "1 " + one
  } else {
    "\{n} " + many
  }
}

///|
/// The id of the element that the editor mounts in.
pub const EDITOR_ID : String = "pg-editor"

///|
/// The id of the element that the playground mounts in.
pub const APP_ID : String = "pg-app"

///|
fn toolbar(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let options = m.data.samples.mapi((i, sample) => {
    @html.option(value=i.to_string(), selected=i == m.sample, sample.title)
  })
  @html.div(class="pg-toolbar", [
    @html.label(class="pg-hint", for_="pg-example", "Example"),
    @html.select(
      id="pg-example",
      class="pg-select",
      on_change=emit.map(value => {
        SampleChosen(@string.parse_int(value) catch { _ => -1 })
      }),
      options,
    ),
    @html.button(
      class="pg-btn",
      disabled=true,
      title="Not available yet",
      "Share link",
    ),
    @html.button(
      class="pg-btn",
      disabled=true,
      title="Not available yet",
      "Download",
    ),
    @html.span(class="pg-spacer", ([] : Array[Html])),
    @html.span(class="pg-pill", "Runs in your browser"),
    @html.span(class="pg-hint", "smithy \{m.data.version} · no server"),
  ])
}

///|
fn check_status(m : Model) -> Html {
  let checking = if m.waiting {
    [@html.span(class="pg-hint", " · checking")]
  } else {
    []
  }
  let main = match m.check {
    Unchecked => @html.span(class="pg-hint", "Not checked")
    Checked(..) if m.errors() > 0 =>
      @html.span(class="pg-err", "● " + plural(m.errors(), "error", "errors"))
    Checked(..) => @html.span(class="pg-ok", "✓ valid")
    Refused(_) => @html.span(class="pg-hint", "Not checked")
    Stopped => @html.span(class="pg-err", "Stopped")
    Failed(_) => @html.span(class="pg-err", "Failed")
  }
  let warnings = if m.warnings() > 0 {
    [
      @html.span(
        class="pg-hint",
        " · " + plural(m.warnings(), "warning", "warnings"),
      ),
    ]
  } else {
    []
  }
  @html.span(class="pg-check", [main, ..warnings, ..checking])
}

///|
fn model_pane(m : Model) -> Html {
  @html.section(class="pg-pane pg-model", [
    @html.div(class="pg-panehead", [
      @html.b("model.smithy"),
      @html.text(" · IDL 2.0"),
      @html.span(class="pg-spacer", ([] : Array[Html])),
      @html.span(
        class="pg-hint pg-fold-hint",
        "Fold: click ▾ in the gutter · Ctrl-Shift-[ and ]",
      ),
    ]),
    // The editor owns the children of this element. It must stay at the
    // same place, with the same attributes, in every render.
    @html.div(id=EDITOR_ID, class="pg-editor", ([] : Array[Html])),
    @html.div(
      class="pg-status",
      attrs=@html.Attrs::build().data_set(
        "waiting",
        if m.waiting {
          "true"
        } else {
          "false"
        },
      ),
      [
        check_status(m),
        @html.span(class="pg-cursor", "Ln \{m.line}, Col \{m.column}"),
      ],
    ),
  ])
}

///|
fn tab_button(
  m : Model,
  emit : @rabbita.Emit[Msg],
  tab : Tab,
  label : String,
  extra : Array[Html],
) -> Html {
  let on = m.tab == tab
  @html.button(
    class=if on { "pg-tab pg-tab-on" } else { "pg-tab" },
    attrs=@html.Attrs::build()
      .role("tab")
      .aria_selected(if on { "true" } else { "false" }),
    on_click=emit(TabChosen(tab)),
    [@html.text(label), ..extra],
  )
}

///|
fn location(d : Diagnostic) -> String {
  if d.start_line > 0 {
    "\{d.file}:\{d.start_line}:\{d.start_column}"
  } else if d.file != "" {
    d.file
  } else {
    "no place in the model"
  }
}

///|
/// A row of a result for older text names a place in that text, so a click
/// on it does not move the cursor.
fn diagnostic_row(
  d : Diagnostic,
  current : Bool,
  emit : @rabbita.Emit[Msg],
) -> Html {
  let severity = d.severity.to_lower()
  let shape = match d.shape {
    Some(id) => [@html.text(" · "), @html.span(class="pg-shape", id)]
    None => []
  }
  let body = [
    @html.span(class="pg-sev pg-sev-" + severity, d.severity),
    @html.div(class="pg-diag-text", [
      @html.div(class="pg-msg", d.message),
      @html.div(
        class="pg-loc",
        [
          @html.text(location(d) + " · "),
          @html.span(class="pg-code", d.code),
          ..shape,
        ],
      ),
    ]),
  ]
  if !current {
    @html.div(class="pg-diag pg-diag-stale", body)
  } else if d.start_line > 0 {
    @html.button(
      class="pg-diag",
      title="Go to line \{d.start_line}",
      on_click=emit(DiagnosticChosen(line=d.start_line, column=d.start_column)),
      body,
    )
  } else {
    @html.div(class="pg-diag", body)
  }
}

///|
fn validate_panel(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  match m.check {
    Unchecked => [@html.p(class="pg-empty", "The model is being checked.")]
    Refused(reason) => [@html.p(class="pg-notice", reason)]
    Stopped =>
      [
        @html.p(
          class="pg-notice",
          "The check took more than 10 seconds, so the playground stopped it and started a new Worker. Change the model to check it again.",
        ),
      ]
    Failed(message) => {
      let detail = if message == "" {
        []
      } else {
        [@html.code(class="pg-detail", message)]
      }
      [
        @html.div(
          class="pg-notice",
          [
            @html.p(
              "The check failed because the Worker stopped with an error. The playground started a new Worker. Change the model to check it again.",
            ),
            ..detail,
          ],
        ),
      ]
    }
    Checked(items~, shapes~) => {
      let head = if m.errors() == 0 {
        [
          @html.div(
            class="pg-okbox",
            "✓ The model is valid. " + plural(shapes, "shape", "shapes") + ".",
          ),
        ]
      } else {
        []
      }
      let listed = items[:if items.length() > MAX_LISTED {
          MAX_LISTED
        } else {
          items.length()
        }]
      let current = m.is_current()
      let rows = listed
        .iter()
        .map(d => diagnostic_row(d, current, emit))
        .to_array()
      let more = if items.length() > MAX_LISTED {
        [
          @html.p(
            class="pg-empty",
            plural(
              items.length() - MAX_LISTED,
              "more diagnostic is",
              "more diagnostics are",
            ) +
            " not in the list. The editor marks all of them.",
          ),
        ]
      } else {
        []
      }
      let hint = if items.is_empty() {
        [
          @html.p(
            class="pg-empty",
            "The diagnostics change when you change the model.",
          ),
        ]
      } else {
        []
      }
      [..head, ..rows, ..more, ..hint]
    }
  }
}

///|
fn results_pane(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let count = if m.errors() > 0 {
    [@html.span(class="pg-count", m.errors().to_string())]
  } else {
    []
  }
  let panel = match m.tab {
    ValidateTab => validate_panel(m, emit)
    TransformTab | TranscriptTab =>
      [@html.p(class="pg-empty", "This tab is not available yet.")]
  }
  @html.section(class="pg-pane pg-results", [
    @html.div(class="pg-tabs", attrs=@html.Attrs::build().role("tablist"), [
      tab_button(m, emit, ValidateTab, "Validate", count),
      tab_button(m, emit, TransformTab, "Transform", []),
      tab_button(m, emit, TranscriptTab, "Transcript", []),
    ]),
    @html.div(
      class="pg-panel",
      attrs=@html.Attrs::build().role("tabpanel"),
      panel,
    ),
  ])
}

///|
/// The workbench: the toolbar, the model editor and the result tabs. The
/// pre-render shows it with no result; the playground script then mounts it
/// again in the element with id `APP_ID` and starts the editor.
pub fn view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  @html.div(class="pg", [
    toolbar(m, emit),
    @html.div(class="pg-bench", [
      model_pane(m),
      @html.div(class="pg-splitter", ([] : Array[Html])),
      results_pane(m, emit),
    ]),
  ])
}

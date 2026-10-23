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
/// The id of the element that the output editor mounts in.
pub const OUTPUT_ID : String = "pg-output"

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
  let checking = if m.checking() {
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
pub fn Output::label(self : Output) -> String {
  match self {
    JsonAst => "JSON AST"
    Idl => "Formatted IDL"
    Selector => "Selector query"
    JsonSchema => "JSON Schema"
    OpenApi30 => "OpenAPI 3.0.2"
    OpenApi31 => "OpenAPI 3.1.0"
    OpenRpc => "OpenRPC 1.3.2"
  }
}

///|
pub let outputs : Array[Output] = [
  JsonAst,
  Idl,
  Selector,
  JsonSchema,
  OpenApi30,
  OpenApi31,
  OpenRpc,
]

///|
/// The name of an output in the `value` of the picker.
fn Output::key(self : Output) -> String {
  match self {
    JsonAst => "json-ast"
    Idl => "idl"
    Selector => "selector"
    JsonSchema => "json-schema"
    OpenApi30 => "openapi-3.0.2"
    OpenApi31 => "openapi-3.1.0"
    OpenRpc => "openrpc"
  }
}

///|
fn output_of_key(key : String) -> Output? {
  outputs.iter().find_first(output => output.key() == key)
}

///|
/// The text in single quotes for a POSIX shell.
fn shell_quote(text : String) -> String {
  "'" + text.replace_all(old="'", new="'\\''") + "'"
}

///|
/// The CLI command that gives the same output. JSON Schema, OpenAPI and
/// OpenRPC are plugins of `smithy build`, so the hint names the plugin and
/// its settings. An IDL output with several files needs `--output-dir`.
pub fn cli_hint(output : Output, selector : String, files : Int32) -> String {
  match output {
    JsonAst => "smithy convert --to json model.smithy"
    Idl =>
      if files > 1 {
        "smithy convert --to idl --output-dir DIR model.smithy"
      } else {
        "smithy convert --to idl model.smithy"
      }
    Selector => "smithy select --selector \{shell_quote(selector)} model.smithy"
    JsonSchema =>
      "smithy build --config smithy-build.json, with the plugin \"jsonSchema\""
    OpenApi30 =>
      "smithy build --config smithy-build.json, with the plugin \"openapi\" and \"version\": \"3.0.2\""
    OpenApi31 =>
      "smithy build --config smithy-build.json, with the plugin \"openapi\" and \"version\": \"3.1.0\""
    OpenRpc =>
      "smithy build --config smithy-build.json, with the plugin \"openrpc\""
  }
}

///|
fn transform_controls(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let options = outputs.map(output => {
    @html.option(
      value=output.key(),
      selected=output == m.output,
      output.label(),
    )
  })
  let selector = if m.output == Selector {
    [
      @html.input(
        id="pg-selector",
        class="pg-input",
        placeholder="structure > member",
        value=m.selector,
        on_input=emit.map(text => SelectorEdited(text)),
        attrs=@html.Attrs::build().aria_label("Selector"),
      ),
    ]
  } else {
    []
  }
  let done = m.tx is TxDone(..)
  @html.div(class="pg-rowctl", [
    @html.label(class="pg-hint", for_="pg-output-kind", "Output"),
    @html.select(
      id="pg-output-kind",
      class="pg-select",
      on_change=emit.map(key => {
        match output_of_key(key) {
          Some(output) => OutputChosen(output)
          None => OutputChosen(m.output)
        }
      }),
      options,
    ),
    @html.div(class="pg-selector-slot", selector),
    @html.button(
      id="pg-run",
      class="pg-btn pg-btn-primary",
      disabled=m.tx == TxRunning,
      on_click=emit(RunClicked),
      if m.tx == TxRunning {
        "Running"
      } else {
        "Run"
      },
    ),
    @html.span(class="pg-spacer", ([] : Array[Html])),
    @html.button(
      id="pg-copy",
      class="pg-btn",
      disabled=!done,
      on_click=emit(CopyClicked),
      "Copy",
    ),
    @html.button(
      id="pg-download-output",
      class="pg-btn",
      disabled=!done,
      on_click=emit(DownloadClicked),
      "Download",
    ),
  ])
}

///|
fn transform_notice(m : Model) -> Array[Html] {
  match m.tx {
    TxIdle =>
      [
        @html.p(
          class="pg-empty",
          "Choose an output, then select Run. The playground converts the model in your browser.",
        ),
      ]
    TxRunning =>
      [@html.p(class="pg-empty", "The playground runs the transform.")]
    TxBlocked(reason~, by~) =>
      [
        @html.p(
          class="pg-notice",
          match by {
            ModelErrors =>
              "The model has errors. Fix them in the Validate tab first."
            Other => reason
          },
        ),
      ]
    TxStopped =>
      [
        @html.p(
          class="pg-notice",
          "The transform took more than 10 seconds, so the playground stopped it and started a new Worker. Select Run to try again.",
        ),
      ]
    TxFailed(message) => {
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
              "The transform failed because the Worker stopped with an error. The playground started a new Worker. Select Run to try again.",
            ),
            ..detail,
          ],
        ),
      ]
    }
    TxDone(files~, edits~, ..) => {
      let stale = if edits != m.edits {
        [
          @html.p(
            class="pg-stale",
            "The model changed after this run. Select Run to update the output.",
          ),
        ]
      } else {
        []
      }
      let copy = match m.copy {
        NotCopied => []
        Copied => [@html.p(class="pg-hint", "Copied to the clipboard.")]
        CopyFailed =>
          [
            @html.p(
              class="pg-stale",
              "The browser did not let the playground copy. Select the text and copy it.",
            ),
          ]
      }
      let empty = if files.is_empty() {
        [@html.p(class="pg-empty", "The transform gave no file.")]
      } else {
        []
      }
      [..stale, ..copy, ..empty]
    }
  }
}

///|
fn file_picker(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  match m.tx {
    TxDone(files~, file~, ..) if files.length() > 1 =>
      files.mapi((i, name) => {
        @html.button(
          class=if i == file { "pg-file pg-file-on" } else { "pg-file" },
          on_click=emit(FileChosen(i)),
          name,
        )
      })
    _ => []
  }
}

///|
fn warning_list(m : Model) -> Array[Html] {
  match m.tx {
    TxDone(warnings~, ..) if !warnings.is_empty() =>
      [
        @html.div(
          class="pg-warnings",
          [
            @html.b(plural(warnings.length(), "warning", "warnings")),
            ..warnings.map(line => @html.div(class="pg-warning", line)),
          ],
        ),
      ]
    _ => []
  }
}

///|
fn transform_panel(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  let (output, files) = match m.tx {
    TxDone(output~, files~, ..) => (output, files.length())
    _ => (m.output, 0)
  }
  let has_output = match m.tx {
    TxDone(files~, ..) => !files.is_empty()
    _ => false
  }
  let protocol_note = if m.output == OpenApi30 || m.output == OpenApi31 {
    [
      @html.p(
        class="pg-hint pg-note",
        "Note: the Validate tab can show errors for a model with @restJson1, and the OpenAPI output can still work. The OpenAPI transform loads the bundled OpenAPI protocol definitions. The Validate tab checks the model as smithy validate does.",
      ),
    ]
  } else {
    []
  }
  // The output editor owns the children of its element. Every slot stays at
  // the same place in every render, so the editor keeps its element.
  [
    transform_controls(m, emit),
    @html.p(
      class="pg-hint pg-cli",
      "CLI: " + cli_hint(output, m.selector, files),
    ),
    @html.div(class="pg-notices", transform_notice(m)),
    @html.div(class="pg-warnings-slot", warning_list(m)),
    @html.div(class="pg-files", file_picker(m, emit)),
    @html.div(
      class=if has_output { "pg-outwrap" } else { "pg-outwrap pg-off" },
      [@html.div(id=OUTPUT_ID, class="pg-editor", ([] : Array[Html]))],
    ),
    @html.div(class="pg-notes", protocol_note),
  ]
}

///|
fn panel(on : Bool, extra : String, children : Array[Html]) -> Html {
  @html.div(
    class=if on { "pg-panel " + extra } else { "pg-panel pg-off " + extra },
    attrs=@html.Attrs::build().role("tabpanel"),
    children,
  )
}

///|
fn results_pane(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let count = if m.errors() > 0 {
    [@html.span(class="pg-count", m.errors().to_string())]
  } else {
    []
  }
  @html.section(class="pg-pane pg-results", [
    @html.div(class="pg-tabs", attrs=@html.Attrs::build().role("tablist"), [
      tab_button(m, emit, ValidateTab, "Validate", count),
      tab_button(m, emit, TransformTab, "Transform", []),
      tab_button(m, emit, TranscriptTab, "Transcript", []),
    ]),
    panel(m.tab == ValidateTab, "pg-validate", validate_panel(m, emit)),
    panel(m.tab == TransformTab, "pg-transform", transform_panel(m, emit)),
    panel(m.tab == TranscriptTab, "pg-transcript", [
      @html.p(class="pg-empty", "This tab is not available yet."),
    ]),
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

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
      id="pg-share",
      class="pg-btn",
      title="Copy a link to this page with your model",
      on_click=emit(ShareClicked),
      "Share link",
    ),
    @html.button(
      id="pg-save",
      class="pg-btn",
      title="Save the model, and on the Transcript tab the transcript, as files",
      on_click=emit(SaveClicked),
      "Download",
    ),
    @html.span(class="pg-spacer", ([] : Array[Html])),
    @html.span(class="pg-pill", "Runs in your browser"),
    @html.span(class="pg-hint", "smithy \{m.data.version} · no server"),
  ])
}

///|
/// The line under the toolbar: what the share button did, or why the page
/// did not open a link. The element is always there, so a screen reader
/// reads each change.
fn share_status(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let content : Array[Html] = match m.share {
    NoShare => []
    LinkCopied(_) =>
      [
        @html.span(
          class="pg-ok",
          "The link is in the address bar and on your clipboard.",
        ),
      ]
    LinkShown(url) =>
      [
        @html.span(
          class="pg-hint",
          "Your browser cannot use the clipboard. Copy this link:",
        ),
        @html.input(
          id="pg-share-url",
          class="pg-input",
          value=url,
          read_only=true,
          attrs=@html.Attrs::build().aria_label("Link to this page"),
        ),
      ]
    LinkTooLong(reason) => [@html.span(class="pg-err", reason)]
    LinkIgnored(reason) =>
      [@html.span(class="pg-err", reason + " I kept your page as it was.")]
    LinkRefused(reason) =>
      [
        @html.span(
          class="pg-err",
          reason + " I opened the default example instead.",
        ),
      ]
  }
  let ask : Array[Html] = match m.incoming {
    Some(_) =>
      [
        @html.span(
          id="pg-incoming-text",
          "Open the new link? You will lose your changes.",
        ),
        @html.button(
          id="pg-incoming-open",
          class="pg-btn pg-btn-primary",
          on_click=emit(OpenIncoming),
          "Open",
        ),
        @html.button(
          id="pg-incoming-keep",
          class="pg-btn",
          on_click=emit(KeepMine),
          "Keep my changes",
        ),
      ]
    None => []
  }
  @html.div(class="pg-sharebox", [
    @html.div(
      id="pg-share-status",
      class="pg-sharestatus",
      attrs=@html.Attrs::build().role("status"),
      content,
    ),
    @html.div(
      id="pg-incoming",
      class="pg-sharestatus",
      attrs=@html.Attrs::build().role("alert"),
      ask,
    ),
  ])
}

///|
/// The seconds that a request has run, for the status bar: nothing in the
/// first second, then the seconds, and from 5 seconds on also the limit, so a
/// long request shows that it works and when the playground stops it.
fn elapsed_text(seconds : Int32) -> String {
  let limit = timeout_ms / 1000
  if seconds <= 0 {
    ""
  } else if seconds < 5 {
    " · \{seconds} s"
  } else {
    " · \{seconds} s of \{limit} s"
  }
}

///|
/// What the Worker does for a request of this kind, for the status bar.
fn busy_label(kind : Kind) -> String {
  match kind {
    Validating => "checking"
    Transforming => "running the transform"
    Transcribing => "checking the transcript"
  }
}

///|
/// A turning ring that shows that the Worker works. It has no text, so the
/// text of the status bar stays the same, and it takes no input.
fn spinner() -> Html {
  @html.span(
    class="pg-spinner",
    attrs=@html.Attrs::build().aria_hidden("true"),
    ([] : Array[Html]),
  )
}

///|
/// The request that runs in the Worker, when it is not a check: a spinner,
/// what the Worker does and the seconds. A check shows in `check_status`.
fn busy_status(m : Model) -> Array[Html] {
  guard m.waiting && m.inflight != Validating else { return [] }
  [
    @html.span(class="pg-busy", [
      spinner(),
      @html.text(busy_label(m.inflight) + elapsed_text(m.elapsed)),
    ]),
  ]
}

///|
fn check_status(m : Model) -> Html {
  let checking = if m.checking() {
    // The Worker checks now: the spinner and the seconds show that it works.
    // Otherwise the check waits for the end of a change or of a request.
    let running = m.waiting && m.inflight == Validating
    if running {
      [
        @html.span(class="pg-hint", " · "),
        spinner(),
        @html.span(class="pg-hint", "checking"),
        @html.span(class="pg-hint pg-elapsed", elapsed_text(m.elapsed)),
      ]
    } else {
      [@html.span(class="pg-hint", " · checking")]
    }
  } else {
    []
  }
  let main = match m.check {
    _ if m.mismatch => @html.span(class="pg-err", "Failed")
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
        ..busy_status(m),
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
/// A message with the names between backticks shown as code.
fn message_html(message : String) -> Array[Html] {
  message_parts(message).map(part => {
    match part {
      Text(text) => @html.text(text)
      Name(name) => @html.code(class="pg-ref", name)
    }
  })
}

///|
/// The other messages of a group, which the reader can open. They name other
/// shapes for the same place, so the list shows the messages only.
fn repeats_html(group : DiagnosticGroup) -> Array[Html] {
  guard !group.repeats.is_empty() else { return [] }
  let shown = group.repeats[:if group.repeats.length() > MAX_LISTED {
      MAX_LISTED
    } else {
      group.repeats.length()
    }]
  let rest = group.repeats.length() - shown.length()
  let tail = if rest > 0 {
    [@html.li(class="pg-hint", plural(rest, "more message", "more messages"))]
  } else {
    []
  }
  [
    @html.details(class="pg-repeats", [
      @html.summary(
        plural(
          group.repeats.length(),
          "more message for this place",
          "more messages for this place",
        ),
      ),
      @html.ul(
        class="pg-repeat-list",
        [
          ..shown.iter().map(d => @html.li(message_html(d.message))).to_array(),
          ..tail,
        ],
      ),
    ]),
  ]
}

///|
/// A row of the Validate list: a diagnostic and its repeats. Its text can be
/// selected and copied. In a row of the current result, a click on the message
/// or the place moves the cursor to the place, unless the click ends a text
/// selection; the Go button does the same from the keyboard. A click on the
/// repeats only opens or closes them. A row of a result for older text names a
/// place in that text, so it does not move the cursor.
fn diagnostic_row(
  group : DiagnosticGroup,
  current : Bool,
  emit : @rabbita.Emit[Msg],
) -> Html {
  let d = group.first
  let severity = d.severity.to_lower()
  let shape = match d.shape {
    Some(id) => [@html.text(" · "), @html.span(class="pg-shape", id)]
    None => []
  }
  let count = if group.repeats.is_empty() {
    []
  } else {
    [
      @html.span(
        class="pg-repeat",
        title=plural(group.size(), "diagnostic", "diagnostics") +
          " at this place",
        "×\{group.size()}",
      ),
    ]
  }
  let go = current && d.start_line > 0
  let chosen = DiagnosticChosen(line=d.start_line, column=d.start_column)
  let main = [
    @html.div(class="pg-msg", message_html(d.message)),
    @html.div(
      class="pg-loc",
      [
        @html.text(location(d) + " · "),
        @html.span(class="pg-code", d.code),
        ..shape,
      ],
    ),
  ]
  let main = if go {
    @html.div(
      class="pg-diag-main",
      title="Go to line \{d.start_line}",
      on_click=emit(chosen),
      main,
    )
  } else {
    @html.div(class="pg-diag-main", main)
  }
  let body = [
    @html.div(
      class="pg-sevcol",
      [@html.span(class="pg-sev pg-sev-" + severity, d.severity), ..count],
    ),
    @html.div(class="pg-diag-text", [main, ..repeats_html(group)]),
    ..if go {
      [
        @html.button(
          class="pg-go",
          on_click=emit(chosen),
          attrs=@html.Attrs::build().aria_label("Go to line \{d.start_line}"),
          "Go",
        ),
      ]
    } else {
      []
    },
  ]
  if !current {
    @html.div(class="pg-diag pg-diag-stale", body)
  } else if go {
    @html.div(class="pg-diag pg-diag-go", body)
  } else {
    @html.div(class="pg-diag", body)
  }
}

///|
/// The bar above the list: the count of diagnostics and of rows, and the
/// "Group repeats" button.
fn list_bar(
  m : Model,
  items : Array[Diagnostic],
  groups : Array[DiagnosticGroup],
  emit : @rabbita.Emit[Msg],
) -> Html {
  let count = plural(items.length(), "diagnostic", "diagnostics") +
    (if groups.length() < items.length() {
      " in " + plural(groups.length(), "row", "rows")
    } else {
      ""
    })
  @html.div(class="pg-listbar", [
    @html.span(class="pg-hint", count),
    @html.span(class="pg-spacer", ([] : Array[Html])),
    @html.button(
      id="pg-group",
      class="pg-btn pg-toggle",
      title="Show the diagnostics with the same code at the same place in one row",
      on_click=emit(GroupToggled),
      attrs=@html.Attrs::build().aria_pressed(
        if m.grouped {
          "true"
        } else {
          "false"
        },
      ),
      "Group repeats",
    ),
  ])
}

///|
fn validate_panel(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  match m.check {
    Unchecked if m.mismatch => []
    Unchecked => [@html.p(class="pg-empty", "The playground checks the model.")]
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
      let groups = group_diagnostics(items, m.grouped)
      let listed = groups[:if groups.length() > MAX_LISTED {
          MAX_LISTED
        } else {
          groups.length()
        }]
      let current = m.is_current()
      let rows = listed
        .iter()
        .map(group => diagnostic_row(group, current, emit))
        .to_array()
      let unlisted = items.length() -
        listed.iter().fold(init=0, (sum, group) => sum + group.size())
      let more = if unlisted > 0 {
        [
          @html.p(
            class="pg-empty",
            plural(unlisted, "more diagnostic is", "more diagnostics are") +
            " not in the list. The editor marks all of them.",
          ),
        ]
      } else {
        []
      }
      let bar = if items.is_empty() {
        []
      } else {
        [list_bar(m, items, groups, emit)]
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
      [..head, ..bar, ..rows, ..more, ..hint]
    }
  }
}

///|
pub fn output_label(output : Output) -> String {
  match output {
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
/// The build command with a plugin and its settings. The settings name the
/// service that the run used, so that the same build gives the same file.
fn plugin_hint(
  plugin : String,
  service : String?,
  extra~ : Array[String] = [],
) -> String {
  let settings = match service {
    Some(id) => ["\"service\": \"\{id}\"", ..extra]
    None => extra
  }
  "smithy build --config smithy-build.json, with the plugin \"\{plugin}\": {" +
  settings.join(", ") +
  "}"
}

///|
/// The CLI command that gives the same output. JSON Schema, OpenAPI and
/// OpenRPC are plugins of `smithy build`, so the hint names the plugin and
/// its settings, with the `service` that the run used. An IDL output with several files needs `--output-dir`.
pub fn cli_hint(
  output : Output,
  selector : String,
  files : Int32,
  service : String?,
) -> String {
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
      plugin_hint("openapi", service, extra=["\"version\": \"3.0.2\""])
    OpenApi31 =>
      plugin_hint("openapi", service, extra=["\"version\": \"3.1.0\""])
    OpenRpc => plugin_hint("openrpc", service)
  }
}

///|
/// The Run button of the Transform tab. The controls have one, and the tab row
/// has another while the controls are folded, so each has its own `id`.
fn run_button(m : Model, emit : @rabbita.Emit[Msg], id : String) -> Html {
  @html.button(
    id~,
    class="pg-btn pg-btn-primary",
    disabled=m.tx == TxRunning,
    on_click=emit(RunClicked),
    if m.tx == TxRunning {
      "Running"
    } else {
      "Run"
    },
  )
}

///|
fn transform_controls(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let options = outputs.map(output => {
    @html.option(
      value=output.key(),
      selected=output == m.output,
      output_label(output),
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
    run_button(m, emit, "pg-run"),
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
      [
        @html.p(class="pg-empty", [
          spinner(),
          @html.text("The playground runs the transform"),
          @html.span(
            class="pg-elapsed",
            if m.waiting && m.inflight == Transforming {
              elapsed_text(m.elapsed)
            } else {
              ""
            },
          ),
        ]),
      ]
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
  // The hint and the note describe the shown output: the run, not the picker.
  let (output, selector, service, files) = match m.tx {
    TxDone(output~, selector~, service~, files~, ..) =>
      (output, selector, service, files.length())
    _ => (m.output, m.selector, None, 0)
  }
  let has_output = match m.tx {
    TxDone(files~, ..) => !files.is_empty()
    _ => false
  }
  let protocol_note = if output == OpenApi30 || output == OpenApi31 {
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
      "CLI: " + cli_hint(output, selector, files, service),
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
/// The fold button of a tab with a code view, and the buttons that stay in
/// the tab row while its controls are folded: Run, or Step and Run all.
fn tab_actions(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  guard m.tab != ValidateTab else { return [] }
  let folded = m.folded_on(m.tab)
  let actions = if !folded {
    []
  } else if m.tab == TransformTab {
    [run_button(m, emit, "pg-run-folded")]
  } else {
    step_buttons(m, emit, "-folded")
  }
  [
    ..actions,
    @html.button(
      id="pg-fold",
      class="pg-fold",
      title=if folded {
        "Show the controls of this tab"
      } else {
        "Fold the controls away, so the code views line up"
      },
      on_click=emit(FoldToggled(m.tab)),
      attrs=@html.Attrs::build().aria_expanded(
        if folded {
          "false"
        } else {
          "true"
        },
      ),
      if folded {
        "▾ Controls"
      } else {
        "▴ Controls"
      },
    ),
  ]
}

///|
/// The summary of the shown tab, in the status bar under the results. It
/// mirrors the status bar of the model editor.
fn results_status_text(m : Model) -> String {
  match m.tab {
    ValidateTab =>
      match m.check {
        Checked(items~, ..) if m.is_current() =>
          plural(items.length(), "diagnostic", "diagnostics")
        Checked(..) => "Checking"
        _ => "Not checked"
      }
    TransformTab =>
      match m.tx {
        TxDone(output~, files~, file~, warnings~, edits~, ..) => {
          let name = match files.get(file) {
            Some(name) => " · " + name
            None => ""
          }
          let place = if files.length() > 1 {
            " · file \{file + 1} of \{files.length()}"
          } else {
            ""
          }
          let warned = if warnings.is_empty() {
            ""
          } else {
            " · " + plural(warnings.length(), "warning", "warnings")
          }
          let old = if edits != m.edits {
            " · older than the model"
          } else {
            ""
          }
          output_label(output) + name + place + warned + old
        }
        TxRunning => "Running"
        TxIdle => "No output yet"
        _ => "No output"
      }
    TranscriptTab =>
      match m.tr {
        TrChecked(log) =>
          plural(log.checked, "entry checked", "entries checked") +
          " · " +
          plural(log.findings.length(), "finding", "findings") +
          (if log.done { "" } else { " so far" })
        _ => "Not checked"
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
  // A folded tab hides its controls with CSS: the editors keep their elements.
  // With no output, the Transform tab keeps its notices, so it is not empty.
  let fold = fn(tab : @samples.Tab) {
    if !m.folded_on(tab) {
      ""
    } else if tab == TransformTab &&
      !(m.tx is TxDone(files~, ..) && !files.is_empty()) {
      " pg-folded pg-folded-empty"
    } else {
      " pg-folded"
    }
  }
  @html.section(class="pg-pane pg-results", [
    @html.div(
      class="pg-tabs",
      [
        @html.div(
          class="pg-tablist",
          attrs=@html.Attrs::build().role("tablist"),
          [
            tab_button(m, emit, ValidateTab, "Validate", count),
            tab_button(m, emit, TransformTab, "Transform", []),
            tab_button(m, emit, TranscriptTab, "Transcript", []),
          ],
        ),
        @html.span(class="pg-spacer", ([] : Array[Html])),
        ..tab_actions(m, emit),
      ],
    ),
    panel(m.tab == ValidateTab, "pg-validate", validate_panel(m, emit)),
    panel(
      m.tab == TransformTab,
      "pg-transform" + fold(TransformTab),
      transform_panel(m, emit),
    ),
    panel(
      m.tab == TranscriptTab,
      "pg-trpanel" + fold(TranscriptTab),
      transcript_panel(m, emit),
    ),
    @html.div(class="pg-rstatus", [
      @html.span(class="pg-hint", results_status_text(m)),
    ]),
  ])
}

///|
/// The text when the Worker script is of another build than the page.
pub const MISMATCH_TEXT : String = "The page and its checker do not match. Reload the page."

///|
/// The message when the Worker script is of another build than the page. The
/// element is always there, so a screen reader reads the change.
fn mismatch_notice(m : Model) -> Html {
  @html.div(
    id="pg-mismatch",
    class="pg-sharestatus",
    attrs=@html.Attrs::build().role("alert"),
    if m.mismatch {
      [@html.span(class="pg-err", MISMATCH_TEXT)]
    } else {
      []
    },
  )
}

///|
/// The workbench: the toolbar, the model editor and the result tabs. The
/// pre-render shows it with no result; the playground script then mounts it
/// again in the element with id `APP_ID` and starts the editor.
pub fn view(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  @html.div(class="pg", [
    toolbar(m, emit),
    share_status(m, emit),
    mismatch_notice(m),
    @html.div(class="pg-bench", [
      model_pane(m),
      @html.div(class="pg-splitter", ([] : Array[Html])),
      results_pane(m, emit),
    ]),
  ])
}

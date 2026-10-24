///|
/// The id of the element that the transcript editor mounts in.
pub const TRANSCRIPT_ID : String = "pg-transcript"

///|
/// The path of the model that has the JSON-RPC protocols of the transcripts.
const PROTOCOL_SAMPLE : String = "examples/json-rpc/peers.smithy"

///|
/// The most characters of a message that an entry row shows.
const MESSAGE_CHARS : Int32 = 400

///|
/// The most findings with no entry that the list shows.
const TEXT_FINDINGS : Int32 = 50

///|
pub fn format_label(format : @samples.TranscriptFormat) -> String {
  match format {
    Markdown => "Markdown"
    Json => "JSON"
    Jsonl => "JSONL log"
  }
}

///|
let formats : Array[@samples.TranscriptFormat] = [Markdown, Json, Jsonl]

///|
fn format_key(format : @samples.TranscriptFormat) -> String {
  match format {
    Markdown => "markdown"
    Json => "json"
    Jsonl => "jsonl"
  }
}

///|
fn format_of_key(key : String) -> @samples.TranscriptFormat? {
  formats.iter().find_first(format => format_key(format) == key)
}

///|
fn Model::protocol(self : Model) -> Protocol? {
  self.protocols.iter().find_first(p => p.id == self.settings.protocol)
}

///|
/// A button that opens the model with the JSON-RPC protocols, if the picker
/// has it.
fn example_button(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  match m.data.samples.search_by(sample => sample.path == PROTOCOL_SAMPLE) {
    Some(index) =>
      [
        @html.button(
          id="pg-open-protocols",
          class="pg-btn",
          on_click=emit(SampleChosen(index)),
          "Open the JSON-RPC chat protocol example",
        ),
      ]
    None => []
  }
}

///|
/// The Step and Run all buttons of the Transcript tab. The controls have them,
/// and the tab row has them too while the controls are folded; `suffix` keeps
/// their `id`s apart.
fn step_buttons(
  m : Model,
  emit : @rabbita.Emit[Msg],
  suffix : String,
) -> Array[Html] {
  let running = m.tr_running()
  let ready = !m.protocols.is_empty()
  let done = m.tr_current() && m.tr is TrChecked({ done: true, .. })
  [
    @html.button(
      id="pg-step" + suffix,
      class="pg-btn",
      disabled=!ready || running || done,
      on_click=emit(StepClicked),
      "▶ Step",
    ),
    @html.button(
      id="pg-runall" + suffix,
      class="pg-btn pg-btn-primary",
      disabled=!ready || running || done,
      on_click=emit(RunAllClicked),
      if running {
        "Running"
      } else {
        "⏭ Run all"
      },
    ),
  ]
}

///|
fn transcript_controls(m : Model, emit : @rabbita.Emit[Msg]) -> Html {
  let samples = m.data.transcripts.mapi((i, sample) => {
    @html.option(value=i.to_string(), selected=i == m.transcript, sample.title)
  })
  let protocols = if m.protocols.is_empty() {
    [@html.option(value="", selected=true, "No protocol")]
  } else {
    m.protocols.map(p => {
      @html.option(value=p.id, selected=p.id == m.settings.protocol, p.id)
    })
  }
  let format_options = formats.map(format => {
    @html.option(
      value=format_key(format),
      selected=format == m.settings.format,
      format_label(format),
    )
  })
  let running = m.tr_running()
  let ready = !m.protocols.is_empty()
  @html.div(
    class="pg-rowctl",
    [
      @html.label(class="pg-hint", for_="pg-transcript-sample", "Transcript"),
      @html.select(
        id="pg-transcript-sample",
        class="pg-select",
        on_change=emit.map(value => {
          TranscriptSampleChosen(@string.parse_int(value) catch { _ => -1 })
        }),
        samples,
      ),
      @html.label(class="pg-hint", for_="pg-protocol", "Protocol"),
      @html.select(
        id="pg-protocol",
        class="pg-select",
        disabled=!ready,
        on_change=emit.map(value => ProtocolChosen(value)),
        protocols,
      ),
      @html.select(
        id="pg-format",
        class="pg-select",
        attrs=@html.Attrs::build().aria_label("Format"),
        on_change=emit.map(key => {
          FormatChosen(format_of_key(key).unwrap_or(m.settings.format))
        }),
        format_options,
      ),
      @html.label(
        class="pg-hint pg-checkbox",
        title="Check the transcript as complete, as --complete does: a call without a reply is an error. When clear, the document decides.",
        [
          @html.input(
            id="pg-complete",
            input_type=Checkbox,
            checked=m.settings.complete,
            on_change=emit.map(_ => CompleteChosen(!m.settings.complete)),
          ),
          @html.text(" complete"),
        ],
      ),
      @html.span(class="pg-spacer", ([] : Array[Html])),
      ..step_buttons(m, emit, ""),
      @html.button(
        id="pg-reset",
        class="pg-btn",
        title="Reset",
        attrs=@html.Attrs::build().aria_label("Reset"),
        disabled=m.tr == TrIdle && !running,
        on_click=emit(ResetClicked),
        "↺",
      ),
    ],
  )
}

///|
/// The version and the preset of a JSONL log.
fn log_controls(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  guard m.settings.format == Jsonl else { return [] }
  let protocol = m.protocol()
  let versions = protocol.map(p => p.versions).unwrap_or([])
  let peers = protocol.map(p => p.peers).unwrap_or([])
  let version_options = versions.map(version => {
    @html.option(value=version, selected=version == m.settings.version, version)
  })
  let kind = match m.settings.preset {
    DirMessage(_) => DirMessageLog
    Raw(_) => RawLog
  }
  let preset_options = [
    @html.option(
      value="dir-message",
      selected=kind == DirMessageLog,
      "dir-message",
    ),
    @html.option(value="raw", selected=kind == RawLog, "raw"),
  ]
  let detail = match m.settings.preset {
    DirMessage(directions) =>
      peers.map(peer => {
        let value = match directions.iter().find_first(d => d.peer == peer) {
          Some(d) => d.value
          None => ""
        }
        @html.label(class="pg-hint pg-dir", [
          @html.text("dir for " + peer + " "),
          @html.input(
            id="pg-dir-" + peer,
            class="pg-input pg-input-short",
            value~,
            on_input=emit.map(text => DirectionEdited(peer~, value=text)),
          ),
        ])
      })
    Raw(sender~) =>
      [
        @html.label(class="pg-hint", for_="pg-sender", "Sender"),
        @html.select(
          id="pg-sender",
          class="pg-select",
          on_change=emit.map(value => SenderChosen(value)),
          peers.map(peer => {
            @html.option(value=peer, selected=peer == sender, peer)
          }),
        ),
      ]
  }
  [
    @html.div(
      class="pg-rowctl pg-logctl",
      [
        @html.label(class="pg-hint", for_="pg-version", "Version"),
        @html.select(
          id="pg-version",
          class="pg-select",
          on_change=emit.map(value => VersionChosen(value)),
          version_options,
        ),
        @html.label(class="pg-hint", for_="pg-preset", "Log preset"),
        @html.select(
          id="pg-preset",
          class="pg-select",
          on_change=emit.map(value => {
            PresetChosen(if value == "raw" { RawLog } else { DirMessageLog })
          }),
          preset_options,
        ),
        ..detail,
      ],
    ),
  ]
}

///|
fn transcript_notice(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  if m.protocols.is_empty() {
    return match m.check {
      Unchecked =>
        [@html.p(class="pg-empty", "The playground checks the model.")]
      _ if m.errors() > 0 =>
        [
          @html.div(class="pg-trnotice", [
            @html.p(
              "The model has errors, so the playground cannot find its JSON-RPC protocols. Fix them in the Validate tab first.",
            ),
          ]),
          @html.div(class="pg-rowctl", example_button(m, emit)),
        ]
      _ =>
        [
          @html.p(
            class="pg-empty",
            "The model has no structure with the @jsonRpcProtocol trait. A transcript check needs one.",
          ),
          @html.div(class="pg-rowctl", example_button(m, emit)),
        ]
    }
  }
  match m.tr {
    TrIdle =>
      [
        @html.p(
          class="pg-empty",
          "Select Step to check one entry, or Run all to check all entries. The playground checks the transcript in your browser.",
        ),
      ]
    TrBlocked(reason~, by~) =>
      [
        @html.p(
          class="pg-trnotice",
          match by {
            ModelErrors =>
              "The model has errors. Fix them in the Validate tab first."
            Other => reason
          },
        ),
      ]
    TrStopped =>
      [
        @html.p(
          class="pg-trnotice",
          "The check took more than 10 seconds, so the playground stopped it and started a new Worker. Select Step or Run all to start again.",
        ),
      ]
    TrFailed(message) => {
      let detail = if message == "" {
        []
      } else {
        [@html.code(class="pg-detail", message)]
      }
      [
        @html.div(
          class="pg-trnotice",
          [
            @html.p(
              "The check failed because the Worker stopped with an error. The playground started a new Worker. Select Step or Run all to start again.",
            ),
            ..detail,
          ],
        ),
      ]
    }
    TrChecked(log) =>
      if m.session is None && !log.done && !m.tr_running() {
        [
          @html.p(
            class="pg-trstale",
            "The playground started a new Worker, so the check stopped. Select Step or Run all to start it again.",
          ),
        ]
      } else if !m.tr_current() && !m.tr_running() {
        [
          @html.p(
            class="pg-trstale",
            "The model, the transcript or a setting changed after the check started. Select Step or Run all to check again.",
          ),
        ]
      } else {
        []
      }
  }
}

///|
/// The text of a message, cut to `MESSAGE_CHARS` characters.
fn short_message(message : String) -> String {
  if message.length() <= MESSAGE_CHARS {
    return message
  }
  let out = StringBuilder()
  let mut n = 0
  for c in message {
    if n >= MESSAGE_CHARS {
      break
    }
    out.write_char(c)
    n += 1
  }
  out.to_string() + " …"
}

///|
fn related_text(related : Array[Int32]) -> String? {
  match related {
    [] => None
    [one] => Some("related to entry \{one}")
    many =>
      Some("related to entries " + many.map(n => n.to_string()).join(", "))
  }
}

///|
/// A finding: the code and the message as the library writes them, then the
/// place: the line for a finding with no entry, the JSON pointer, the shape
/// and the related entries.
fn finding_view(f : Finding, with_line : Bool) -> Html {
  let place = []
  if with_line && f.line is Some(line) {
    place.push("line \{line}:\{f.column.unwrap_or(1)}")
  }
  if f.path is Some(path) {
    place.push(path)
  }
  if f.shape is Some(shape) {
    place.push(shape)
  }
  if related_text(f.related) is Some(text) {
    place.push(text)
  }
  let at = if place.is_empty() {
    []
  } else {
    [@html.div(class="pg-find-at", place.join(" · "))]
  }
  @html.div(
    class=if f.severity == "error" { "pg-find" } else { "pg-find pg-find-adv" },
    [
      @html.code(class="pg-find-code", f.code),
      @html.text(" " + f.message),
      ..at,
    ],
  )
}

///|
fn entry_row(
  e : Entry,
  checked : Bool,
  findings : Array[Finding],
  current : Bool,
  emit : @rabbita.Emit[Msg],
) -> Html {
  let to = match e.receiver {
    Some(peer) => @html.b(peer)
    None => @html.text("reply")
  }
  let line = match e.line {
    Some(n) if current =>
      [
        @html.text(" · "),
        @html.button(
          class="pg-linkbtn",
          title="Go to line \{n} of the transcript",
          on_click=emit(EntryChosen(line=n, column=e.column.unwrap_or(1))),
          "line \{n}",
        ),
      ]
    Some(n) => [@html.text(" · line \{n}")]
    None => []
  }
  let mark = if checked && findings.is_empty() {
    [@html.span(class="pg-okmark", "✓")]
  } else {
    []
  }
  @html.div(
    class=if checked { "pg-entry" } else { "pg-entry pg-entry-pending" },
    attrs=@html.Attrs::build().data_set("entry", e.index.to_string()),
    [
      @html.div(class="pg-entry-n", "#\{e.index}"),
      @html.div(
        class="pg-entry-body",
        [
          @html.div(
            class="pg-entry-dir",
            [@html.b(e.sender), @html.text(" → "), to, ..line, ..mark],
          ),
          @html.div(class="pg-entry-msg", short_message(e.message)),
          ..if checked {
            findings.map(f => finding_view(f, false))
          } else {
            []
          },
        ],
      ),
    ],
  )
}

///|
fn entry_list(m : Model, log : Log, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  let by_entry : Map[Int32, Array[Finding]] = Map([])
  let loose = []
  for f in log.findings {
    match f.entry {
      Some(i) if i >= 0 && i < log.entries.length() =>
        match by_entry.get(i) {
          Some(list) => list.push(f)
          None => by_entry[i] = [f]
        }
      _ => loose.push(f)
    }
  }
  let marked = by_entry.keys().collect()
  marked.sort()
  let total = log.entries.length()
  let current = m.tr_current()
  let rows = visible_rows(total, log.checked, marked).map(row => {
    match row {
      Shown(i) =>
        entry_row(
          log.entries[i],
          i < log.checked,
          by_entry.get(i).unwrap_or([]),
          current,
          emit,
        )
      Hidden(count) =>
        @html.div(
          class="pg-entry-gap",
          plural(count, "entry is", "entries are") + " not in the list.",
        )
    }
  })
  let note = if total > MAX_ENTRY_ROWS {
    [
      @html.p(
        class="pg-hint pg-trnote",
        "The transcript has \{total} entries. The list shows the entries near the last checked entry and the first \{MARKED_ROWS} entries with findings. The summary counts all entries.",
      ),
    ]
  } else {
    []
  }
  let text = if loose.is_empty() {
    []
  } else {
    let more = if loose.length() > TEXT_FINDINGS {
      [
        @html.p(
          class="pg-hint",
          plural(
            loose.length() - TEXT_FINDINGS,
            "more finding is",
            "more findings are",
          ) +
          " not in the list.",
        ),
      ]
    } else {
      []
    }
    [
      @html.div(
        class="pg-textfinds",
        [
          @html.b("Findings with no entry"),
          ..loose[:if loose.length() > TEXT_FINDINGS {
            TEXT_FINDINGS
          } else {
            loose.length()
          }]
          .iter()
          .map(f => finding_view(f, true))
          .to_array(),
          ..more,
        ],
      ),
    ]
  }
  [..text, ..note, ..rows]
}

///|
fn stat(value : String, label : String) -> Html {
  @html.div(class="pg-stat", [@html.b(value), @html.span(label)])
}

///|
fn expected_text(e : Expected) -> String {
  let entry = e.entry.map(n => " at entry \{n}").unwrap_or("")
  let related = e.related.map(n => " related to entry \{n}").unwrap_or("")
  "I expected \{e.code}\{entry}\{related}; no finding matches it."
}

///|
/// The counts of the check: entries checked, error findings and calls without
/// a reply. At the end, the verdict, the counts of a log and the match of the
/// `expect` list, with the lines of the CLI for each mismatch.
fn transcript_summary(m : Model, log : Log) -> Array[Html] {
  let errors = match log.summary {
    Some(summary) => summary.errors
    None => log.findings.filter(f => f.severity == "error").length()
  }
  let outstanding = match log.summary {
    Some(summary) => summary.outstanding.to_string()
    None => "–"
  }
  let stats = [
    stat(log.checked.to_string(), "entries checked"),
    stat(errors.to_string(), "error findings"),
    stat(outstanding, "calls without a reply"),
  ]
  guard log.summary is Some(summary) else {
    return [@html.div(class="pg-summary", stats)]
  }
  let expect = match summary.expectations {
    Some(e) => {
      stats.push(
        stat(if e.matched { "yes" } else { "no" }, "expect list matched"),
      )
      stats.push(stat(e.missing.length().to_string(), "missing"))
      stats.push(stat(e.unexpected.length().to_string(), "unexpected"))
      let lines = e.missing.map(expected => {
        @html.div(class="pg-trwarning", expected_text(expected))
      })
      for f in e.unexpected {
        let at = f.entry.map(n => "entry \{n}: ").unwrap_or("")
        lines.push(
          @html.div(
            class="pg-trwarning",
            "\{at}I did not expect error \{f.code}.",
          ),
        )
      }
      if lines.is_empty() {
        []
      } else {
        [@html.div(class="pg-trwarnings", lines)]
      }
    }
    None => []
  }
  let verdict = if summary.valid {
    @html.span(class="pg-ok", "✓ valid")
  } else {
    @html.span(class="pg-err", "● not valid")
  }
  let counts = if m.session.map(s => s.settings.format) == Some(Jsonl) ||
    summary.lines > 0 {
    [
      @html.text(
        " · \{summary.lines} lines · \{summary.not_json} not JSON · \{summary.skipped} skipped",
      ),
    ]
  } else {
    []
  }
  [
    @html.p(
      class="pg-hint pg-verdict",
      [
        verdict,
        @html.text(
          if summary.complete {
            " · complete"
          } else {
            " · partial"
          },
        ),
        ..counts,
      ],
    ),
    @html.div(class="pg-summary", stats),
    ..expect,
  ]
}

///|
fn transcript_panel(m : Model, emit : @rabbita.Emit[Msg]) -> Array[Html] {
  let (entries, summary) = match m.tr {
    TrChecked(log) => (entry_list(m, log, emit), transcript_summary(m, log))
    _ => ([], [])
  }
  let hint = if m.protocols.is_empty() {
    []
  } else {
    [@html.p(class="pg-hint pg-trcli", "CLI: " + transcript_hint(m.settings))]
  }
  // The transcript editor owns the children of its element. Every slot stays
  // at the same place in every render, so the editor keeps its element.
  [
    transcript_controls(m, emit),
    @html.div(class="pg-logslot", log_controls(m, emit)),
    @html.div(class="pg-hintslot", hint),
    @html.div(class="pg-trnotices", transcript_notice(m, emit)),
    @html.div(class="pg-txwrap", [
      @html.div(id=TRANSCRIPT_ID, class="pg-editor", ([] : Array[Html])),
    ]),
    @html.div(
      id="pg-entries",
      class="pg-entries",
      attrs=@html.Attrs::build().aria_label("Transcript entries"),
      entries,
    ),
    @html.div(class="pg-sumslot", summary),
  ]
}

///|
/// Send the first request of the files: the check of the model files, or, for
/// a diff lesson, the diff of both models (its answer has their findings).
fn Model::send_validate(self : Model) -> (Model, Array[Effect]) {
  let seq = self.seq + 1
  let (inflight, request) = if self.page.engine is Diff {
    let (old, new) = @model.sides(self.files)
    (Diffing, SendDiff(seq~, old=pairs(old), new=pairs(new)))
  } else {
    (Validating, SendValidate(seq~, files=model_pairs(self)))
  }
  (
    {
      ..self,
      seq,
      sent_edits: self.edits,
      waiting: true,
      inflight,
      pending: false,
    },
    [request, Wait(ms=TIMEOUT_MS, msg=TimedOut(seq))],
  )
}

///|
/// Send the transform of the lesson output. Call it only for a lesson with an
/// output.
fn Model::send_transform(self : Model) -> (Model, Array[Effect]) {
  guard self.page.output is Some(output) else { return (self, []) }
  let seq = self.seq + 1
  (
    {
      ..self,
      seq,
      sent_edits: self.edits,
      waiting: true,
      inflight: Transforming,
      pending: false,
    },
    [
      SendTransform(
        seq~,
        files=model_pairs(self),
        output~,
        selector=@model.query_of(self.files, fixed=self.page.selector),
      ),
      Wait(ms=TIMEOUT_MS, msg=TimedOut(seq)),
    ],
  )
}

///|
/// A check that did not run: a transcript lesson shows no old rows and
/// disables Step.
fn Model::stop_transcript(self : Model, reason : String) -> Model {
  if self.transcript_setup() is Some(_) {
    { ..self, transcript: None, not_run: Some(reason), }
  } else {
    self
  }
}

///|
/// The setup of a transcript lesson; `None` for every other lesson.
fn Model::transcript_setup(self : Model) -> @model.TranscriptSetup? {
  match self.page.engine {
    Transcript(setup) => Some(setup)
    _ => None
  }
}

///|
/// The name of the file of the transcript; "" for a lesson with none.
pub fn Model::transcript_file(self : Model) -> String {
  match self.transcript_setup() {
    Some(setup) => setup.file
    None => ""
  }
}

///|
/// Send the model files and the transcript to the Worker. The check starts
/// at the first entry; the answer decides about the steps up to the position
/// that the reader asked for. Call it only for a transcript lesson.
fn Model::send_transcript_start(self : Model) -> (Model, Array[Effect]) {
  guard self.transcript_setup() is Some(setup) else { return (self, []) }
  let text = match self.files.iter().find_first(f => f.name == setup.file) {
    Some(file) => file.text
    None => ""
  }
  let seq = self.seq + 1
  (
    {
      ..self,
      seq,
      sent_edits: self.edits,
      waiting: true,
      inflight: Transcribing,
      stepping: false,
      pending: false,
    },
    [
      SendTranscriptStart(
        seq~,
        files=model_pairs(self),
        protocol=setup.protocol,
        text~,
      ),
      Wait(ms=TIMEOUT_MS, msg=TimedOut(seq)),
    ],
  )
}

///|
/// Ask the Worker to check the next `count` entries.
fn Model::send_transcript_step(
  self : Model,
  count : Int32,
) -> (Model, Array[Effect]) {
  let seq = self.seq + 1
  (
    {
      ..self,
      seq,
      sent_edits: self.edits,
      waiting: true,
      inflight: Transcribing,
      stepping: true,
      pending: false,
    },
    [SendTranscriptStep(seq~, count~), Wait(ms=TIMEOUT_MS, msg=TimedOut(seq))],
  )
}

///|
/// The model after an edit: the lines on the Transcript tab, so that the next
/// check can highlight the lines that are new. A check that did not reach its
/// position yet keeps the lines that it has.
fn Model::remember_lines(self : Model) -> Model {
  match self.transcript {
    Some(t) if !(t.before is Some(_) && !t.reached()) =>
      {
        ..self,
        transcript: Some({
          ..t,
          before: Some(transcript_lines(t, self.transcript_file())),
        }),
      }
    _ => self
  }
}

///|
/// After the newest request ended: send the newest files when their wait
/// ended while it ran. One request runs at a time, so the time limit of a
/// request measures that request only.
fn Model::next(self : Model, effects : Array[Effect]) -> (Model, Array[Effect]) {
  let m = { ..self, waiting: false, retried: false, }
  if m.pending {
    let (sent, more) = m.send_validate()
    (sent, [..effects, ..more])
  } else {
    (m, effects)
  }
}

///|
/// Check the files now, or after the request that runs.
fn Model::check_now(self : Model) -> (Model, Array[Effect]) {
  if self.waiting {
    ({ ..self, pending: true, }, [])
  } else {
    self.send_validate()
  }
}

///|
/// Send the value or message check. Call it only for a value or message lesson.
fn Model::send_check(self : Model) -> (Model, Array[Effect]) {
  let text_of = (name : String) => {
    match self.files.search_by(f => f.name == name) {
      Some(i) => self.files[i].text
      None => ""
    }
  }
  let (inflight, request) = match self.page.engine {
    Value(setup) =>
      (
        CheckingValue,
        SendCheckValue(
          seq=self.seq + 1,
          files=model_pairs(self),
          shape=setup.shape,
          value=text_of(setup.file),
          options=setup.options,
        ),
      )
    Message(setup) =>
      (
        CheckingMessage,
        SendCheckMessage(
          seq=self.seq + 1,
          files=model_pairs(self),
          service=setup.service,
          version=setup.version,
          message=text_of(setup.file),
          kind=setup.message_kind(self.files),
          options=setup.options,
        ),
      )
    _ => return (self, [])
  }
  let seq = self.seq + 1
  (
    {
      ..self,
      seq,
      sent_edits: self.edits,
      waiting: true,
      inflight,
      pending: false,
    },
    [request, Wait(ms=TIMEOUT_MS, msg=TimedOut(seq))],
  )
}

///|
/// Show the lines of a value or message check, with the lines that changed
/// since the output on the page. `empty` is the text when there is no finding.
fn Model::data_checked(
  self : Model,
  findings : Array[@core.DataFinding],
  empty~ : String,
) -> (Model, Array[Effect]) {
  let text = data_text(findings, self.data_file(), empty~)
  let before = match self.output {
    Shown(text~, ..) => text
    _ => ""
  }
  let highlight = changed_lines(before, text)
  { ..self, output: Shown(text~, highlight~), }.next([
    ShowOutput(text~, highlight~),
  ])
}

///|
/// The name of the output tab.
fn output_name(output : @samples.Output) -> String {
  match output {
    JsonAst => "JSON AST"
    Idl => "IDL (flattened)"
    Selector => "Selector"
    JsonSchema => "JSON Schema"
    OpenApi30 => "OpenAPI 3.0"
    OpenApi31 => "OpenAPI 3.1"
    OpenRpc => "OpenRPC"
  }
}

///|
/// Why the output did not run: the model has errors. ERROR and DANGER stop
/// a transform in the playground core.
fn errors_text(errors : Int32, output : @samples.Output) -> String {
  let label = output_name(output)
  if errors == 1 {
    "The model has 1 error, so I did not make the \{label}. The Findings tab shows the error."
  } else {
    "The model has \{errors} errors, so I did not make the \{label}. The Findings tab shows the errors."
  }
}

///|
/// Whether the finding stops the output (`Severity::blocks_output`).
fn is_error(d : @core.Diagnostic) -> Bool {
  @model.Severity::parse(d.severity) is Some(severity) &&
  severity.blocks_output()
}

///|
/// The output pane after an output that did not run: the reason, and an
/// empty output editor with no highlight.
fn Model::not_shown(self : Model, reason : String) -> (Model, Array[Effect]) {
  ({ ..self, output: NotShown(reason), }, [ShowOutput(text="", highlight=[])])
}

///|
/// The name of the data file of a value or message lesson, "" for another
/// lesson.
fn Model::data_file(self : Model) -> String {
  match self.page.engine {
    Value(setup) => setup.file
    Message(setup) => setup.file
    _ => ""
  }
}

///|
/// The findings of the newest files arrived.
fn Model::checked(
  self : Model,
  items : Array[@core.Diagnostic],
) -> (Model, Array[Effect]) {
  // The tab opens on the output, except when the first model of the page
  // has findings that the lesson compares.
  let pane = if self.findings == Unchecked &&
    !self.chosen &&
    items.any(d => @model.Severity::parse(d.severity) is Some(_)) {
    FindingsPane
  } else {
    self.pane
  }
  let m = { ..self, findings: Found(items), pane, }
  let marked = [Mark(items=m.selected_findings())]
  if m.transcript_setup() is Some(_) {
    if items.filter(is_error).length() == 0 {
      let (sent, more) = { ..m, waiting: false, retried: false, not_run: None, }.send_transcript_start()
      return (sent, [..marked, ..more])
    }
    // The transcript check needs a model without errors. The pane says so.
    return { ..m, transcript: None, not_run: Some(not_run_text), }.next(marked)
  }
  if self.page.engine is (Value(_) | Message(_)) {
    return if items.filter(is_error).length() == 0 {
      let (sent, more) = { ..m, waiting: false, retried: false, }.send_check()
      (sent, [..marked, ..more])
    } else {
      // The value or message check needs a model without errors. The pane says so.
      let shown = { ..m, output: NotShown(not_run_text), }
      shown.next([..marked, ShowOutput(text=not_run_text, highlight=[])])
    }
  }
  match self.page.output {
    None => m.next(marked)
    Some(output) => {
      let errors = items.filter(is_error).length()
      if errors == 0 {
        let (sent, more) = { ..m, waiting: false, retried: false, }.send_transform()
        (sent, [..marked, ..more])
      } else {
        let (m, shown) = m.not_shown(errors_text(errors, output))
        m.next([..marked, ..shown])
      }
    }
  }
}

///|
/// The answer of a diff: the findings of both models and the diff lines.
fn Model::diffed(
  self : Model,
  old : Array[@core.Diagnostic],
  new : Array[@core.Diagnostic],
  events : Array[@core.DiffEvent]?,
) -> (Model, Array[Effect]) {
  let items = [..old, ..new]
  // The tab opens on the diff, except when the first models of the page have
  // findings that the lesson compares.
  let pane = if self.findings == Unchecked &&
    !self.chosen &&
    items.any(d => @model.Severity::parse(d.severity) is Some(_)) {
    FindingsPane
  } else {
    self.pane
  }
  let m = { ..self, findings: Found(items), pane, }
  let marked = Mark(items=m.selected_findings())
  match events {
    None => {
      let text = diff_not_run_text(old.any(is_error), new.any(is_error))
      { ..m, output: NotShown(text), }.next([
        marked,
        ShowOutput(text~, highlight=[]),
      ])
    }
    Some(events) => {
      let text = if events.is_empty() {
        no_difference_text
      } else {
        events.map(e => e.cli_line()).join("\n")
      }
      let before = match m.output {
        Shown(text~, ..) => text
        _ => ""
      }
      let highlight = changed_lines(before, text)
      { ..m, output: Shown(text~, highlight~), }.next([
        marked,
        ShowOutput(text~, highlight~),
      ])
    }
  }
}

///|
/// The state of the transcript check arrived. A start gives every entry and
/// replaces the rows; a step adds its findings. The check goes on to the
/// position that the reader asked for.
fn Model::progressed(
  self : Model,
  entries : Array[@core.EntryView],
  findings : Array[@core.FindingView],
  checked : Int32,
  done : Bool,
  summary : @core.SummaryView?,
) -> (Model, Array[Effect]) {
  let old = self.transcript
  let t : Transcript = match (self.stepping, old) {
    (true, Some(t)) =>
      { ..t, findings: [..t.findings, ..findings], checked, done, summary, }
    _ =>
      {
        entries,
        findings,
        checked,
        done,
        summary,
        wanted: old.map(t => t.wanted).unwrap_or(0),
        before: old.bind(t => t.before),
      }
  }
  let m = { ..self, transcript: Some(t), not_run: None, }
  if t.wanted > t.checked && !t.done {
    { ..m, waiting: false, retried: false, }.send_transcript_step(
      t.wanted - t.checked,
    )
  } else {
    m.next([])
  }
}

///|
pub fn update(m : Model, msg : Msg) -> (Model, Array[Effect]) {
  match msg {
    Edited(text) => {
      guard m.files.get(m.selected) is Some(file) && file.text != text else {
        return (m, [])
      }
      let files = m.files.copy()
      files[m.selected] = { ..file, text, }
      let edits = m.edits + 1
      let m = { ..m, files, edits, link_problem: None, }.remember_lines()
      let keep = if files == m.page.files {
        Clear(key=m.page.storage_key)
      } else {
        Store(key=m.page.storage_key, value=m.stored_value())
      }
      (m, [keep, Wait(ms=DEBOUNCE_MS, msg=Debounced(edits))])
    }
    Debounced(edits) => if edits != m.edits { (m, []) } else { m.check_now() }
    SelectFile(index) =>
      match m.files.get(index) {
        Some(_) if index != m.selected => {
          let m = { ..m, selected: index, }
          (m, [m.load_selected(fresh=false), Mark(items=m.selected_findings())])
        }
        _ => (m, [])
      }
    SelectPane(pane) =>
      if (pane == OutputPane && !has_output_pane(m.page)) ||
        (pane == TranscriptPane && m.transcript_setup() is None) {
        (m, [])
      } else {
        ({ ..m, pane, chosen: true, }, [])
      }
    Answered(seq~, answer~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      // The answer is for files that changed since: it does not show.
      if m.edits != m.sent_edits {
        return m.next([])
      }
      match (m.inflight, answer) {
        (Validating, Checked(items)) => m.checked(items)
        (Validating, NotConverted(reason)) => {
          let m = { ..m, findings: NotChecked(reason), }.stop_transcript(reason)
          if has_output_pane(m.page) {
            let (m, shown) = m.not_shown(reason)
            m.next([Mark(items=[]), ..shown])
          } else {
            m.next([Mark(items=[])])
          }
        }
        (Transforming, Converted(text)) => {
          // The lines that changed since the output on the page. After no
          // output, or an output that did not run, nothing is highlighted.
          let before = match m.output {
            Shown(text~, ..) => text
            _ => ""
          }
          let highlight = changed_lines(before, text)
          { ..m, output: Shown(text~, highlight~), }.next([
            ShowOutput(text~, highlight~),
          ])
        }
        // A value or message check is sent only after a validate of the same
        // files found no ERROR and no DANGER, and the guard above drops an
        // answer for older files. So the core does not block it for model
        // errors, and level 1 fails a lesson whose shape or service ID does not
        // parse. The one block that can come is a model that the core cannot
        // build with no error to show, and its own reason is the right text.
        (Transforming | CheckingValue | CheckingMessage, NotConverted(reason)) => {
          let (m, shown) = m.not_shown(reason)
          m.next(shown)
        }
        (Transcribing, Progress(entries~, findings~, checked~, done~, summary~)) =>
          m.progressed(entries, findings, checked, done, summary)
        // No rows of an older text stay.
        (Transcribing, NotConverted(reason)) =>
          { ..m, transcript: None, not_run: Some(reason), }.next([])
        (Diffing, Diffed(old~, new~, events~)) => m.diffed(old, new, events)
        (Diffing, NotConverted(reason)) => {
          // Both the findings and the diff come from this request.
          let (m, shown) = { ..m, findings: NotChecked(reason), }.not_shown(
            reason,
          )
          m.next([Mark(items=[]), ..shown])
        }
        (CheckingValue, DataChecked(valid=_, findings~)) =>
          m.data_checked(findings, empty=valid_text)
        (CheckingMessage, DataChecked(valid=_, findings~)) =>
          m.data_checked(findings, empty=message_valid_text)
        // An answer of the other kind cannot come; the request ends.
        _ => m.next([])
      }
    }
    TimedOut(seq) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      if m.pending || m.edits != m.sent_edits {
        // The files changed since: check the newest ones. A transform of the
        // edited files would show an output for files whose findings the
        // page does not show.
        let (sent, more) = m.send_validate()
        ({ ..sent, retried: false, }, [RestartWorker, ..more])
      } else if m.retried {
        // The second try also took too long: a model that is too slow would
        // restart the Worker again and again.
        // A transform that stops keeps the findings of its files.
        match (m.inflight, has_output_pane(m.page)) {
          (Transcribing, _) =>
            { ..m, transcript: None, not_run: Some(timeout_text), }.next([
              RestartWorker,
            ])
          (Transforming | CheckingValue | CheckingMessage, _) => {
            let (m, shown) = m.not_shown(timeout_text)
            m.next([RestartWorker, ..shown])
          }
          (Diffing, _) => {
            let (m, shown) = { ..m, findings: NotChecked(timeout_text), }.not_shown(
              timeout_text,
            )
            m.next([RestartWorker, Mark(items=[]), ..shown])
          }
          (Validating, false) =>
            { ..m, findings: NotChecked(timeout_text), }
            .stop_transcript(timeout_text)
            .next([RestartWorker, Mark(items=[])])
          (Validating, true) => {
            let (m, shown) = { ..m, findings: NotChecked(timeout_text), }
              .stop_transcript(timeout_text)
              .not_shown(timeout_text)
            m.next([RestartWorker, Mark(items=[]), ..shown])
          }
        }
      } else {
        let (sent, more) = match m.inflight {
          Validating | Diffing => m.send_validate()
          Transforming => m.send_transform()
          // The new Worker holds no transcript: start it again. The answer
          // steps to the position of the reader.
          Transcribing => m.send_transcript_start()
          CheckingValue | CheckingMessage => m.send_check()
        }
        ({ ..sent, retried: true, }, [RestartWorker, ..more])
      }
    }
    StepClicked =>
      match m.transcript {
        Some(t) if !m.busy() && !t.done => {
          let t = { ..t, wanted: t.checked + 1, before: None, }
          { ..m, transcript: Some(t), }.send_transcript_step(1)
        }
        _ => (m, [])
      }
    RunAllClicked =>
      match m.transcript {
        Some(t) if !m.busy() && !t.done => {
          let wanted = t.entries.length().max(t.checked)
          let t = { ..t, wanted, before: None, }
          { ..m, transcript: Some(t), }.send_transcript_step(wanted - t.checked)
        }
        _ => (m, [])
      }
    ToggleExpand(side) =>
      ({ ..m, layout: m.layout.toggled(side), }, [Remeasure])
    Reset => {
      let m = {
        ..m,
        files: m.page.files,
        edits: m.edits + 1,
        link_problem: None,
      }
      let m = m.remember_lines()
      let (m, sent) = m.check_now()
      (m, [Clear(key=m.page.storage_key), m.load_selected(fresh=true), ..sent])
    }
    OpenPlayground => {
      let models = m.files.filter(f => !@model.is_query_file(f.name))
      guard m.page.playground is Some(href) && models.get(0) is Some(file) else {
        return (m, [])
      }
      let state : @samples.ShareState = {
        model: file.text,
        transcript: "",
        tab: if m.page.output is Some(_) {
          TransformTab
        } else {
          ValidateTab
        },
        output: m.page.output.unwrap_or(JsonAst),
        protocol: "",
        format: Markdown,
        complete: false,
        selector: @model.query_of(m.files, fixed=m.page.selector),
        log_preset: None,
        version: None,
      }
      // A link that is too long would not open in the playground.
      let fragment = if @core.share_state_problem(state) is None {
        @core.encode_share(state)
      } else {
        ""
      }
      if fragment == "" || fragment.length() > @core.MAX_SHARE_LENGTH {
        ({ ..m, link_problem: Some(too_large_text), }, [])
      } else {
        (m, [Navigate(url=href + "#" + fragment)])
      }
    }
  }
}

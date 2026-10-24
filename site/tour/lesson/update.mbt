///|
fn Model::send_validate(self : Model) -> (Model, Array[Effect]) {
  let seq = self.seq + 1
  (
    {
      ..self,
      seq,
      sent_edits: self.edits,
      waiting: true,
      inflight: Validating,
      pending: false,
    },
    [
      SendValidate(seq~, files=pairs(self.files)),
      Wait(ms=TIMEOUT_MS, msg=TimedOut(seq)),
    ],
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
        files=pairs(self.files),
        output~,
        selector=self.page.selector,
      ),
      Wait(ms=TIMEOUT_MS, msg=TimedOut(seq)),
    ],
  )
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
/// The name of the output tab.
pub fn output_label(output : @samples.Output) -> String {
  match output {
    JsonAst => "JSON AST"
    Idl => "IDL"
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
  let label = output_label(output)
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
pub fn update(m : Model, msg : Msg) -> (Model, Array[Effect]) {
  match msg {
    Edited(text) => {
      guard m.files.get(m.selected) is Some(file) && file.text != text else {
        return (m, [])
      }
      let files = m.files.copy()
      files[m.selected] = { ..file, text, }
      let edits = m.edits + 1
      let m = { ..m, files, edits, link_problem: None, }
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
        Some(file) if index != m.selected => {
          let m = { ..m, selected: index, }
          (m, [LoadEditor(text=file.text), Mark(items=m.selected_findings())])
        }
        _ => (m, [])
      }
    SelectPane(pane) =>
      if pane == OutputPane && m.page.output is None {
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
          let m = { ..m, findings: NotChecked(reason), }
          if m.page.output is Some(_) {
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
        (Transforming, NotConverted(reason)) => {
          let (m, shown) = m.not_shown(reason)
          m.next(shown)
        }
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
        match (m.inflight, m.page.output) {
          (Transforming, _) => {
            let (m, shown) = m.not_shown(timeout_text)
            m.next([RestartWorker, ..shown])
          }
          (Validating, None) =>
            { ..m, findings: NotChecked(timeout_text), }.next([
              RestartWorker,
              Mark(items=[]),
            ])
          (Validating, Some(_)) => {
            let (m, shown) = { ..m, findings: NotChecked(timeout_text), }.not_shown(
              timeout_text,
            )
            m.next([RestartWorker, Mark(items=[]), ..shown])
          }
        }
      } else {
        let (sent, more) = match m.inflight {
          Validating => m.send_validate()
          Transforming => m.send_transform()
        }
        ({ ..sent, retried: true, }, [RestartWorker, ..more])
      }
    }
    Reset => {
      let m = {
        ..m,
        files: m.page.files,
        edits: m.edits + 1,
        link_problem: None,
      }
      let (m, sent) = m.check_now()
      (
        m,
        [
          Clear(key=m.page.storage_key),
          LoadEditor(text=m.selected_text()),
          ..sent,
        ],
      )
    }
    OpenPlayground => {
      guard m.page.playground is Some(href) && m.files.get(0) is Some(file) else {
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
        selector: m.page.selector,
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

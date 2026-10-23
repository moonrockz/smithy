///|
/// What the page needs to start the playground. The pre-render writes it in
/// the site data of the playground page.
pub(all) struct PlaygroundData {
  /// The Smithy version that the Worker runs.
  version : String
  /// The URL of the Worker script.
  worker : String
  samples : Array[@samples.Sample]
  /// The index of the sample to open.
  selected : Int32
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend PlaygroundData with Eq::{equal, not_equal}

///|
pub extend PlaygroundData with @debug.Debug::{to_repr}

///|
pub extend PlaygroundData with ToJson::{to_json}

///|
pub extend PlaygroundData with FromJson::{from_json}

///|
/// A diagnostic of the model, as the library writes it. Lines and columns
/// start at 1; a line of 0 means that the library gave no place in the text.
pub(all) struct Diagnostic {
  severity : String
  code : String
  message : String
  file : String
  start_line : Int32
  start_column : Int32
  end_line : Int32
  end_column : Int32
  shape : String?
} derive(Eq, Debug)

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
/// ERROR and DANGER stop a model; the other severities do not.
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  self.severity == "ERROR" || self.severity == "DANGER"
}

///|
pub(all) enum Tab {
  ValidateTab
  TransformTab
  TranscriptTab
} derive(Eq, Debug)

///|
pub extend Tab with Eq::{equal, not_equal}

///|
pub extend Tab with @debug.Debug::{to_repr}

///|
/// The result of the newest check that the page shows.
pub(all) enum Check {
  /// No answer yet.
  Unchecked
  Checked(items~ : Array[Diagnostic], shapes~ : Int32)
  /// The Worker did not run the request, for the reason given.
  Refused(String)
  /// The Worker did not answer in time and was replaced.
  Stopped
  /// The Worker stopped with an error, given by the browser, and was replaced.
  Failed(String)
} derive(Eq, Debug)

///|
pub extend Check with Eq::{equal, not_equal}

///|
pub extend Check with @debug.Debug::{to_repr}

///|
/// The answer of the Worker to a check.
pub(all) enum Answer {
  Validated(items~ : Array[Diagnostic], shapes~ : Int32)
  NotRun(String)
} derive(Eq, Debug)

///|
pub extend Answer with Eq::{equal, not_equal}

///|
pub extend Answer with @debug.Debug::{to_repr}

///|
pub(all) struct Model {
  data : PlaygroundData
  sample : Int32
  tab : Tab
  /// The number of changes to the model text so far.
  edits : Int32
  /// The number of the newest request; each request has a new one.
  seq : Int32
  /// The value of `edits` when the newest request was sent.
  sent_edits : Int32
  /// True while the newest request has no answer.
  waiting : Bool
  /// True when the text changed and its wait ended while a request ran.
  /// The newest text goes to the Worker when that request ends.
  pending : Bool
  check : Check
  /// The cursor, from 1.
  line : Int32
  column : Int32
} derive(Eq, Debug)

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
pub(all) enum Msg {
  /// The model text changed.
  Edited
  CursorMoved(line~ : Int32, column~ : Int32)
  /// The wait after the change with this number ended.
  Debounced(edits~ : Int32)
  Answered(seq~ : Int32, answer~ : Answer)
  /// The time for the request with this number ended.
  TimedOut(seq~ : Int32)
  /// The Worker stopped with an error; the text is the message of the browser.
  WorkerFailed(String)
  SampleChosen(Int32)
  TabChosen(Tab)
  DiagnosticChosen(line~ : Int32, column~ : Int32)
} derive(Eq, Debug)

///|
pub extend Msg with Eq::{equal, not_equal}

///|
pub extend Msg with @debug.Debug::{to_repr}

///|
/// What the page must do after an update. The page reads the model text from
/// the editor when it sends a request, so the text is not in the model.
pub(all) enum Effect {
  /// Send `then` after `ms` milliseconds.
  Wait(ms~ : Int32, then~ : Msg)
  /// Send the editor text to the Worker for a check.
  SendValidate(seq~ : Int32)
  /// Replace the editor text.
  LoadText(String)
  /// Show these diagnostics in the editor.
  Mark(Array[Diagnostic])
  MoveCursor(line~ : Int32, column~ : Int32)
  /// End the Worker and start a new one.
  RestartWorker
} derive(Eq, Debug)

///|
pub extend Effect with Eq::{equal, not_equal}

///|
pub extend Effect with @debug.Debug::{to_repr}

///|
/// The wait after a change before the check, in milliseconds.
pub const DEBOUNCE_MS : Int32 = 250

///|
/// The time that the Worker has for one request, in milliseconds.
pub let timeout_ms : Int32 = 10000

///|
/// The model of a new page, and the check of the first sample.
pub fn Model::start(data : PlaygroundData) -> (Model, Array[Effect]) {
  let sample = if data.selected >= 0 && data.selected < data.samples.length() {
    data.selected
  } else {
    0
  }
  let m = {
    data,
    sample,
    tab: ValidateTab,
    edits: 0,
    seq: 0,
    sent_edits: 0,
    waiting: false,
    pending: false,
    check: Unchecked,
    line: 1,
    column: 1,
  }
  m.send()
}

///|
/// The text of the sample that the page opens with.
pub fn Model::first_text(self : Model) -> String {
  match self.data.samples.get(self.sample) {
    Some(sample) => sample.model
    None => ""
  }
}

///|
fn Model::send(self : Model) -> (Model, Array[Effect]) {
  let seq = self.seq + 1
  (
    { ..self, seq, sent_edits: self.edits, waiting: true, pending: false, },
    [SendValidate(seq~), Wait(ms=timeout_ms, then=TimedOut(seq~))],
  )
}

///|
/// True when the result on the page is for the text in the editor: no
/// change since its request, and no newer request running.
pub fn Model::is_current(self : Model) -> Bool {
  !self.waiting && self.edits == self.sent_edits
}

///|
/// After the newest request ended with no result to show: send the newest
/// text when a change waits for it. One request runs at a time, so the time
/// limit of a request measures that request only.
fn Model::next(self : Model, effects : Array[Effect]) -> (Model, Array[Effect]) {
  let m = { ..self, waiting: false, }
  if m.pending {
    let (sent, more) = m.send()
    (sent, [..effects, ..more])
  } else {
    (m, effects)
  }
}

///|
pub fn Model::errors(self : Model) -> Int32 {
  match self.check {
    Checked(items~, ..) => items.filter(d => d.is_error()).length()
    _ => 0
  }
}

///|
pub fn Model::warnings(self : Model) -> Int32 {
  match self.check {
    Checked(items~, ..) => items.filter(d => !d.is_error()).length()
    _ => 0
  }
}

///|
pub fn update(m : Model, msg : Msg) -> (Model, Array[Effect]) {
  match msg {
    Edited => {
      let edits = m.edits + 1
      ({ ..m, edits, }, [Wait(ms=DEBOUNCE_MS, then=Debounced(edits~))])
    }
    // Only one request runs at a time: a change while one runs waits for it.
    Debounced(edits~) =>
      if edits != m.edits {
        (m, [])
      } else if m.waiting {
        ({ ..m, pending: true, }, [])
      } else {
        m.send()
      }
    Answered(seq~, answer~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      // The answer is for text that changed since: it does not show.
      guard m.edits == m.sent_edits else { return m.next([]) }
      match answer {
        Validated(items~, shapes~) =>
          (
            { ..m, waiting: false, check: Checked(items~, shapes~), },
            [Mark(items)],
          )
        NotRun(reason) =>
          ({ ..m, waiting: false, check: Refused(reason), }, [Mark([])])
      }
    }
    TimedOut(seq~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      { ..m, check: Stopped, }.next([RestartWorker, Mark([])])
    }
    // An error while no request runs restarts nothing: a Worker that cannot
    // load would restart again and again.
    WorkerFailed(message) => {
      guard m.waiting else { return (m, []) }
      { ..m, check: Failed(message), }.next([RestartWorker, Mark([])])
    }
    SampleChosen(index) =>
      match m.data.samples.get(index) {
        Some(sample) => ({ ..m, sample: index, }, [LoadText(sample.model)])
        None => (m, [])
      }
    TabChosen(tab) => ({ ..m, tab, }, [])
    CursorMoved(line~, column~) => ({ ..m, line, column, }, [])
    // A row of an older result names a place in older text.
    DiagnosticChosen(line~, column~) =>
      if m.is_current() {
        (m, [MoveCursor(line~, column~)])
      } else {
        (m, [])
      }
  }
}

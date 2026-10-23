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
/// The transform that the Transform tab runs.
pub(all) enum Output {
  JsonAst
  Idl
  Selector
  JsonSchema
  OpenApi30
  OpenApi31
  OpenRpc
} derive(Eq, Debug)

///|
pub extend Output with Eq::{equal, not_equal}

///|
pub extend Output with @debug.Debug::{to_repr}

///|
/// Why the Worker did not run a request.
pub(all) enum BlockedBy {
  /// The model has errors.
  ModelErrors
  /// Any other reason. The text of the answer says it.
  Other
} derive(Eq, Debug)

///|
pub extend BlockedBy with Eq::{equal, not_equal}

///|
pub extend BlockedBy with @debug.Debug::{to_repr}

///|
/// The request that the Worker runs now. One request runs at a time.
pub(all) enum Kind {
  Validating
  Transforming
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with @debug.Debug::{to_repr}

///|
/// The answer of the Worker to a request. The text of the files stays in
/// the page script; the model holds the names only.
pub(all) enum Answer {
  Validated(items~ : Array[Diagnostic], shapes~ : Int32)
  Transformed(files~ : Array[String], warnings~ : Array[String])
  NotRun(String, BlockedBy)
} derive(Eq, Debug)

///|
pub extend Answer with Eq::{equal, not_equal}

///|
pub extend Answer with @debug.Debug::{to_repr}

///|
/// The state of the Transform tab.
pub(all) enum Transformation {
  /// No run yet.
  TxIdle
  /// The run waits for the Worker, or the Worker runs it.
  TxRunning
  /// The output. `file` is the index of the file that the editor shows.
  /// `edits` is the number of changes to the model when the run started.
  TxDone(
    output~ : Output,
    files~ : Array[String],
    warnings~ : Array[String],
    file~ : Int32,
    edits~ : Int32
  )
  /// The Worker did not run the transform, for the reason given.
  TxBlocked(reason~ : String, by~ : BlockedBy)
  /// The Worker did not answer in time and was replaced.
  TxStopped
  /// The Worker stopped with an error, given by the browser, and was replaced.
  TxFailed(String)
} derive(Eq, Debug)

///|
pub extend Transformation with Eq::{equal, not_equal}

///|
pub extend Transformation with @debug.Debug::{to_repr}

///|
/// The result of the Copy button.
pub(all) enum Copy {
  NotCopied
  Copied
  CopyFailed
} derive(Eq, Debug)

///|
pub extend Copy with Eq::{equal, not_equal}

///|
pub extend Copy with @debug.Debug::{to_repr}

///|
pub(all) struct Model {
  data : PlaygroundData
  sample : Int32
  tab : Tab
  /// The number of changes to the model text so far.
  edits : Int32
  /// The number of the newest request; each request has a new one.
  seq : Int32
  /// The value of `edits` when the newest check was sent.
  sent_edits : Int32
  /// The value of `edits` for the check that the page shows.
  check_edits : Int32
  /// True while the newest request has no answer.
  waiting : Bool
  /// The kind of the newest request.
  inflight : Kind
  /// True when the text changed and its wait ended while a request ran.
  /// The newest text goes to the Worker when that request ends.
  pending : Bool
  /// True when Run was selected while a request ran. The transform goes to
  /// the Worker when that request ends, before a pending check.
  run_pending : Bool
  check : Check
  output : Output
  /// The selector of the Selector output.
  selector : String
  /// The value of `edits` when the newest transform was sent.
  tx_edits : Int32
  tx : Transformation
  copy : Copy
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
  OutputChosen(Output)
  SelectorEdited(String)
  RunClicked
  FileChosen(Int32)
  CopyClicked
  /// The clipboard took the text (true) or refused it (false).
  CopyDone(Bool)
  DownloadClicked
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
  /// Send the editor text to the Worker for a transform.
  SendTransform(seq~ : Int32, output~ : Output, selector~ : String?)
  /// Show this file of the output in the output editor.
  ShowFile(Int32)
  /// Put this file of the output on the clipboard.
  CopyFile(Int32)
  /// Save this file of the output on the computer of the user.
  DownloadFile(Int32)
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
/// The selector that the Selector output starts with.
pub const DEFAULT_SELECTOR : String = "structure > member"

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
    check_edits: 0,
    waiting: false,
    inflight: Validating,
    pending: false,
    run_pending: false,
    check: Unchecked,
    output: JsonAst,
    selector: DEFAULT_SELECTOR,
    tx_edits: 0,
    tx: TxIdle,
    copy: NotCopied,
    line: 1,
    column: 1,
  }
  m.send_validate()
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
    [SendValidate(seq~), Wait(ms=timeout_ms, then=TimedOut(seq~))],
  )
}

///|
fn Model::send_transform(self : Model) -> (Model, Array[Effect]) {
  let seq = self.seq + 1
  let selector = if self.output == Selector {
    Some(self.selector)
  } else {
    None
  }
  (
    {
      ..self,
      seq,
      tx_edits: self.edits,
      waiting: true,
      inflight: Transforming,
      run_pending: false,
      tx: TxRunning,
      copy: NotCopied,
    },
    [
      SendTransform(seq~, output=self.output, selector~),
      Wait(ms=timeout_ms, then=TimedOut(seq~)),
    ],
  )
}

///|
/// True when the check on the page is for the text in the editor: no change
/// since its request, and no newer check waiting.
pub fn Model::is_current(self : Model) -> Bool {
  self.edits == self.check_edits && !self.pending
}

///|
/// True when the page waits for a check.
pub fn Model::checking(self : Model) -> Bool {
  (self.waiting && self.inflight == Validating) || self.pending
}

///|
/// After the newest request ended: send what waits for the Worker. A
/// transform that the user asked for goes first, then the newest text. One
/// request runs at a time, so the time limit of a request measures that
/// request only, and no request waits in the Worker behind another.
fn Model::next(self : Model, effects : Array[Effect]) -> (Model, Array[Effect]) {
  let m = { ..self, waiting: false, }
  if m.run_pending {
    let (sent, more) = m.send_transform()
    (sent, [..effects, ..more])
  } else if m.pending {
    let (sent, more) = m.send_validate()
    (sent, [..effects, ..more])
  } else {
    (m, effects)
  }
}

///|

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
        m.send_validate()
      }
    Answered(seq~, answer~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      match (m.inflight, answer) {
        (Validating, Validated(items~, shapes~)) =>
          // The answer is for text that changed since: it does not show.
          if m.edits != m.sent_edits {
            m.next([])
          } else {
            { ..m, check: Checked(items~, shapes~), check_edits: m.sent_edits, }.next([
                Mark(items),
              ],
            )
          }
        (Validating, NotRun(reason, _)) =>
          if m.edits != m.sent_edits {
            m.next([])
          } else {
            { ..m, check: Refused(reason), check_edits: m.sent_edits, }.next([
              Mark([]),
            ])
          }
        // The output shows even when the model changed after the run. The
        // tab then says so.
        (Transforming, Transformed(files~, warnings~)) =>
          {
            ..m,
            tx: TxDone(
              output=m.output,
              files~,
              warnings~,
              file=0,
              edits=m.tx_edits,
            ),
          }.next(if files.is_empty() { [] } else { [ShowFile(0)] })
        (Transforming, NotRun(reason, by)) =>
          { ..m, tx: TxBlocked(reason~, by~), }.next([])
        // An answer of the other kind cannot come; the request ends.
        _ => m.next([])
      }
    }
    TimedOut(seq~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      match m.inflight {
        Validating => { ..m, check: Stopped, }.next([RestartWorker, Mark([])])
        Transforming => { ..m, tx: TxStopped, }.next([RestartWorker])
      }
    }
    // An error while no request runs restarts nothing: a Worker that cannot
    // load would restart again and again.
    WorkerFailed(message) => {
      guard m.waiting else { return (m, []) }
      match m.inflight {
        Validating =>
          { ..m, check: Failed(message), }.next([RestartWorker, Mark([])])
        Transforming => { ..m, tx: TxFailed(message), }.next([RestartWorker])
      }
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
    OutputChosen(output) => ({ ..m, output, }, [])
    SelectorEdited(selector) => ({ ..m, selector, }, [])
    // A run while a request runs waits for it, as a change does.
    RunClicked =>
      if m.tx == TxRunning {
        (m, [])
      } else if m.waiting {
        ({ ..m, run_pending: true, tx: TxRunning, copy: NotCopied, }, [])
      } else {
        m.send_transform()
      }
    FileChosen(index) =>
      match m.tx {
        TxDone(output~, files~, warnings~, edits~, ..) =>
          if index >= 0 && index < files.length() {
            (
              {
                ..m,
                tx: TxDone(output~, files~, warnings~, file=index, edits~),
                copy: NotCopied,
              },
              [ShowFile(index)],
            )
          } else {
            (m, [])
          }
        _ => (m, [])
      }
    CopyClicked =>
      match m.tx {
        TxDone(file~, ..) => (m, [CopyFile(file)])
        _ => (m, [])
      }
    CopyDone(ok) => ({ ..m, copy: if ok { Copied } else { CopyFailed }, }, [])
    DownloadClicked =>
      match m.tx {
        TxDone(file~, ..) => (m, [DownloadFile(file)])
        _ => (m, [])
      }
  }
}

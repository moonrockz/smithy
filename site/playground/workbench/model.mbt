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
  /// The transcripts of the Transcript tab picker.
  transcripts : Array[@samples.TranscriptSample]
  /// The index of the transcript to open.
  transcript : Int32
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
pub using @samples {type Tab, type Output}

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
  Transcribing
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with @debug.Debug::{to_repr}

///|
/// The answer of the Worker to a request. The text of the files stays in
/// the page script; the model holds the names only.
pub(all) enum Answer {
  /// The diagnostics and the JSON-RPC protocols of the model.
  Validated(
    items~ : Array[Diagnostic],
    shapes~ : Int32,
    protocols~ : Array[Protocol]
  )
  Transformed(
    files~ : Array[String],
    warnings~ : Array[String],
    service~ : String?
  )
  NotRun(String, BlockedBy)
  /// The change of a transcript check since the previous answer: every entry
  /// for a start, and the new findings.
  Progressed(
    entries~ : Array[Entry],
    findings~ : Array[Finding],
    checked~ : Int32,
    done~ : Bool,
    summary~ : Summary?
  )
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
  /// `output`, `selector` and `service` are those of the run, so the page
  /// describes the shown output and not the picker.
  /// `seq` is the request that gave the files; the page script keeps their text by it.
  TxDone(
    seq~ : Int32,
    output~ : Output,
    selector~ : String,
    service~ : String?,
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
/// What the share button did, or why the page opened without the link that
/// it was given.
pub(all) enum Share {
  NoShare
  /// The URL of the link, which the clipboard took.
  LinkCopied(String)
  /// The URL of the link. The browser has no clipboard, so the page shows it.
  LinkShown(String)
  /// The state does not fit in a link. The text says why.
  LinkTooLong(String)
  /// The page could not open the link that it was given. The text says why.
  LinkRefused(String)
  /// The user pasted a link that the page could not read. The page kept its state.
  LinkIgnored(String)
} derive(Eq, Debug)

///|
pub extend Share with Eq::{equal, not_equal}

///|
pub extend Share with @debug.Debug::{to_repr}

///|
/// How the page was opened.
pub(all) enum Opened {
  /// With no link in the address.
  Default
  /// With the state of a link.
  Shared(@samples.ShareState)
  /// With a link that the page could not read. The text says why.
  Refused(String)
} derive(Eq, Debug)

///|
pub extend Opened with Eq::{equal, not_equal}

///|
pub extend Opened with @debug.Debug::{to_repr}

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
  /// The whole seconds that the newest request has run, while it runs.
  elapsed : Int32
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
  /// The output and the selector of the newest transform when it was sent.
  tx_output : Output
  tx_selector : String
  tx : Transformation
  copy : Copy
  /// The index of the transcript of the picker.
  transcript : Int32
  /// The JSON-RPC protocols of the newest model that assembled.
  protocols : Array[Protocol]
  settings : Settings
  /// The number of changes to the transcript text so far.
  text_edits : Int32
  /// What the session of the Worker checks; `None` when the Worker has none.
  session : Started?
  /// What the newest transcript request was sent for.
  tr_sent : Started
  tr : Checking
  /// A button of the tab that waits for the request that runs.
  tr_pending : Action?
  /// What the check still needs after the transcript request that runs.
  goal : Goal
  /// The newest transcript request.
  tr_request : TrRequest
  /// The cursor, from 1.
  line : Int32
  column : Int32
  share : Share
  /// The state of a pasted link that waits for the answer of the user,
  /// because the editors have changes.
  incoming : @samples.ShareState?
  /// True when the Worker could not read the newest request: the page and
  /// the Worker script come from different builds. A reload fixes it.
  mismatch : Bool
  /// True when the Validate list shows the repeats of a diagnostic in one row.
  grouped : Bool
  /// The tabs whose controls are folded away.
  folded : Folded
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
  /// One more second of the request with this number passed.
  Ticked(seq~ : Int32)
  /// The Worker stopped with an error; the text is the message of the browser.
  WorkerFailed(String)
  /// The Worker could not read a request, or the page could not read its
  /// answer: the Worker script is of another build than the page.
  Mismatched
  OutputChosen(Output)
  SelectorEdited(String)
  RunClicked
  FileChosen(Int32)
  CopyClicked
  /// The clipboard took the text (true) or refused it (false).
  CopyDone(Bool)
  DownloadClicked
  /// The Share link button.
  ShareClicked
  /// The link was made, or could not be made.
  ShareDone(Share)
  /// The Download button of the toolbar.
  SaveClicked
  /// The user opened another link in this tab. `dirty` is true when an editor
  /// text differs from the text that the page loaded or shared last.
  LinkOpened(opened~ : Opened, dirty~ : Bool)
  /// "Open" of the question about a pasted link.
  OpenIncoming
  /// "Keep my changes" of the question about a pasted link.
  KeepMine
  SampleChosen(Int32)
  TabChosen(Tab)
  /// The Go button of a diagnostic.
  DiagnosticChosen(line~ : Int32, column~ : Int32)
  /// A click on the message or the place of a diagnostic. It can end a text
  /// selection, which must stay.
  DiagnosticClicked(line~ : Int32, column~ : Int32)
  TranscriptSampleChosen(Int32)
  /// The transcript text changed.
  TranscriptEdited
  ProtocolChosen(String)
  FormatChosen(@samples.TranscriptFormat)
  CompleteChosen(Bool)
  VersionChosen(String)
  PresetChosen(LogKind)
  /// The `dir` value of the messages of `peer` changed.
  DirectionEdited(peer~ : String, value~ : String)
  SenderChosen(String)
  StepClicked
  RunAllClicked
  ResetClicked
  /// An entry of the list: its place in the transcript text.
  EntryChosen(line~ : Int32, column~ : Int32)
  /// The "Group repeats" button of the Validate tab.
  GroupToggled
  /// The fold button of the controls of a tab.
  FoldToggled(@samples.Tab)
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
  /// Show this file of the output of the request `seq` in the output editor.
  /// The page script drops the files of every other request.
  ShowFile(seq~ : Int32, index~ : Int32)
  /// Put this file of the output of the request `seq` on the clipboard.
  CopyFile(seq~ : Int32, index~ : Int32)
  /// Save this file of the output of the request `seq` on the computer of the user.
  DownloadFile(seq~ : Int32, index~ : Int32)
  /// Make the link of the editors and these settings, put it in the address
  /// and on the clipboard. The page answers with `ShareDone`.
  MakeShare(
    tab~ : Tab,
    output~ : Output,
    selector~ : String,
    settings~ : Settings
  )
  /// Put the texts of a pasted link in the editors. The page script keeps
  /// them as the texts that the user has not changed.
  ApplyShared(
    model~ : String,
    transcript~ : String,
    format~ : @samples.TranscriptFormat
  )
  /// Save the model, and the transcript in this format, as files on the
  /// computer of the user.
  SaveFiles(transcript~ : @samples.TranscriptFormat?)
  /// Replace the editor text.
  LoadText(String)
  /// Show these diagnostics in the editor.
  Mark(Array[Diagnostic])
  MoveCursor(line~ : Int32, column~ : Int32)
  /// Move the cursor as `MoveCursor` does, unless the reader has selected
  /// text on the page: the click then ended the selection.
  MoveCursorUnlessSelecting(line~ : Int32, column~ : Int32)
  /// End the Worker and start a new one.
  RestartWorker
  /// Send the editor texts of the model and the transcript to the Worker, to
  /// start a transcript check.
  SendTranscriptStart(seq~ : Int32, settings~ : Settings)
  SendTranscriptStep(seq~ : Int32, count~ : Int32)
  SendTranscriptReset(seq~ : Int32)
  /// Replace the text and the language of the transcript editor.
  LoadTranscript(text~ : String, format~ : @samples.TranscriptFormat)
  SetTranscriptLanguage(@samples.TranscriptFormat)
  /// Move the cursor of the transcript editor to a line, if the user does not
  /// type in it.
  FollowTranscript(line~ : Int32)
  /// Move the cursor of the transcript editor to a place and focus it.
  GoToTranscript(line~ : Int32, column~ : Int32)
  /// Keep the choice of "Group repeats" in the browser for the next visit.
  StoreGrouped(Bool)
  /// Keep the folds of the tabs in the browser for the next visit.
  StoreFolded(Folded)
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
/// The time between two `Ticked` messages of a request, in milliseconds.
pub const TICK_MS : Int32 = 1000

///|
/// The selector that the Selector output starts with.
pub const DEFAULT_SELECTOR : String = "structure > member"

///|
/// The model of a new page, and the check of the first sample.
pub fn Model::start(data : PlaygroundData) -> (Model, Array[Effect]) {
  Model::start_with(data, Default)
}

///|
/// The model of a new page that was opened as `opened` says, and the check of
/// its model. The state of a link joins the pickers as "Shared link", so the
/// page opens with its texts. The settings stay as the link gives them until
/// the first check lists the protocols; then they fit the model.
pub fn Model::start_with(
  data : PlaygroundData,
  opened : Opened,
) -> (Model, Array[Effect]) {
  let data = match opened {
    Shared(state) => data.with_shared(state)
    _ => data
  }
  let sample = if data.selected >= 0 && data.selected < data.samples.length() {
    data.selected
  } else {
    0
  }
  let transcript = if data.transcript >= 0 &&
    data.transcript < data.transcripts.length() {
    data.transcript
  } else {
    0
  }
  let complete = match opened {
    Shared(state) => state.complete
    _ => false
  }
  let settings : Settings = match data.transcripts.get(transcript) {
    Some(sample) => { ..Settings::of_sample(sample), complete, }
    None =>
      {
        protocol: "",
        format: Markdown,
        complete: false,
        version: "",
        preset: DirMessage([]),
      }
  }
  let output : Output = match opened {
    Shared(state) => state.output
    _ => JsonAst
  }
  let selector = match opened {
    Shared({ selector: Some(selector), .. }) => selector
    _ => DEFAULT_SELECTOR
  }
  let m = {
    data,
    sample,
    tab: match opened {
      Shared(state) => state.tab
      _ => ValidateTab
    },
    edits: 0,
    seq: 0,
    sent_edits: 0,
    check_edits: 0,
    waiting: false,
    elapsed: 0,
    inflight: Validating,
    pending: false,
    run_pending: false,
    check: Unchecked,
    output,
    selector,
    tx_edits: 0,
    tx_output: output,
    tx_selector: selector,
    tx: TxIdle,
    copy: NotCopied,
    transcript,
    protocols: [],
    settings,
    text_edits: 0,
    session: None,
    tr_sent: { model_edits: 0, text_edits: 0, settings, },
    tr: TrIdle,
    tr_pending: None,
    goal: NoGoal,
    tr_request: Starting,
    line: 1,
    column: 1,
    share: match opened {
      Refused(reason) => LinkRefused(reason)
      _ => NoShare
    },
    incoming: None,
    mismatch: false,
    grouped: true,
    folded: no_fold,
  }
  m.send_validate()
}

///|
/// The model with the choice of "Group repeats" that the browser kept.
pub fn Model::with_grouped(self : Model, grouped : Bool) -> Model {
  { ..self, grouped, }
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
      elapsed: 0,
      inflight: Validating,
      pending: false,
    },
    [
      SendValidate(seq~),
      Wait(ms=timeout_ms, then=TimedOut(seq~)),
      Wait(ms=TICK_MS, then=Ticked(seq~)),
    ],
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
      tx_output: self.output,
      tx_selector: self.selector,
      waiting: true,
      elapsed: 0,
      inflight: Transforming,
      run_pending: false,
      tx: TxRunning,
      copy: NotCopied,
    },
    [
      SendTransform(seq~, output=self.output, selector~),
      Wait(ms=timeout_ms, then=TimedOut(seq~)),
      Wait(ms=TICK_MS, then=Ticked(seq~)),
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
/// True when a check of newer text than the result on the page runs or
/// comes. Every change starts a wait that ends in a check, so a change since
/// the newest request is enough: the result on the page is then for older
/// text, also during the 250 ms wait and after an answer for older text.
pub fn Model::checking(self : Model) -> Bool {
  (self.waiting && self.inflight == Validating) ||
  self.pending ||
  self.edits != self.sent_edits
}

///|
/// After the newest request ended: send what waits for the Worker. A
/// transform that the user asked for goes first, then a button of the
/// Transcript tab, then the newest text, then the next group of a Run all.
/// One request runs at a time, so the time limit of a request measures that
/// request only, and no request waits in the Worker behind another.
fn Model::next(self : Model, effects : Array[Effect]) -> (Model, Array[Effect]) {
  let m = { ..self, waiting: false, }
  if m.run_pending {
    let (sent, more) = m.send_transform()
    return (sent, [..effects, ..more])
  }
  let m = match m.tr_pending {
    Some(action) => {
      let (sent, more) = m.act(action)
      if sent.waiting {
        return (sent, [..effects, ..more])
      }
      sent
    }
    None => m
  }
  if m.pending {
    let (sent, more) = m.send_validate()
    (sent, [..effects, ..more])
  } else if m.goal != NoGoal && m.can_step() {
    let (sent, more) = m.send_step(m.goal)
    (sent, [..effects, ..more])
  } else {
    ({ ..m, goal: NoGoal, }, effects)
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
/// The WARNING findings. DANGER counts as an error (see `Diagnostic::is_error`).
/// NOTE and SUGGESTION are not counted: `smithy validate` does not print them.
pub fn Model::warnings(self : Model) -> Int32 {
  match self.check {
    Checked(items~, ..) => items.filter(d => d.severity == "WARNING").length()
    _ => 0
  }
}

///|
/// The data with the state of a link as the last sample of both pickers, titled
/// "Shared link" and selected. The state of an earlier link goes out. The page
/// start and a link opened later both use this.
fn PlaygroundData::with_shared(
  self : PlaygroundData,
  state : @samples.ShareState,
) -> PlaygroundData {
  let samples = self.samples.filter(s => s.path != "")
  let transcripts = self.transcripts.filter(s => s.path != "")
  let transcript : @samples.TranscriptSample = {
    title: "Shared link",
    path: "",
    protocol: state.protocol,
    format: state.format,
    version: state.version,
    preset: state.log_preset,
    text: state.transcript,
  }
  {
    ..self,
    samples: [
      ..samples,
      { title: "Shared link", path: "", model: state.model, },
    ],
    selected: samples.length(),
    transcripts: [..transcripts, transcript],
    transcript: transcripts.length(),
  }
}

///|
/// Open the state of a link in a page that runs. The state joins the pickers
/// as "Shared link", in place of the one of an earlier link. The texts go to
/// the editors, which send their own change messages; the check starts after
/// the wait as for any change. The settings stay as the link gives them until
/// that check lists the protocols, then they fit the model.
fn Model::reopen(
  self : Model,
  state : @samples.ShareState,
) -> (Model, Array[Effect]) {
  let data = self.data.with_shared(state)
  let selector = state.selector.unwrap_or(DEFAULT_SELECTOR)
  let edits = self.edits + 1
  // A transform that runs belongs to the page as it was: its answer comes
  // with the output and selector of its own run, and the tab marks it old.
  // A run that only waits for a request never starts.
  let running = self.waiting && self.inflight == Transforming
  let (tx, tx_output, tx_selector) = if running {
    (self.tx, self.tx_output, self.tx_selector)
  } else {
    (TxIdle, state.output, selector)
  }
  let transcript = data.transcripts[data.transcript]
  (
    {
      ..self,
      data,
      sample: data.selected,
      transcript: data.transcript,
      tab: state.tab,
      output: state.output,
      selector,
      tx_output,
      tx_selector,
      tx,
      run_pending: false,
      tr_pending: None,
      goal: NoGoal,
      copy: NotCopied,
      settings: { ..Settings::of_sample(transcript), complete: state.complete, },
      edits,
      share: NoShare,
      incoming: None,
    },
    [
      ApplyShared(
        model=state.model,
        transcript=state.transcript,
        format=state.format,
      ),
      Wait(ms=DEBOUNCE_MS, then=Debounced(edits~)),
    ],
  )
}

///|
pub fn update(m : Model, msg : Msg) -> (Model, Array[Effect]) {
  let (next, effects) = update_state(m, msg)
  (next.open_for_notices(m), effects)
}

///|
/// The model and the effects after a message, before folded controls with a
/// notice open again.
fn update_state(m : Model, msg : Msg) -> (Model, Array[Effect]) {
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
      let m = { ..m, mismatch: false, }
      match (m.inflight, answer) {
        (Validating, Validated(items~, shapes~, protocols~)) =>
          // The answer is for text that changed since: it does not show.
          if m.edits != m.sent_edits {
            m.next([])
          } else {
            // A model with errors does not assemble and lists no protocol;
            // the protocols of the previous model stay until it assembles.
            let m = if protocols.is_empty() && items.any(d => d.is_error()) {
              m
            } else {
              { ..m, protocols, }.with_settings(m.settings)
            }
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
        (Transforming, Transformed(files~, warnings~, service~)) =>
          {
            ..m,
            tx: TxDone(
              seq~,
              output=m.tx_output,
              selector=m.tx_selector,
              service~,
              files~,
              warnings~,
              file=0,
              edits=m.tx_edits,
            ),
          }.next(if files.is_empty() { [] } else { [ShowFile(seq~, index=0)] })
        (Transforming, NotRun(reason, by)) =>
          { ..m, tx: TxBlocked(reason~, by~), }.next([])
        (Transcribing, answer) => m.transcript_answer(seq, answer)
        // An answer of the other kind cannot come; the request ends.
        _ => m.next([])
      }
    }
    // The seconds of the request that runs, so the page shows that it works.
    Ticked(seq~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      ({ ..m, elapsed: m.elapsed + 1, }, [Wait(ms=TICK_MS, then=Ticked(seq~))])
    }
    TimedOut(seq~) => {
      guard seq == m.seq && m.waiting else { return (m, []) }
      // A new Worker has no transcript session.
      let m = m.lost_session()
      match m.inflight {
        Validating => { ..m, check: Stopped, }.next([RestartWorker, Mark([])])
        Transforming => { ..m, tx: TxStopped, }.next([RestartWorker])
        Transcribing =>
          {
            ..m,
            tr: if m.tr_request == Resetting {
              TrIdle
            } else {
              TrStopped
            },
          }.next([RestartWorker])
      }
    }
    // A Worker of another build answers at once, so the page does not wait
    // for the time limit. A new Worker would load the same script, so none
    // starts, and the work that waits is not sent.
    Mismatched => {
      guard m.waiting else { return (m, []) }
      let tx = if m.inflight == Transforming && m.tx == TxRunning {
        TxIdle
      } else {
        m.tx
      }
      (
        {
          ..m,
          mismatch: true,
          waiting: false,
          pending: false,
          run_pending: false,
          tr_pending: None,
          goal: NoGoal,
          tx,
        },
        [],
      )
    }
    // An error while no request runs restarts nothing: a Worker that cannot
    // load would restart again and again.
    WorkerFailed(message) => {
      guard m.waiting else { return (m, []) }
      let m = m.lost_session()
      match m.inflight {
        Validating =>
          { ..m, check: Failed(message), }.next([RestartWorker, Mark([])])
        Transforming => { ..m, tx: TxFailed(message), }.next([RestartWorker])
        Transcribing =>
          {
            ..m,
            tr: if m.tr_request == Resetting {
              TrIdle
            } else {
              TrFailed(message)
            },
          }.next([RestartWorker])
      }
    }
    SampleChosen(index) =>
      match m.data.samples.get(index) {
        Some(sample) => ({ ..m, sample: index, }, [LoadText(sample.model)])
        None => (m, [])
      }
    TabChosen(tab) => ({ ..m, tab, }, [])
    FoldToggled(tab) => {
      let folded = m.folded.toggle(tab)
      ({ ..m, folded, }, [StoreFolded(folded)])
    }
    GroupToggled => {
      let grouped = !m.grouped
      ({ ..m, grouped, }, [StoreGrouped(grouped)])
    }
    CursorMoved(line~, column~) => ({ ..m, line, column, }, [])
    // A row of an older result names a place in older text.
    DiagnosticChosen(line~, column~) =>
      if m.is_current() {
        (m, [MoveCursor(line~, column~)])
      } else {
        (m, [])
      }
    DiagnosticClicked(line~, column~) =>
      if m.is_current() {
        (m, [MoveCursorUnlessSelecting(line~, column~)])
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
        TxDone(
          seq~,
          output~,
          selector~,
          service~,
          files~,
          warnings~,
          edits~,
          ..
        ) =>
          if index >= 0 && index < files.length() {
            (
              {
                ..m,
                tx: TxDone(
                  seq~,
                  output~,
                  selector~,
                  service~,
                  files~,
                  warnings~,
                  file=index,
                  edits~,
                ),
                copy: NotCopied,
              },
              [ShowFile(seq~, index~)],
            )
          } else {
            (m, [])
          }
        _ => (m, [])
      }
    CopyClicked =>
      match m.tx {
        TxDone(seq~, file~, ..) => (m, [CopyFile(seq~, index=file)])
        _ => (m, [])
      }
    CopyDone(ok) => ({ ..m, copy: if ok { Copied } else { CopyFailed }, }, [])
    DownloadClicked =>
      match m.tx {
        TxDone(seq~, file~, ..) => (m, [DownloadFile(seq~, index=file)])
        _ => (m, [])
      }
    ShareClicked =>
      (
        m,
        [
          MakeShare(
            tab=m.tab,
            output=m.output,
            selector=m.selector,
            settings=m.settings,
          ),
        ],
      )
    LinkOpened(opened~, dirty~) =>
      match opened {
        Default => (m, [])
        Refused(reason) =>
          ({ ..m, share: LinkIgnored(reason), incoming: None, }, [])
        Shared(state) =>
          if dirty {
            ({ ..m, incoming: Some(state), share: NoShare, }, [])
          } else {
            m.reopen(state)
          }
      }
    OpenIncoming =>
      match m.incoming {
        Some(state) => m.reopen(state)
        None => (m, [])
      }
    KeepMine => ({ ..m, incoming: None, }, [])
    ShareDone(share) => ({ ..m, share, }, [])
    SaveClicked =>
      (
        m,
        [
          SaveFiles(
            transcript=if m.tab == TranscriptTab {
              Some(m.settings.format)
            } else {
              None
            },
          ),
        ],
      )
    _ => transcript_update(m, msg)
  }
}

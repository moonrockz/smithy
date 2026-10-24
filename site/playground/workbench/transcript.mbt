///|
/// A structure of the model with the `@jsonRpcProtocol` trait: the versions
/// that it declares and its peer names, in trait order.
pub(all) struct Protocol {
  id : String
  versions : Array[String]
  peers : Array[String]
} derive(Eq, Debug)

///|
pub extend Protocol with Eq::{equal, not_equal}

///|
pub extend Protocol with @debug.Debug::{to_repr}

///|
/// A transcript entry. `receiver` is `None` for a reply.
pub(all) struct Entry {
  index : Int32
  sender : String
  receiver : String?
  message : String
  line : Int32?
  column : Int32?
} derive(Eq, Debug)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
/// A transcript finding, as the library writes it. `severity` is "error" or
/// "advisory"; `path` is a JSON pointer.
pub(all) struct Finding {
  code : String
  severity : String
  message : String
  entry : Int32?
  line : Int32?
  column : Int32?
  sender : String?
  related : Array[Int32]
  path : String?
  shape : String?
  operation : String?
} derive(Eq, Debug)

///|
pub extend Finding with Eq::{equal, not_equal}

///|
pub extend Finding with @debug.Debug::{to_repr}

///|
/// An expected finding of the `expect` list of a transcript.
pub(all) struct Expected {
  code : String
  entry : Int32?
  related : Int32?
} derive(Eq, Debug)

///|
pub extend Expected with Eq::{equal, not_equal}

///|
pub extend Expected with @debug.Debug::{to_repr}

///|
/// The match of the findings against the `expect` list.
pub(all) struct Expectations {
  matched : Bool
  missing : Array[Expected]
  /// The unexpected error findings.
  unexpected : Array[Finding]
} derive(Eq, Debug)

///|
pub extend Expectations with Eq::{equal, not_equal}

///|
pub extend Expectations with @debug.Debug::{to_repr}

///|
/// The result at the end of a transcript. `lines`, `not_json` and `skipped`
/// are the counts of a JSONL log.
pub(all) struct Summary {
  valid : Bool
  complete : Bool
  entries : Int32
  errors : Int32
  outstanding : Int32
  correlation : Bool
  lines : Int32
  not_json : Int32
  skipped : Int32
  expectations : Expectations?
} derive(Eq, Debug)

///|
pub extend Summary with Eq::{equal, not_equal}

///|
pub extend Summary with @debug.Debug::{to_repr}

///|
/// The kind of a log preset, for the picker.
pub(all) enum LogKind {
  DirMessageLog
  RawLog
} derive(Eq, Debug)

///|
pub extend LogKind with Eq::{equal, not_equal}

///|
pub extend LogKind with @debug.Debug::{to_repr}

///|
/// How the Transcript tab checks the transcript text. `version` and `preset`
/// apply to a JSONL log only; a document gives its own version.
pub(all) struct Settings {
  protocol : String
  format : @samples.TranscriptFormat
  /// The CLI flag --complete. Clear: the document decides.
  complete : Bool
  version : String
  preset : @samples.LogPreset
} derive(Eq, Debug)

///|
pub extend Settings with Eq::{equal, not_equal}

///|
pub extend Settings with @debug.Debug::{to_repr}

///|
/// The settings of a transcript of the picker.
pub fn Settings::of_sample(sample : @samples.TranscriptSample) -> Settings {
  {
    protocol: sample.protocol,
    format: sample.format,
    complete: false,
    version: sample.version.unwrap_or(""),
    preset: sample.preset.unwrap_or(DirMessage([])),
  }
}

///|
/// The version of a request: the chosen one for a log, none for a document.
pub fn Settings::request_version(self : Settings) -> String? {
  if self.format == Jsonl && self.version != "" {
    Some(self.version)
  } else {
    None
  }
}

///|
/// The preset of a request: the chosen one for a log, none for a document.
pub fn Settings::request_preset(self : Settings) -> @samples.LogPreset? {
  if self.format == Jsonl {
    Some(self.preset)
  } else {
    None
  }
}

///|
/// True when both settings give the same check. A document gives its own
/// version and has no preset, so only a log compares them.
pub fn Settings::same_check(self : Settings, other : Settings) -> Bool {
  self.protocol == other.protocol &&
  self.format == other.format &&
  self.complete == other.complete &&
  (
    self.format != Jsonl ||
    (self.version == other.version && self.preset == other.preset)
  )
}

///|
/// The preset that the CLI uses with no option: "request" is the first peer
/// and "response" the second.
fn default_preset(protocol : Protocol) -> @samples.LogPreset {
  match protocol.peers {
    [first, second, ..] =>
      DirMessage([
        { value: "request", peer: first, },
        { value: "response", peer: second, },
      ])
    _ => DirMessage([])
  }
}

///|
/// The settings with a protocol of `protocols`, and a version and peers of
/// that protocol. Settings that fit stay as they are.
fn Settings::fit(self : Settings, protocols : Array[Protocol]) -> Settings {
  let protocol = match protocols.iter().find_first(p => p.id == self.protocol) {
    Some(p) => p
    None =>
      match protocols.get(0) {
        Some(p) => p
        None => return self
      }
  }
  let version = if protocol.versions.contains(self.version) {
    self.version
  } else {
    protocol.versions.get(0).unwrap_or("")
  }
  let preset : @samples.LogPreset = match self.preset {
    DirMessage([]) => default_preset(protocol)
    DirMessage(directions) =>
      if directions.all(d => protocol.peers.contains(d.peer)) {
        self.preset
      } else {
        default_preset(protocol)
      }
    Raw(sender~) =>
      if protocol.peers.contains(sender) {
        self.preset
      } else {
        Raw(sender=protocol.peers.get(0).unwrap_or(""))
      }
  }
  { ..self, protocol: protocol.id, version, preset, }
}

///|
/// The entries and the findings of a check. A log can have 20,000 entries,
/// and the page compares models after each message, so equality compares
/// `revision` only. Each change has a new revision: the number of the answer
/// that made it.
pub(all) struct Log {
  revision : Int32
  entries : Array[Entry]
  findings : Array[Finding]
  /// The number of entries that the checker has read.
  checked : Int32
  done : Bool
  summary : Summary?
} derive(Debug)

///|
pub impl Eq for Log with fn equal(self, other) {
  self.revision == other.revision
}

///|
pub extend Log with Eq::{equal, not_equal}

///|
pub extend Log with @debug.Debug::{to_repr}

///|
/// The log of the answer to a start.
pub fn Log::start(
  revision : Int32,
  entries : Array[Entry],
  findings : Array[Finding],
  checked : Int32,
  done : Bool,
  summary : Summary?,
) -> Log {
  { revision, entries, findings, checked, done, summary, }
}

///|
/// The log after the answer to a step, which gives the new findings only.
pub fn Log::add(
  self : Log,
  revision : Int32,
  findings : Array[Finding],
  checked : Int32,
  done : Bool,
  summary : Summary?,
) -> Log {
  {
    revision,
    entries: self.entries,
    findings: self.findings + findings,
    checked,
    done,
    summary,
  }
}

///|
/// The state of the Transcript tab.
pub(all) enum Checking {
  /// No check.
  TrIdle
  /// The check so far.
  TrChecked(Log)
  /// The Worker did not start the check, for the reason given.
  TrBlocked(reason~ : String, by~ : BlockedBy)
  /// The Worker did not answer in time and was replaced.
  TrStopped
  /// The Worker stopped with an error, given by the browser, and was replaced.
  TrFailed(String)
} derive(Eq, Debug)

///|
pub extend Checking with Eq::{equal, not_equal}

///|
pub extend Checking with @debug.Debug::{to_repr}

///|
/// A button of the Transcript tab that waits for the Worker.
pub(all) enum Action {
  StepAction
  RunAllAction
  ResetAction
} derive(Eq, Debug)

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
/// What the check still needs after the request that runs.
pub(all) enum Goal {
  NoGoal
  /// One entry: Step.
  OneStep
  /// Every entry, in groups: Run all.
  ToEnd
} derive(Eq, Debug)

///|
pub extend Goal with Eq::{equal, not_equal}

///|
pub extend Goal with @debug.Debug::{to_repr}

///|
/// A transcript request.
pub(all) enum TrRequest {
  Starting
  Stepping
  Resetting
} derive(Eq, Debug)

///|
pub extend TrRequest with Eq::{equal, not_equal}

///|
pub extend TrRequest with @debug.Debug::{to_repr}

///|
/// What the session of the Worker checks: the settings and the numbers of
/// changes to the model and the transcript when it started.
pub(all) struct Started {
  model_edits : Int32
  text_edits : Int32
  settings : Settings
} derive(Eq, Debug)

///|
pub extend Started with Eq::{equal, not_equal}

///|
pub extend Started with @debug.Debug::{to_repr}

///|
/// The number of entries that each request of Run all checks. A group is
/// small, so the list fills as the findings come, and the time limit of a
/// request is far away.
pub const RUN_GROUP : Int32 = 250

///|
/// The text and the language of the transcript that the page opens with.
pub fn Model::first_transcript(
  self : Model,
) -> (String, @samples.TranscriptFormat) {
  match self.data.transcripts.get(self.transcript) {
    Some(sample) => (sample.text, sample.format)
    None => ("", Markdown)
  }
}

///|
/// True when the session of the Worker checks the text and the settings of
/// the page.
pub fn Model::tr_current(self : Model) -> Bool {
  match self.session {
    Some(started) =>
      started.model_edits == self.edits &&
      started.text_edits == self.text_edits &&
      started.settings.same_check(self.settings)
    None => false
  }
}

///|
/// True while a Step or a Run all waits for the Worker or goes on.
pub fn Model::tr_running(self : Model) -> Bool {
  (
    self.waiting &&
    self.inflight == Transcribing &&
    self.tr_request != Resetting
  ) ||
  self.tr_pending is Some(StepAction | RunAllAction) ||
  self.goal != NoGoal
}

///|
fn Model::send_transcript(
  self : Model,
  request : TrRequest,
  effect : (Int32) -> Effect,
) -> (Model, Array[Effect]) {
  let seq = self.seq + 1
  (
    {
      ..self,
      seq,
      waiting: true,
      elapsed: 0,
      inflight: Transcribing,
      tr_request: request,
      tr_sent: {
        model_edits: self.edits,
        text_edits: self.text_edits,
        settings: self.settings,
      },
    },
    [
      effect(seq),
      Wait(ms=timeout_ms, then=TimedOut(seq~)),
      Wait(ms=TICK_MS, then=Ticked(seq~)),
    ],
  )
}

///|
fn Model::send_start(self : Model, goal : Goal) -> (Model, Array[Effect]) {
  { ..self, goal, }.send_transcript(Starting, seq => {
    SendTranscriptStart(seq~, settings=self.settings)
  })
}

///|
fn Model::send_step(self : Model, goal : Goal) -> (Model, Array[Effect]) {
  let count = if goal == ToEnd { RUN_GROUP } else { 1 }
  // A single step is the whole goal; Run all goes on to the end.
  let next = if goal == ToEnd { ToEnd } else { NoGoal }
  { ..self, goal: next, }.send_transcript(Stepping, seq => {
    SendTranscriptStep(seq~, count~)
  })
}

///|
/// True when the check of the session can go on: it is shown and not done.
fn Model::can_step(self : Model) -> Bool {
  self.session is Some(_) && self.tr is TrChecked(log) && !log.done
}

///|
/// True while a check of newer model text waits or runs: the wait after a
/// change, a pending check, or a check that the Worker runs.
fn Model::model_check_due(self : Model) -> Bool {
  self.edits != self.sent_edits ||
  self.pending ||
  (self.waiting && self.inflight == Validating)
}

///|
/// Run a button of the tab now; no request runs.
fn Model::act(self : Model, action : Action) -> (Model, Array[Effect]) {
  let m = { ..self, tr_pending: None, }
  match action {
    StepAction | RunAllAction => {
      let goal = if action == StepAction { OneStep } else { ToEnd }
      if m.tr_current() && m.tr is TrChecked(log) {
        if log.done {
          (m, [])
        } else {
          m.send_step(goal)
        }
      } else if m.model_check_due() {
        // A start waits for the check of the newest model text, so that its
        // settings fit the protocols of that model.
        ({ ..m, tr_pending: Some(action), }, [])
      } else {
        m.send_start(goal)
      }
    }
    ResetAction =>
      { ..m, tr: TrIdle, session: None, goal: NoGoal, }.send_transcript(
        Resetting,
        seq => SendTranscriptReset(seq~),
      )
  }
}

///|
/// A button of the tab: now, or after the request that runs.
fn Model::press(self : Model, action : Action) -> (Model, Array[Effect]) {
  if self.waiting {
    ({ ..self, tr_pending: Some(action), }, [])
  } else {
    self.act(action)
  }
}

///|
/// The answer to a transcript request.
fn Model::transcript_answer(
  self : Model,
  seq : Int32,
  answer : Answer,
) -> (Model, Array[Effect]) {
  // A Reset waits: the answer does not show.
  if self.tr_pending == Some(ResetAction) {
    return self.next([])
  }
  match (self.tr_request, answer) {
    (Resetting, _) => { ..self, tr: TrIdle, session: None, }.next([])
    (_, NotRun(reason, by)) =>
      { ..self, tr: TrBlocked(reason~, by~), session: None, goal: NoGoal, }.next([],
      )
    (Starting, Progressed(entries~, findings~, checked~, done~, summary~)) => {
      let log = Log::start(seq, entries, findings, checked, done, summary)
      {
        ..self,
        tr: TrChecked(log),
        session: Some(self.tr_sent),
        goal: if done {
          NoGoal
        } else {
          self.goal
        },
      }.next(follow(log))
    }
    (Stepping, Progressed(findings~, checked~, done~, summary~, ..)) =>
      match self.tr {
        TrChecked(log) => {
          let log = log.add(seq, findings, checked, done, summary)
          {
            ..self,
            tr: TrChecked(log),
            goal: if done {
              NoGoal
            } else {
              self.goal
            },
          }.next(follow(log))
        }
        _ => { ..self, goal: NoGoal, }.next([])
      }
    // An answer of another kind cannot come; the request ends.
    _ => { ..self, goal: NoGoal, }.next([])
  }
}

///|
/// Move the cursor of the transcript editor to the last checked entry.
fn follow(log : Log) -> Array[Effect] {
  match log.entries.get(log.checked - 1) {
    Some({ line: Some(line), .. }) => [FollowTranscript(line~)]
    _ => []
  }
}

///|
/// The model after a new Worker started: it has no session.
fn Model::lost_session(self : Model) -> Model {
  // A Step or a Run all that waits starts a new check; a Reset has nothing
  // to end.
  let pending = if self.tr_pending == Some(ResetAction) {
    None
  } else {
    self.tr_pending
  }
  { ..self, session: None, goal: NoGoal, tr_pending: pending, }
}

///|
/// The settings after a change, fitted to the protocols of the model.
fn Model::with_settings(self : Model, settings : Settings) -> Model {
  { ..self, settings: settings.fit(self.protocols), }
}

///|
/// The preset with `value` as the `dir` value of `peer`. The directions keep
/// the order of the peers; an empty value leaves the peer out.
fn Settings::with_direction(
  self : Settings,
  protocols : Array[Protocol],
  peer : String,
  value : String,
) -> Settings {
  guard self.preset is DirMessage(directions) else { return self }
  let peers = match protocols.iter().find_first(p => p.id == self.protocol) {
    Some(p) => p.peers
    None => directions.map(d => d.peer)
  }
  let out : Array[@samples.Direction] = []
  for name in peers {
    let text = if name == peer {
      value
    } else {
      match directions.iter().find_first(d => d.peer == name) {
        Some(d) => d.value
        None => ""
      }
    }
    if text != "" {
      out.push({ value: text, peer: name, })
    }
  }
  { ..self, preset: DirMessage(out), }
}

///|
/// The update of the messages of the Transcript tab.
fn transcript_update(m : Model, msg : Msg) -> (Model, Array[Effect]) {
  match msg {
    TranscriptSampleChosen(index) =>
      match m.data.transcripts.get(index) {
        Some(sample) =>
          // The settings fit the protocols of the model, so the picker,
          // the request and the hint agree.
          (
            { ..m, transcript: index, }.with_settings(
              Settings::of_sample(sample),
            ),
            [LoadTranscript(text=sample.text, format=sample.format)],
          )
        None => (m, [])
      }
    TranscriptEdited => ({ ..m, text_edits: m.text_edits + 1, }, [])
    ProtocolChosen(id) =>
      if m.protocols.iter().any(p => p.id == id) {
        (m.with_settings({ ..m.settings, protocol: id, }), [])
      } else {
        (m, [])
      }
    FormatChosen(format) =>
      (
        m.with_settings({ ..m.settings, format, }),
        [SetTranscriptLanguage(format)],
      )
    CompleteChosen(complete) =>
      ({ ..m, settings: { ..m.settings, complete, }, }, [])
    VersionChosen(version) =>
      match m.protocols.iter().find_first(p => p.id == m.settings.protocol) {
        Some(p) if p.versions.contains(version) =>
          ({ ..m, settings: { ..m.settings, version, }, }, [])
        _ => (m, [])
      }
    PresetChosen(kind) => {
      let preset : @samples.LogPreset = match kind {
        DirMessageLog => DirMessage([])
        RawLog => Raw(sender="")
      }
      (m.with_settings({ ..m.settings, preset, }), [])
    }
    DirectionEdited(peer~, value~) =>
      (
        { ..m, settings: m.settings.with_direction(m.protocols, peer, value), },
        [],
      )
    SenderChosen(sender) =>
      match m.settings.preset {
        Raw(_) => (m.with_settings({ ..m.settings, preset: Raw(sender~), }), [])
        _ => (m, [])
      }
    StepClicked => if m.tr_running() { (m, []) } else { m.press(StepAction) }
    RunAllClicked =>
      if m.tr_running() {
        (m, [])
      } else {
        m.press(RunAllAction)
      }
    ResetClicked => {
      let m = { ..m, tr: TrIdle, goal: NoGoal, }
      // The Worker can hold a session, or get one from the request that runs.
      let busy = m.waiting && m.inflight == Transcribing
      if busy {
        ({ ..m, tr_pending: Some(ResetAction), }, [])
      } else if m.session is None {
        ({ ..m, tr_pending: None, }, [])
      } else {
        m.press(ResetAction)
      }
    }
    // A line of older text can be another line now.
    EntryChosen(line~, column~) =>
      if m.tr_current() {
        (m, [GoToTranscript(line~, column~)])
      } else {
        (m, [])
      }
    _ => (m, [])
  }
}

///|
/// A row of the entry list: an entry, or a number of entries that the list
/// does not show.
pub(all) enum Row {
  Shown(Int32)
  Hidden(Int32)
} derive(Eq, Debug)

///|
pub extend Row with Eq::{equal, not_equal}

///|
pub extend Row with @debug.Debug::{to_repr}

///|
/// The most entries that the list shows. A longer transcript shows a window
/// near the last checked entry and the first entries with findings, so a log
/// of 20,000 lines does not stop the page.
pub const MAX_ENTRY_ROWS : Int32 = 200

///|
/// The number of entries of the window near the last checked entry.
pub const WINDOW_ROWS : Int32 = 150

///|
/// The most entries with findings that a long list shows out of the window.
pub const MARKED_ROWS : Int32 = 50

///|
/// The rows of a list of `total` entries, of which `checked` are checked and
/// `marked` (in order) have findings.
pub fn visible_rows(
  total : Int32,
  checked : Int32,
  marked : Array[Int32],
) -> Array[Row] {
  if total <= MAX_ENTRY_ROWS {
    return Array::makei(total, i => Shown(i))
  }
  let start = if checked > 100 { checked - 100 } else { 0 }
  let hi = if start + WINDOW_ROWS < total { start + WINDOW_ROWS } else { total }
  let lo = if hi > WINDOW_ROWS { hi - WINDOW_ROWS } else { 0 }
  let shown : Array[Int32] = []
  let mut taken = 0
  for i in marked {
    if taken >= MARKED_ROWS || i >= lo {
      break
    }
    if i >= 0 && (shown.is_empty() || shown[shown.length() - 1] < i) {
      shown.push(i)
      taken += 1
    }
  }
  for i in lo..<hi {
    shown.push(i)
  }
  for i in marked {
    if taken >= MARKED_ROWS {
      break
    }
    if i >= hi && i < total && shown[shown.length() - 1] < i {
      shown.push(i)
      taken += 1
    }
  }
  let rows = []
  let mut next = 0
  for i in shown {
    if i > next {
      rows.push(Hidden(i - next))
    }
    rows.push(Shown(i))
    next = i + 1
  }
  if next < total {
    rows.push(Hidden(total - next))
  }
  rows
}

///|
fn format_extension(format : @samples.TranscriptFormat) -> String {
  match format {
    Markdown => "md"
    Json => "json"
    Jsonl => "jsonl"
  }
}

///|
/// The text as one word of a POSIX shell: as it is when the shell leaves it
/// alone, else in single quotes (`shell_quote`).
fn shell_word(text : String) -> String {
  let plain = text != "" &&
    text
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      "#._-=/:@+,".contains_char(c)
    })
  if plain {
    text
  } else {
    shell_quote(text)
  }
}

///|
/// The CLI command that gives the same findings.
pub fn transcript_hint(settings : Settings) -> String {
  let parts = [
    "smithy validate rpc transcript --protocol \{shell_word(settings.protocol)}",
  ]
  if settings.complete {
    parts.push("--complete")
  }
  if settings.format == Jsonl {
    parts.push("--version \{shell_word(settings.version)}")
    match settings.preset {
      DirMessage(directions) => {
        parts.push("--log-preset dir-message")
        for d in directions {
          parts.push("--direction \{shell_word(d.value + "=" + d.peer)}")
        }
      }
      Raw(sender~) =>
        parts.push("--log-preset raw --sender \{shell_word(sender)}")
    }
  }
  parts.push("model.smithy transcript.\{format_extension(settings.format)}")
  parts.join(" ")
}

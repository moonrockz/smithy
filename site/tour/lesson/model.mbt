///|
/// The id of the element that the lesson component mounts in.
pub const APP_ID : String = "tour-app"

///|
/// The id of the element that the model editor mounts in.
pub const EDITOR_ID : String = "tour-editor"

///|
/// The id of the element that the output editor mounts in.
pub const OUTPUT_ID : String = "tour-output"

///|
/// The wait after an edit before the check, in milliseconds, as in the
/// playground.
pub const DEBOUNCE_MS : Int32 = 250

///|
/// The time that the Worker has for one request, in milliseconds, as in the
/// playground.
pub const TIMEOUT_MS : Int32 = 10000

///|
/// The text of the Findings and the output tabs after a request that did not
/// end in time, two times.
pub let timeout_text : String = "The check took more than \{TIMEOUT_MS / 1000} s, two times, so I stopped it. Edit the model to try again."

///|
/// The text next to Open in playground when the files do not fit in a link.
pub let too_large_text : String = "The model is too large for a link to the playground."

///|
/// A tab of the output pane.
pub(all) enum Pane {
  FindingsPane
  OutputPane
  /// The steps of a transcript lesson.
  TranscriptPane
} derive(Eq, Debug)

///|
pub extend Pane with Eq::{equal, not_equal}

///|
pub extend Pane with @debug.Debug::{to_repr}

///|
/// Which right-hand pane fills the column.
pub(all) enum Layout {
  /// The editor above the output.
  Split
  /// The editor fills the column; the output is hidden.
  EditorOnly
  /// The output fills the column; the editor is hidden.
  OutputOnly
} derive(Eq, Debug)

///|
pub extend Layout with Eq::{equal, not_equal}

///|
pub extend Layout with @debug.Debug::{to_repr}

///|
/// A right-hand pane that has an expand button.
pub(all) enum Expandable {
  EditorSide
  OutputSide
} derive(Eq, Debug)

///|
pub extend Expandable with Eq::{equal, not_equal}

///|
pub extend Expandable with @debug.Debug::{to_repr}

///|
/// The layout after the button of this pane: the pane fills the column, or,
/// when it did already, both panes show.
fn Layout::toggled(self : Layout, side : Expandable) -> Layout {
  match (side, self) {
    (EditorSide, EditorOnly) | (OutputSide, OutputOnly) => Split
    (EditorSide, _) => EditorOnly
    (OutputSide, _) => OutputOnly
  }
}

///|
/// The answer of the Worker to a request.
pub(all) enum Answer {
  /// The findings of the files.
  Checked(Array[@core.Diagnostic])
  /// The text of the output.
  Converted(String)
  /// The Worker did not run the request; the text says why.
  NotConverted(String)
  /// The state of the transcript check after a start or a step, as the
  /// Worker gives it: a start gives every entry, a step gives none; the
  /// findings are the new ones.
  Progress(
    entries~ : Array[@core.EntryView],
    findings~ : Array[@core.FindingView],
    checked~ : Int32,
    done~ : Bool,
    summary~ : @core.SummaryView?
  )
} derive(Eq, Debug)

///|
pub extend Answer with Eq::{equal, not_equal}

///|
pub extend Answer with @debug.Debug::{to_repr}

///|
pub(all) enum Msg {
  /// The full text of the file that the editor shows. The editor also sends
  /// it after `LoadEditor`; the same text changes nothing.
  Edited(String)
  /// The wait after the edit with this number ended.
  Debounced(Int32)
  SelectFile(Int32)
  SelectPane(Pane)
  Answered(seq~ : Int32, answer~ : Answer)
  /// The time for the request with this number ended.
  TimedOut(Int32)
  Reset
  OpenPlayground
  /// The reader pressed the expand button of a pane.
  ToggleExpand(Expandable)
  /// The reader pressed Step: check one more entry of the transcript.
  StepClicked
  /// The reader pressed Run all: check the rest of the entries.
  RunAllClicked
} derive(Eq, Debug)

///|
pub extend Msg with Eq::{equal, not_equal}

///|
pub extend Msg with @debug.Debug::{to_repr}

///|
/// What the page must do after an update.
pub(all) enum Effect {
  /// Send the files, as (name, text), to the Worker for a check.
  SendValidate(seq~ : Int32, files~ : Array[(String, String)])
  /// Send the files to the Worker for the output of the lesson.
  SendTransform(
    seq~ : Int32,
    files~ : Array[(String, String)],
    output~ : @samples.Output,
    selector~ : String?
  )
  /// Send the model files and the text of the transcript to the Worker, which
  /// loads the transcript and checks its first entries.
  SendTranscriptStart(
    seq~ : Int32,
    files~ : Array[(String, String)],
    protocol~ : String,
    text~ : String
  )
  /// Check the next `count` entries of the transcript that the Worker holds.
  SendTranscriptStep(seq~ : Int32, count~ : Int32)
  /// Send `msg` after `ms` milliseconds.
  Wait(ms~ : Int32, msg~ : Msg)
  /// Put this text, of the selected file `file`, in the model editor, in
  /// `language`. The editor keeps the text, cursor and undo history of each
  /// file apart, so a switch to a file gives its state back and Undo never
  /// crosses files. With `fresh`, every file starts with a new state (start
  /// and Reset).
  LoadEditor(text~ : String, file~ : String, fresh~ : Bool, language~ : String)
  /// Put this text in the output editor and highlight these lines, from 1.
  /// An empty list removes the highlight.
  ShowOutput(text~ : String, highlight~ : Array[Int32])
  /// Show these findings, of the selected file, in the model editor.
  Mark(items~ : Array[@core.Diagnostic])
  /// Keep the value in localStorage under the key.
  Store(key~ : String, value~ : String)
  /// Remove the key from localStorage.
  Clear(key~ : String)
  /// Open this URL in the tab.
  Navigate(url~ : String)
  /// End the Worker and start a new one.
  RestartWorker
  /// Make the editors measure their elements again, after a change of layout.
  Remeasure
} derive(Eq, Debug)

///|
pub extend Effect with Eq::{equal, not_equal}

///|
pub extend Effect with @debug.Debug::{to_repr}

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
/// The state of the Findings tab.
pub(all) enum Findings {
  /// No answer yet.
  Unchecked
  Found(Array[@core.Diagnostic])
  /// The check did not run; the text says why.
  NotChecked(String)
} derive(Eq, Debug)

///|
pub extend Findings with Eq::{equal, not_equal}

///|
pub extend Findings with @debug.Debug::{to_repr}

///|
/// The state of the output tab.
pub(all) enum Output {
  /// No output yet.
  NoOutput
  /// The output, and its lines that changed since the output before it.
  Shown(text~ : String, highlight~ : Array[Int32])
  /// The output did not run; the text says why.
  NotShown(String)
} derive(Eq, Debug)

///|
pub extend Output with Eq::{equal, not_equal}

///|
pub extend Output with @debug.Debug::{to_repr}

///|
/// The number of characters of a message that the Transcript tab shows.
pub const MESSAGE_CHARS : Int32 = 120

///|
/// The state of the Transcript tab: the entries of the transcript, the
/// findings so far and the position of the check.
pub(all) struct Transcript {
  entries : Array[@core.EntryView]
  findings : Array[@core.FindingView]
  checked : Int32
  done : Bool
  summary : @core.SummaryView?
  /// The number of entries that the reader asked to check. An edit keeps it.
  wanted : Int32
  /// The CLI lines before the last edit; a line that is not in them is
  /// highlighted. `None`: no highlight.
  before : Array[String]?
} derive(Eq, Debug)

///|
pub extend Transcript with Eq::{equal, not_equal}

///|
pub extend Transcript with @debug.Debug::{to_repr}

///|
/// The lines that `smithy validate rpc transcript` writes for the findings of
/// the transcript in `file`: the line of each finding, then the lines of the
/// `expect` list.
pub fn transcript_lines(t : Transcript, file : String) -> Array[String] {
  let lines = t.findings.map(f => f.cli_line(file~))
  match t.summary {
    Some({ expectations: Some(expectations), .. }) =>
      lines.append(expectations.cli_lines(file~))
    _ => ()
  }
  lines
}

///|
/// True when the check reached the position that the reader asked for, or
/// the end of the transcript.
fn Transcript::reached(self : Transcript) -> Bool {
  self.done || self.checked >= self.wanted
}

///|
/// The lines of the transcript that the page highlights: the lines that are
/// not in the lines before the last edit, once the check reached its
/// position.
pub fn Transcript::changed_lines(
  self : Transcript,
  file : String,
) -> Array[String] {
  match self.before {
    Some(before) if self.reached() =>
      transcript_lines(self, file).filter(line => !before.contains(line))
    _ => []
  }
}

///|
pub(all) struct Model {
  page : @model.LessonPage
  /// The files as the reader edited them, in the order of the starting files.
  files : Array[@model.LessonFile]
  /// The index of the file that the editor shows.
  selected : Int32
  pane : Pane
  layout : Layout
  /// True when the reader selected a tab of the output pane. Then the
  /// lesson does not change the tab.
  chosen : Bool
  /// The number of edits so far.
  edits : Int32
  /// The number of the newest request; each request has a new one.
  seq : Int32
  /// The value of `edits` when the newest request was sent.
  sent_edits : Int32
  /// True while the newest request has no answer.
  waiting : Bool
  /// The kind of the newest request.
  inflight : Kind
  /// True when the wait of an edit ended while a request ran. The newest
  /// files go to the Worker when that request ends.
  pending : Bool
  /// True when the newest request is the second try after a timeout.
  retried : Bool
  findings : Findings
  output : Output
  /// The Transcript tab of a transcript lesson; `None` before the first
  /// answer and while the transcript did not run.
  transcript : Transcript?
  /// Why the transcript did not run, until the next answer.
  not_run : String?
  /// True when the newest transcript request is a step, not a start.
  stepping : Bool
  /// Why Open in playground did not open the model, until the next edit.
  link_problem : String?
} derive(Eq, Debug)

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with @debug.Debug::{to_repr}

///|
/// The edits of a lesson in localStorage, with the digest of the starting
/// files that they come from.
priv struct Stored {
  digest : String
  files : Array[(String, String)]
} derive(ToJson, FromJson)

///|
fn pairs(files : Array[@model.LessonFile]) -> Array[(String, String)] {
  files.map(f => (f.name, f.text))
}

///|
/// The files that the Worker loads as the model: all files without the query
/// file and the data files of the engine.
fn model_pairs(model : Model) -> Array[(String, String)] {
  pairs(@model.model_files(model.page.engine, model.files))
}

///|
/// The language of the editor for a file: `.smithy` is IDL, `.json` is JSON,
/// every other name (the query file) is plain text.
fn editor_language(name : String) -> String {
  if name.has_suffix(".smithy") {
    "smithy"
  } else if name.has_suffix(".json") {
    "json"
  } else {
    "text"
  }
}

///|
/// The stored files, when they come from these starting files: the same
/// digest and the same file names in the same order. Else `None`.
fn stored_files(
  page : @model.LessonPage,
  value : String,
) -> Array[@model.LessonFile]? {
  let stored : Stored = @json.from_json(@json.parse(value)) catch {
    _ => return None
  }
  guard stored.digest == page.digest &&
    stored.files.map(f => f.0) == page.files.map(f => f.name) else {
    return None
  }
  Some(stored.files.map(f => { name: f.0, text: f.1, }))
}

///|
/// The model of a lesson page and its first effects. `stored` is the value
/// of `page.storage_key` in localStorage. Stored edits of other starting
/// files are cleared, and the lesson starts from its starting files.
pub fn Model::start(
  page : @model.LessonPage,
  stored : String?,
) -> (Model, Array[Effect]) {
  let (files, effects) = match stored {
    None => (page.files, [])
    Some(value) =>
      match stored_files(page, value) {
        Some(files) => (files, [])
        None => (page.files, [Clear(key=page.storage_key)])
      }
  }
  let m = {
    page,
    files,
    selected: 0,
    pane: if page.engine is Transcript(_) {
      TranscriptPane
    } else if page.output is Some(_) {
      OutputPane
    } else {
      FindingsPane
    },
    layout: Split,
    chosen: false,
    edits: 0,
    seq: 0,
    sent_edits: 0,
    waiting: false,
    inflight: Validating,
    pending: false,
    retried: false,
    findings: Unchecked,
    output: NoOutput,
    transcript: None,
    not_run: None,
    stepping: false,
    link_problem: None,
  }
  let (m, sent) = m.send_validate()
  (m, [..effects, m.load_selected(fresh=true), ..sent])
}

///|
/// The name of the file that the editor shows.
pub fn Model::selected_name(self : Model) -> String {
  match self.files.get(self.selected) {
    Some(file) => file.name
    None => ""
  }
}

///|
/// The effect that puts the selected file in the editor. With `fresh`, every
/// file starts with a new editor state.
fn Model::load_selected(self : Model, fresh~ : Bool) -> Effect {
  let name = self.selected_name()
  LoadEditor(
    text=self.selected_text(),
    file=name,
    fresh~,
    language=editor_language(name),
  )
}

///|
/// The text of the file that the editor shows.
pub fn Model::selected_text(self : Model) -> String {
  match self.files.get(self.selected) {
    Some(file) => file.text
    None => ""
  }
}

///|
/// The findings of the file that the editor shows.
fn Model::selected_findings(self : Model) -> Array[@core.Diagnostic] {
  match (self.findings, self.files.get(self.selected)) {
    (Found(items), Some(file)) => items.filter(d => d.file == file.name)
    _ => []
  }
}

///|
/// True while a check of newer files than the result on the page runs or
/// comes.
pub fn Model::busy(self : Model) -> Bool {
  self.waiting || self.pending || self.edits != self.sent_edits
}

///|
/// The value to store for the files: the digest of the starting files and
/// the files.
fn Model::stored_value(self : Model) -> String {
  let stored : Stored = { digest: self.page.digest, files: pairs(self.files), }
  ToJson::to_json(stored).stringify()
}

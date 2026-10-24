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
  /// Send `msg` after `ms` milliseconds.
  Wait(ms~ : Int32, msg~ : Msg)
  /// Put this text, of the selected file, in the model editor (Smithy mode).
  LoadEditor(text~ : String)
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
    pane: if page.output is Some(_) {
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
    link_problem: None,
  }
  let (m, sent) = m.send_validate()
  (m, [..effects, LoadEditor(text=m.selected_text()), ..sent])
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

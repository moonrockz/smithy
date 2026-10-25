///|
/// One file of a lesson: the editor tab name and the text.
pub(all) struct LessonFile {
  name : String
  text : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LessonFile with Eq::{equal, not_equal}

///|
pub extend LessonFile with @debug.Debug::{to_repr}

///|
pub extend LessonFile with ToJson::{to_json}

///|
pub extend LessonFile with FromJson::{from_json}

///|
/// What a case must show: the complete list of its compared findings, and
/// strings that must each be a substring of the output text.
pub(all) struct Expectation {
  events : Array[EventKey]
  output_contains : Array[String]
  /// A text that the reason of a blocked output must contain. The output must
  /// be blocked for a reason other than model errors (`BlockKind::Other`).
  blocked : String?
  /// The finding keys of a value or message lesson: `found_key` and
  /// `stopped_key`. Empty for other lessons.
  findings : Array[String]
  /// The diff event keys of a diff lesson. Empty for other lessons.
  diff : Array[String]
  /// The verdict of the summary of a transcript lesson; `None` leaves it
  /// unchecked. `None` for other lessons.
  valid : Bool?
  /// The findings of a transcript lesson after Step is clicked `count` times
  /// from the start. Empty for other lessons.
  steps : Array[StepExpectation]
}

///|
/// The transcript finding keys (`transcript_key`) that a check shows after
/// `count` entries from the start, in any order.
pub(all) struct StepExpectation {
  count : Int32
  findings : Array[String]
} derive(Eq, Debug)

///|
pub extend StepExpectation with Eq::{equal, not_equal}

///|
pub extend StepExpectation with @debug.Debug::{to_repr}

///|
/// What a lesson runs on its files. A lesson has one engine.
pub(all) enum Engine {
  /// Validate the model files; `Lesson.output` names the transform, if any.
  Model
  /// Check a JSON value against a shape of the model.
  Value(ValueSetup)
  /// Check a JSON-RPC message against a service of the model.
  Message(MessageSetup)
  /// Compare the models in `old/` and `new/`, as `smithy diff` does.
  Diff
  /// Step through a JSON-RPC transcript against a protocol of the model.
  Transcript(TranscriptSetup)
  /// No editor, no files and no cases: the blocks of the text come from
  /// include blocks.
  Static
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Engine with Eq::{equal, not_equal}

///|
pub extend Engine with @debug.Debug::{to_repr}

///|
pub extend Engine with ToJson::{to_json}

///|
pub extend Engine with FromJson::{from_json}

///|
/// The setup of a value lesson: the starting file with the value, the absolute
/// ID of the target shape and the options of `smithy validate value`.
pub(all) struct ValueSetup {
  file : String
  shape : String
  options : @samples.ValueOptions
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend ValueSetup with Eq::{equal, not_equal}

///|
pub extend ValueSetup with @debug.Debug::{to_repr}

///|
pub extend ValueSetup with ToJson::{to_json}

///|
pub extend ValueSetup with FromJson::{from_json}

///|
/// The setup of a message lesson: the starting file with the message, the
/// absolute ID of the service, the JSON-RPC version, what the message is and
/// the options of `smithy validate rpc`.
pub(all) struct MessageSetup {
  file : String
  service : String
  version : @samples.RpcVersion
  role : MessageRole
  options : @samples.ValueOptions
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend MessageSetup with Eq::{equal, not_equal}

///|
pub extend MessageSetup with @debug.Debug::{to_repr}

///|
pub extend MessageSetup with ToJson::{to_json}

///|
pub extend MessageSetup with FromJson::{from_json}

///|
/// What the message of a message lesson is: a request, or a response with the
/// options `--method`, `--operation`, `--request`, `--envelope-only` and
/// `--legacy-errors`.
pub(all) enum MessageRole {
  Request
  Response(context~ : LessonContext?, legacy_errors~ : @samples.LegacyErrors)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend MessageRole with Eq::{equal, not_equal}

///|
pub extend MessageRole with @debug.Debug::{to_repr}

///|
pub extend MessageRole with ToJson::{to_json}

///|
pub extend MessageRole with FromJson::{from_json}

///|
/// What a response lesson knows of the call: `RequestFile` names a starting
/// file that holds the request. The check gets the text of that file.
pub(all) enum LessonContext {
  Method(String)
  Operation(String)
  RequestFile(String)
  EnvelopeOnly
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LessonContext with Eq::{equal, not_equal}

///|
pub extend LessonContext with @debug.Debug::{to_repr}

///|
pub extend LessonContext with ToJson::{to_json}

///|
pub extend LessonContext with FromJson::{from_json}

///|
/// The kind of the message check for `files` (the files of the lesson or of a
/// case): a `RequestFile` becomes the text of that file. The reader makes sure
/// that the lesson has the file; a case that deletes it has an empty request.
/// JSON-RPC 2.0 has no legacy errors, and the CLI rejects the option there, so
/// the check gets no value for it.
pub fn MessageSetup::message_kind(
  self : MessageSetup,
  files : Array[LessonFile],
) -> @samples.MessageKind {
  match self.role {
    Request => RequestMessage
    Response(context~, legacy_errors~) => {
      let context : @samples.ResponseContext? = match context {
        None => None
        Some(Method(name)) => Some(Method(name))
        Some(Operation(id)) => Some(Operation(id))
        Some(EnvelopeOnly) => Some(@samples.ResponseContext::EnvelopeOnly)
        Some(RequestFile(name)) =>
          Some(
            OriginalRequest(
              match files.search_by(f => f.name == name) {
                Some(i) => files[i].text
                None => ""
              },
            ),
          )
      }
      let legacy_errors = match self.version {
        V1_0 => Some(legacy_errors)
        V2_0 => None
      }
      ResponseMessage(context~, legacy_errors~)
    }
  }
}

///|
/// The setup of a transcript lesson: the starting file with the transcript
/// (a `.json` document) and the absolute ID of the protocol shape.
pub(all) struct TranscriptSetup {
  file : String
  protocol : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TranscriptSetup with Eq::{equal, not_equal}

///|
pub extend TranscriptSetup with @debug.Debug::{to_repr}

///|
pub extend TranscriptSetup with ToJson::{to_json}

///|
pub extend TranscriptSetup with FromJson::{from_json}

///|
/// The names of the files that hold data in place of a model.
pub fn Engine::data_files(self : Engine) -> Array[String] {
  match self {
    Model => []
    Value(setup) => [setup.file]
    Transcript(setup) => [setup.file]
    Message(setup) =>
      match setup.role {
        Response(context=Some(RequestFile(name)), ..) => [setup.file, name]
        _ => [setup.file]
      }
    Diff | Static => []
  }
}

///|
/// True for the query file of a Selector lesson: a name that ends with
/// ".selector".
pub fn is_query_file(name : String) -> Bool {
  name.has_suffix(".selector")
}

///|
/// The files of the model: the files without the data files of the engine and
/// without the query file of a Selector lesson, in the same order.
pub fn model_files(
  engine : Engine,
  files : Array[LessonFile],
) -> Array[LessonFile] {
  let data = engine.data_files()
  files.filter(f => !data.contains(f.name) && !is_query_file(f.name))
}

///|
/// The selector for `files`: the text of the query file, else `fixed` (the
/// "selector" of `lesson.json`).
pub fn query_of(files : Array[LessonFile], fixed~ : String?) -> String? {
  for file in files {
    if is_query_file(file.name) {
      return Some(file.text)
    }
  }
  fixed
}

///|
/// The folder of the old model in the files of a diff lesson, and the prefix of
/// the names of its files.
pub let old_prefix : String = "old/"

///|
/// The folder of the new model, as `old_prefix`.
pub let new_prefix : String = "new/"

///|
/// The files of the old and of the new model of a diff lesson, by the prefix
/// `old/` and `new/`. The names keep their prefix, in the same order. A file
/// with another prefix is in neither list: the reader (`read_sides`) accepts
/// only these two folders, and a test checks that every file of a diff lesson
/// is in one of them.
pub fn sides(
  files : Array[LessonFile],
) -> (Array[LessonFile], Array[LessonFile]) {
  (
    files.filter(f => f.name.has_prefix(old_prefix)),
    files.filter(f => f.name.has_prefix(new_prefix)),
  )
}

///|
/// Whether the text is the severity of a diff event that a lesson can claim.
/// SUPPRESSED events are not shown, so no lesson claims them.
pub fn is_diff_severity(s : String) -> Bool {
  s == "NOTE" || s == "WARNING" || s == "DANGER" || s == "ERROR"
}

///|
/// Whether the text has the form `id|SEVERITY|shape` of a diff key, with `-`
/// for no shape.
pub fn is_diff_key(key : String) -> Bool {
  guard key.split("|").map(p => p.to_owned()).to_array()
    is [id, severity, shape] else {
    return false
  }
  id != "" && shape != "" && is_diff_severity(severity)
}

///|
/// The key of a diff event: `id|SEVERITY|shape`, with `-` for no shape.
pub fn diff_key(id : String, severity : String, shape : String?) -> String {
  "\{id}|\{severity}|\{shape.unwrap_or("-")}"
}

///|
/// The key of a `Found` finding: `code|severity|path|shape`. The path is the
/// JSON pointer, empty for the root.
pub fn found_key(
  code : String,
  severity : String,
  path : String,
  shape : String,
) -> String {
  "\{code}|\{severity}|\{path}|\{shape}"
}

///|
/// The key of a `Stopped` finding: `code|stopped|source`, with `-` for the
/// input file.
pub fn stopped_key(code : String, source : String?) -> String {
  "\{code}|stopped|\{source.unwrap_or("-")}"
}

///|
/// Whether the text has the form of a finding key: a `Found` key has 4 or more
/// parts (a pointer can hold `|`) with `error` or `advisory` as part 2; a
/// `Stopped` key has 3 parts with `stopped` as part 2.
pub fn is_finding_key(key : String) -> Bool {
  let parts = key.split("|").map(p => p.to_owned()).to_array()
  if parts.length() < 3 || parts[0] == "" {
    return false
  }
  if parts[1] == "stopped" {
    return parts.length() == 3 && parts[2] != ""
  }
  parts.length() >= 4 &&
  (parts[1] == "error" || parts[1] == "advisory") &&
  parts[parts.length() - 1] != ""
}

///|
/// The key of a transcript finding: `code|severity|entry|sender`, with `-` for
/// no entry or no sender.
pub fn transcript_key(
  code : String,
  severity : String,
  entry : Int32?,
  sender : String?,
) -> String {
  "\{code}|\{severity}|\{entry.map(n => n.to_string()).unwrap_or("-")}|\{sender.unwrap_or("-")}"
}

///|
/// Whether the text has the form of `transcript_key`: the severity is `error`
/// or `advisory`, and the entry is a number or `-`.
pub fn is_transcript_key(key : String) -> Bool {
  guard key.split("|").map(p => p.to_owned()).to_array()
    is [code, severity, entry, sender] &&
    code != "" &&
    sender != "" &&
    (severity == "error" || severity == "advisory") else {
    return false
  }
  entry == "-" ||
  (entry != "" && entry.to_array().iter().all(c => c.is_ascii_digit()))
}

///|
/// The note that a value or message lesson must have in its text: Smithy
/// defines no such check.
pub let extension_note : String = "> **Our extension:**"

///|
/// Whether the text of the lesson must hold `extension_note`.
pub fn Lesson::needs_extension_note(self : Lesson) -> Bool {
  match self.engine {
    Model => false
    Value(_) | Message(_) | Transcript(_) => true
    // Smithy has a diff tool: the lesson shows its events.
    Diff => false
    Static => self.extension
  }
}

///|
/// A named edit of the starting files, and the result that it must give.
pub(all) struct Case {
  name : String
  files : Array[LessonFile]
  expect : Expectation
}

///|
pub(all) struct Lesson {
  dir : String
  number : Int32
  slug : String
  title : String
  section : String
  engine : Engine
  /// Whether the text must say that the lesson shows a feature of Smithy in
  /// MoonBit, not of Smithy. Set in `lesson.json` of a static lesson; a value
  /// lesson always says it.
  extension : Bool
  output : @samples.Output?
  selector : String?
  spec : String
  text : String
  files : Array[LessonFile]
  cases : Array[Case]
}

///|
/// Whether the lesson has an editor and an output. A static lesson has none.
pub fn Lesson::is_static(self : Lesson) -> Bool {
  self.engine is Static
}

///|
/// The lessons, sorted by number.
pub(all) struct Tour {
  lessons : Array[Lesson]
}

///|
/// The contents: consecutive lessons with the same section form one section.
pub fn Tour::sections(self : Tour) -> Array[(String, Array[Lesson])] {
  let result : Array[(String, Array[Lesson])] = []
  for lesson in self.lessons {
    let last = result.length() - 1
    if last >= 0 && result[last].0 == lesson.section {
      result[last].1.push(lesson)
    } else {
      result.push((lesson.section, [lesson]))
    }
  }
  result
}

///|
pub fn Tour::find(self : Tour, slug : String) -> Lesson? {
  self.lessons.search_by(l => l.slug == slug).map(i => self.lessons[i])
}

///|
/// The previous and the next lesson.
pub fn Tour::neighbours(self : Tour, lesson : Lesson) -> (Lesson?, Lesson?) {
  match self.lessons.search_by(l => l.number == lesson.number) {
    None => (None, None)
    Some(i) =>
      (
        if i > 0 {
          Some(self.lessons[i - 1])
        } else {
          None
        },
        if i + 1 < self.lessons.length() {
          Some(self.lessons[i + 1])
        } else {
          None
        },
      )
  }
}

///|
/// The starting files, replaced or added by name, sorted by name.
pub fn Lesson::case_files(self : Lesson, case : Case) -> Array[LessonFile] {
  let merged : Array[LessonFile] = []
  for file in self.files {
    merged.push(file)
  }
  for file in case.files {
    match merged.search_by(f => f.name == file.name) {
      Some(i) => merged[i] = file
      None => merged.push(file)
    }
  }
  merged.sort_by(fn(a, b) { compare_code_units(a.name, b.name) })
  merged
}

///|
/// SHA-256 as lower-case hex, over the files sorted by name, of
/// `name + "\u0000" + text + "\u0000"` in UTF-8.
pub fn digest(files : Array[LessonFile]) -> String {
  let sorted = files.copy()
  sorted.sort_by(fn(a, b) { compare_code_units(a.name, b.name) })
  let buf = StringBuilder()
  for file in sorted {
    buf.write_string(file.name)
    buf.write_char('\u0000')
    buf.write_string(file.text)
    buf.write_char('\u0000')
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(buf.to_string())))
}

///|
/// The output of a transform as one text, as the lesson page shows it and as
/// `output_contains` reads it: one file as it is; several files, as (name,
/// text), joined with a line break in their order.
pub fn output_text(files : Array[(String, String)]) -> String {
  if files is [(_, text)] {
    return text
  }
  files.map(file => file.1).join("\n")
}

///|
/// The severity of a finding that the tour compares. The tour does not
/// compare NOTE and SUPPRESSED findings.
pub(all) enum Severity {
  Warning
  Danger
  Error
} derive(Eq, Debug)

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
/// The severity of a name such as `WARNING`, or `None` for a severity that
/// the tour does not compare.
pub fn Severity::parse(name : String) -> Severity? {
  [Warning, Danger, Error].iter().find_first(s => s.name() == name)
}

///|
/// The name of the severity, as Smithy writes it.
pub fn Severity::name(self : Severity) -> String {
  match self {
    Warning => "WARNING"
    Danger => "DANGER"
    Error => "ERROR"
  }
}

///|
/// Whether a finding of this severity stops the output. The playground core
/// does not transform a model with an ERROR or a DANGER (`is_error_event` in
/// `playground/core/model.mbt`), and the reference harness does the same
/// (`blocked` in `scripts/reference-tour.mbtx`).
pub fn Severity::blocks_output(self : Severity) -> Bool {
  match self {
    Warning => false
    Danger | Error => true
  }
}

///|
/// A compared finding: its id, its severity and its shape.
pub(all) struct EventKey {
  id : String
  severity : Severity
  shape : String?
} derive(Eq, Debug)

///|
pub extend EventKey with Eq::{equal, not_equal}

///|
pub extend EventKey with @debug.Debug::{to_repr}

///|
/// The key of a finding, or `None` when the tour does not compare its
/// severity.
pub fn EventKey::of_finding(
  id : String,
  severity : String,
  shape : String?,
) -> EventKey? {
  Severity::parse(severity).map(severity => { id, severity, shape, })
}

///|
/// The key of the text `id|SEVERITY|shape`, with `-` for no shape. `None`
/// when the text has another form or a severity that the tour does not
/// compare.
pub fn EventKey::parse(text : String) -> EventKey? {
  guard text.split("|").map(p => p.to_owned()).to_array()
    is [id, severity, shape] &&
    id != "" &&
    shape != "" &&
    Severity::parse(severity) is Some(severity) else {
    return None
  }
  Some({ id, severity, shape: if shape == "-" { None } else { Some(shape) }, })
}

///|
/// The text `id|SEVERITY|shape`, as `expect.json` and the reference results
/// write it.
pub fn EventKey::to_string(self : EventKey) -> String {
  self.id + "|" + self.severity.name() + "|" + self.shape.unwrap_or("-")
}

///|
/// The order of the event keys: their texts in code unit order.
pub fn compare_events(a : EventKey, b : EventKey) -> Int32 {
  compare_code_units(a.to_string(), b.to_string())
}

///|
/// The id of a case: the folder of its lesson and the name of the case.
pub(all) struct CaseId {
  dir : String
  name : String
} derive(Eq, Hash, Debug)

///|
pub extend CaseId with Eq::{equal, not_equal}

///|
pub extend CaseId with Hash::{hash_combine}

///|
pub extend CaseId with @debug.Debug::{to_repr}

///|
/// The id of the text `<dir>/<name>`, or `None` for another form.
pub fn CaseId::parse(text : String) -> CaseId? {
  guard text.split("/").map(p => p.to_owned()).to_array() is [dir, name] &&
    dir != "" &&
    name != "" else {
    return None
  }
  Some({ dir, name, })
}

///|
/// The text `<dir>/<name>`, as the reference results and the allow list
/// write it.
pub fn CaseId::to_string(self : CaseId) -> String {
  self.dir + "/" + self.name
}

///|
/// The id of a case of this lesson.
pub fn Lesson::case_id(self : Lesson, case : Case) -> CaseId {
  { dir: self.dir, name: case.name, }
}

///|
/// Order by UTF-16 code unit, then by length (`@samples.compare_code_units`).
/// `String::compare` orders by length first, so the digest and the file order
/// cannot use it.
pub using @samples {compare_code_units}

///|
/// The folder of a lesson: its number in two digits, `-`, and its slug.
pub fn lesson_dir(number : Int32, slug : String) -> String {
  let digits = if number < 10 { "0\{number}" } else { "\{number}" }
  "\{digits}-\{slug}"
}

///|
/// A `spec` that starts with this is a link to the Smithy specification.
pub let spec_url_prefix : String = "https://smithy.io/"

///|
/// The repository path of the lessons folder.
pub let lessons_root : String = "site/tour/lessons"

///|
/// The repository path of the text of a lesson.
pub fn lesson_source(number : Int32, slug : String) -> String {
  "\{lessons_root}/\{lesson_dir(number, slug)}/lesson.md"
}

///|
/// The slug of the lesson whose text is at the repository path `path`, or
/// `None` when `path` is not the text of a lesson.
pub fn slug_of_source(path : String) -> String? {
  let prefix = lessons_root + "/"
  let suffix = "/lesson.md"
  guard path.length() > prefix.length() + suffix.length() &&
    path.has_prefix(prefix) &&
    path.has_suffix(suffix) else {
    return None
  }
  let dir = path[prefix.length():path.length() - suffix.length()].to_owned()
  let chars = dir.to_array()
  if chars.length() < 4 ||
    !(chars[0].is_ascii_digit() && chars[1].is_ascii_digit()) ||
    chars[2] != '-' ||
    dir.contains("/") {
    return None
  }
  Some(dir[3:].to_owned())
}

///|
/// A link to a lesson.
pub(all) struct LessonLink {
  slug : String
  title : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LessonLink with Eq::{equal, not_equal}

///|
pub extend LessonLink with @debug.Debug::{to_repr}

///|
pub extend LessonLink with ToJson::{to_json}

///|
pub extend LessonLink with FromJson::{from_json}

///|
/// What the page of one lesson needs: the pre-render writes it in the site
/// data, and the lesson component starts from it.
pub(all) struct LessonPage {
  slug : String
  title : String
  section : String
  /// The place of the lesson in the tour, from 1, and the number of lessons.
  number : Int32
  total : Int32
  /// What the lesson runs. A static lesson has no editor and no output.
  engine : Engine
  output : @samples.Output?
  selector : String?
  /// The smithy.io section that the lesson teaches.
  spec : String
  /// The starting files.
  files : Array[LessonFile]
  /// The `digest` of the starting files. Stored edits of other files are stale.
  digest : String
  previous : LessonLink?
  next : LessonLink?
  /// The versioned URL of the playground Worker.
  worker : String
  /// The localStorage key of the edits: `smithy-tour:<channel>:<slug>`. The
  /// channels share an origin, so the key holds the channel.
  storage_key : String
  /// The href of the playground page; `None` when the lesson has more than
  /// one file, because the playground holds one model.
  playground : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Whether the page is a static lesson: it has no editor and no output.
pub fn LessonPage::is_static(self : LessonPage) -> Bool {
  self.engine is Static
}

///|
pub extend LessonPage with Eq::{equal, not_equal}

///|
pub extend LessonPage with @debug.Debug::{to_repr}

///|
pub extend LessonPage with ToJson::{to_json}

///|
pub extend LessonPage with FromJson::{from_json}

///|
/// The contents: the sections in order, each with its lessons in order.
pub(all) struct TourContents {
  sections : Array[(String, Array[LessonLink])]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TourContents with Eq::{equal, not_equal}

///|
pub extend TourContents with @debug.Debug::{to_repr}

///|
pub extend TourContents with ToJson::{to_json}

///|
pub extend TourContents with FromJson::{from_json}

///|
/// The data of a tour page: the contents, or one lesson.
pub(all) enum TourPage {
  Contents(TourContents)
  Page(LessonPage)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TourPage with Eq::{equal, not_equal}

///|
pub extend TourPage with @debug.Debug::{to_repr}

///|
pub extend TourPage with ToJson::{to_json}

///|
pub extend TourPage with FromJson::{from_json}

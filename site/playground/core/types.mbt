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
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The encoding of the transcript text.
pub(all) enum TranscriptFormat {
  Markdown
  Json
  Jsonl
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A message from the page to the Worker. `seq` comes back unchanged in the
/// response, so the page can drop a stale response.
pub(all) enum Request {
  Validate(seq~ : Int32, model~ : String)
  Transform(
    seq~ : Int32,
    model~ : String,
    output~ : Output,
    selector~ : String?
  )
  /// Load a transcript and check its first entries. `log_preset` applies to
  /// the format Jsonl only: `None` or "dir-message" (request is the first peer,
  /// response the second), "dir-message:value=peer,value=peer", or "raw:peer".
  /// `complete` is the flag --complete of the CLI: true makes the check complete.
  /// False leaves the choice to the document, and a document that says nothing
  /// is partial.
  TranscriptStart(
    seq~ : Int32,
    model~ : String,
    protocol~ : String,
    format~ : TranscriptFormat,
    complete~ : Bool,
    log_preset~ : String?,
    text~ : String
  )
  /// Check the next `count` entries: 1 for Step, a large number for Run all.
  TranscriptStep(seq~ : Int32, count~ : Int32)
  TranscriptReset(seq~ : Int32)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A finding of the model, as the library writes it. `severity` and `code` are
/// the library's strings (`ERROR`, `WARNING`, ...). A line or column of 0 means
/// that the library gave no place in the model text.
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
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A transcript entry. `line` and `column` are the place of the message in the
/// transcript text.
pub(all) struct EntryView {
  index : Int32
  sender : String
  receiver : String?
  message : String
  line : Int32?
  column : Int32?
  /// False until the checker has read the entry.
  checked : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A transcript finding, with the fields of the CLI JSON report. `severity` is
/// "error" or "advisory". `path` is a JSON pointer.
pub(all) struct FindingView {
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
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) struct ExpectedView {
  code : String
  entry : Int32?
  related : Int32?
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The match of the findings against the `expect` list of the transcript.
pub(all) struct ExpectationView {
  matched : Bool
  missing : Array[ExpectedView]
  /// The unexpected findings with severity "error".
  unexpected : Array[FindingView]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The result at the end of a transcript. `lines`, `not_json` and `skipped`
/// are the counts of a JSONL log; they are 0 for other formats.
pub(all) struct SummaryView {
  valid : Bool
  complete : Bool
  entries : Int32
  errors : Int32
  outstanding : Int32
  correlation : Bool
  lines : Int32
  not_json : Int32
  skipped : Int32
  expectations : ExpectationView?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum Response {
  Diagnostics(seq~ : Int32, items~ : Array[Diagnostic], shapes~ : Int32)
  /// The files of a transform, as (name, text).
  Transformed(seq~ : Int32, files~ : Array[(String, String)])
  /// The request did not run. `reason` says why, in a sentence.
  Blocked(seq~ : Int32, reason~ : String)
  /// The state of the check after a start or a step. `entries` lists every
  /// entry of the transcript, and `findings` lists all findings so far.
  TranscriptProgress(
    seq~ : Int32,
    entries~ : Array[EntryView],
    findings~ : Array[FindingView],
    done~ : Bool,
    summary~ : SummaryView?
  )
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum Tab {
  Validate
  Transform
  Transcript
} derive(Eq, Debug, ToJson, FromJson)

///|
/// What a share link holds.
pub(all) struct ShareState {
  model : String
  transcript : String
  tab : Tab
  output : Output
  protocol : String
  format : TranscriptFormat
  complete : Bool
} derive(Eq, Debug, ToJson, FromJson)

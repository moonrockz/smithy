///|
/// The transcript format and the log preset of a request are the types of the
/// samples of the picker, so the page sends them with no conversion.
pub using @samples {
  type TranscriptFormat,
  type Direction,
  type LogPreset,
  type Output,
  type Tab,
  type ShareState,
}

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
  /// the format Jsonl only, as the CLI option --log-preset; `None` is
  /// `DirMessage([])`. `version` is the CLI option --version: a log needs it,
  /// and a document gives its own, so the page sends `None` for a document.
  /// `complete` is the flag --complete of the CLI: true makes the check
  /// complete. False leaves the choice to the document, and a document that
  /// says nothing is partial.
  TranscriptStart(
    seq~ : Int32,
    model~ : String,
    protocol~ : String,
    format~ : TranscriptFormat,
    complete~ : Bool,
    log_preset~ : LogPreset?,
    version~ : String?,
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
/// transcript text. `receiver` is the receiver that the document names, else
/// the other peer for a request; it is `None` for a reply with no named
/// receiver.
pub(all) struct EntryView {
  index : Int32
  sender : String
  receiver : String?
  message : String
  line : Int32?
  column : Int32?
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
/// Why a request did not run, for the page to choose its copy.
pub(all) enum BlockKind {
  /// The model has errors, and a transform needs a model without them.
  ModelErrors
  /// Any other reason; the `reason` text of the response says it.
  Other
} derive(Eq, Debug, ToJson, FromJson)

///|
/// A structure of the model with the `smithy.rpc#jsonRpcProtocol` trait: the
/// versions that it declares and the names of its peers, in trait order.
pub(all) struct ProtocolView {
  id : String
  versions : Array[String]
  peers : Array[String]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub(all) enum Response {
  /// The diagnostics of the model, and its JSON-RPC protocols, by shape ID.
  /// A model that does not assemble lists no protocol.
  Diagnostics(
    seq~ : Int32,
    items~ : Array[Diagnostic],
    shapes~ : Int32,
    protocols~ : Array[ProtocolView]
  )
  /// The files of a transform, as (name, text). `warnings` are the warnings
  /// of the converter, each as the CLI prints it: `WARNING: <shape>: <message>`.
  /// `service` is the shape ID of the service that an OpenAPI or OpenRPC
  /// output used; other outputs have `None`.
  Transformed(
    seq~ : Int32,
    files~ : Array[(String, String)],
    warnings~ : Array[String],
    service~ : String?
  )
  /// The request did not run. `reason` says why, in a sentence.
  Blocked(seq~ : Int32, reason~ : String, kind~ : BlockKind)
  /// The state of the check after a start or a step, as a change since the
  /// previous response for the same transcript, so a step costs the same at
  /// the end of a long log as at its start. A start gives every entry of the
  /// transcript; a step gives none. `findings` are the findings that are new
  /// since the previous response. `checked` is the number of entries that the
  /// checker has read so far.
  TranscriptProgress(
    seq~ : Int32,
    entries~ : Array[EntryView],
    findings~ : Array[FindingView],
    checked~ : Int32,
    done~ : Bool,
    summary~ : SummaryView?
  )
} derive(Eq, Debug, ToJson, FromJson)

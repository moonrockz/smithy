///|
/// One example of the playground picker: its title and the repository path
/// of its model.
pub(all) struct SampleSource {
  title : String
  path : String
} derive(Eq, Debug)

///|
pub extend SampleSource with Eq::{equal, not_equal}

///|
pub extend SampleSource with @debug.Debug::{to_repr}

///|
/// The examples of the playground picker, in the order of the picker. A model
/// from `examples/` is the file of that example. A model that only the
/// playground uses, such as the one with a deliberate mistake, is in
/// `site/playground/samples/`, so the examples index does not list it.
pub let manifest : Array[SampleSource] = [
  { title: "JSON-RPC chat protocol", path: "examples/json-rpc/peers.smithy", },
  {
    title: "JSON-RPC chat protocol (with a mistake)",
    path: "site/playground/samples/chat-error.smithy",
  },
  { title: "Order", path: "site/landing/sample/order.smithy", },
]

///|
/// The index in `manifest` of the example that the playground opens with.
pub let default_index : Int32 = 1

///|
/// An example of the picker with the text of its model.
pub(all) struct Sample {
  title : String
  path : String
  model : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Sample with Eq::{equal, not_equal}

///|
pub extend Sample with @debug.Debug::{to_repr}

///|
pub extend Sample with ToJson::{to_json}

///|
pub extend Sample with FromJson::{from_json}

///|
/// The encoding of a transcript text.
pub(all) enum TranscriptFormat {
  Markdown
  Json
  Jsonl
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TranscriptFormat with Eq::{equal, not_equal}

///|
pub extend TranscriptFormat with @debug.Debug::{to_repr}

///|
pub extend TranscriptFormat with ToJson::{to_json}

///|
pub extend TranscriptFormat with FromJson::{from_json}

///|
/// The sender of the message of a log record whose `dir` member has this
/// value: the CLI option `--direction value=peer`.
pub(all) struct Direction {
  value : String
  peer : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Direction with Eq::{equal, not_equal}

///|
pub extend Direction with @debug.Debug::{to_repr}

///|
pub extend Direction with ToJson::{to_json}

///|
pub extend Direction with FromJson::{from_json}

///|
/// How the lines of a JSONL log become transcript entries: the CLI option
/// `--log-preset`.
pub(all) enum LogPreset {
  /// `{"dir", "message"}` records. Each direction names the sender for one
  /// `dir` value.
  DirMessage(Array[Direction])
  /// Each line is a JSON-RPC message from `sender`.
  Raw(sender~ : String)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LogPreset with Eq::{equal, not_equal}

///|
pub extend LogPreset with @debug.Debug::{to_repr}

///|
pub extend LogPreset with ToJson::{to_json}

///|
pub extend LogPreset with FromJson::{from_json}

///|
/// A transcript of the Transcript tab picker: its title, the repository path
/// of its text, and how to check it. The model of every transcript is
/// `examples/json-rpc/peers.smithy`. A log has a version and a preset; a
/// document gives its own version and has neither.
pub(all) struct TranscriptSource {
  title : String
  path : String
  protocol : String
  format : TranscriptFormat
  version : String?
  preset : LogPreset?
} derive(Eq, Debug)

///|
pub extend TranscriptSource with Eq::{equal, not_equal}

///|
pub extend TranscriptSource with @debug.Debug::{to_repr}

///|
/// The transcripts of the picker, in the order of the picker. The one with the
/// three findings of the mockup only the playground uses, so it is in
/// `site/playground/samples/`.
pub let transcript_manifest : Array[TranscriptSource] = [
  {
    title: "Chat with three findings",
    path: "site/playground/samples/chat-findings.md",
    protocol: "example.peers#EchoChat",
    format: Markdown,
    version: None,
    preset: None,
  },
  {
    title: "Chat",
    path: "examples/json-rpc/transcripts/chat.md",
    protocol: "example.peers#EchoChat",
    format: Markdown,
    version: None,
    preset: None,
  },
  {
    title: "Echo",
    path: "examples/json-rpc/transcripts/echo.md",
    protocol: "example.peers#EchoChat",
    format: Markdown,
    version: None,
    preset: None,
  },
  {
    title: "Editor",
    path: "examples/json-rpc/transcripts/editor.md",
    protocol: "example.peers#Editor",
    format: Markdown,
    version: None,
    preset: None,
  },
  {
    title: "Editor log (JSONL)",
    path: "examples/json-rpc/transcripts/editor.jsonl",
    protocol: "example.peers#Editor",
    format: Jsonl,
    version: Some("2.0"),
    preset: Some(
      DirMessage([
        { value: "in", peer: "client", },
        { value: "out", peer: "server", },
      ]),
    ),
  },
]

///|
/// The index in `transcript_manifest` of the transcript that the tab opens with.
pub let default_transcript : Int32 = 0

///|
/// A transcript of the picker with its text.
pub(all) struct TranscriptSample {
  title : String
  path : String
  protocol : String
  format : TranscriptFormat
  version : String?
  preset : LogPreset?
  text : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TranscriptSample with Eq::{equal, not_equal}

///|
pub extend TranscriptSample with @debug.Debug::{to_repr}

///|
pub extend TranscriptSample with ToJson::{to_json}

///|
pub extend TranscriptSample with FromJson::{from_json}

///|
/// The tab of the playground.
pub(all) enum Tab {
  ValidateTab
  TransformTab
  TranscriptTab
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Tab with Eq::{equal, not_equal}

///|
pub extend Tab with @debug.Debug::{to_repr}

///|
pub extend Tab with ToJson::{to_json}

///|
pub extend Tab with FromJson::{from_json}

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
pub extend Output with Eq::{equal, not_equal}

///|
pub extend Output with @debug.Debug::{to_repr}

///|
pub extend Output with ToJson::{to_json}

///|
pub extend Output with FromJson::{from_json}

///|
/// What a share link holds: the settings of the page and the texts of the two
/// editors. The page and the core both use it, so a link needs no conversion.
pub(all) struct ShareState {
  model : String
  transcript : String
  tab : Tab
  output : Output
  protocol : String
  format : TranscriptFormat
  complete : Bool
  selector : String?
  log_preset : LogPreset?
  /// The JSON-RPC version of a log.
  version : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend ShareState with Eq::{equal, not_equal}

///|
pub extend ShareState with @debug.Debug::{to_repr}

///|
pub extend ShareState with ToJson::{to_json}

///|
pub extend ShareState with FromJson::{from_json}

///|
/// The state that "Open in playground" opens for the example directory `dir`
/// of `examples/`: the first model of the picker under that directory, with
/// the first transcript under it (the default transcript when there is none).
/// `None` when no model of the picker is in that directory, so the example
/// page has no button.
pub fn example_state(
  dir : String,
  samples : Array[Sample],
  transcripts : Array[TranscriptSample],
  default_transcript : Int32,
) -> ShareState? {
  let prefix = "examples/" + dir + "/"
  guard samples.iter().find_first(s => s.path.has_prefix(prefix))
    is Some(sample) else {
    return None
  }
  let transcript = match
    transcripts.iter().find_first(t => t.path.has_prefix(prefix)) {
    Some(t) => Some(t)
    None => transcripts.get(default_transcript)
  }
  match transcript {
    Some(t) =>
      Some({
        model: sample.model,
        transcript: t.text,
        tab: ValidateTab,
        output: JsonAst,
        protocol: t.protocol,
        format: t.format,
        complete: false,
        selector: None,
        log_preset: t.preset,
        version: t.version,
      })
    None =>
      Some({
        model: sample.model,
        transcript: "",
        tab: ValidateTab,
        output: JsonAst,
        protocol: "",
        format: Markdown,
        complete: false,
        selector: None,
        log_preset: None,
        version: None,
      })
  }
}

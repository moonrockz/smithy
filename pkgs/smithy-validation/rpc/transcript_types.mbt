///|
/// Declared, never assumed. Complete reports each unanswered call as missing;
/// Partial reports it as outstanding.
pub(all) enum Completeness {
  Complete
  Partial
} derive(Eq, Debug)

///|
/// One-based line and column of an entry in its source document.
pub(all) struct SourceLocation {
  line : Int32
  column : Int32
} derive(Eq, Debug)

///|
/// One message sent by a named peer. The receiver is the other peer.
pub(all) struct TranscriptEntry {
  sender : PeerName
  /// The receiver the document names, if any; it must be the other peer.
  receiver : PeerName?
  message : String
  location : SourceLocation?
} derive(Eq, Debug)

///|
/// Constructor names differ from FindingCode so that unqualified FindingCode
/// constructors stay unambiguous; `to_string` gives the stable code names.
pub(all) enum TranscriptCode {
  /// A message-level finding from the request or response validator.
  Message(FindingCode)
  UnknownPeer
  EntryLimit
  ActiveCallLimit
  FindingLimit
  UnsolicitedResponse
  /// Renders as "DuplicateResponse".
  DuplicateReply
  /// Renders as "MissingResponse".
  MissingReply
  OutstandingCall
  ResponseToNotification
  WrongResponder
  ActiveIdReused
  /// Renders as "AmbiguousId".
  AmbiguousReplyId
  WrongReplyForm
  /// A problem in the transcript document rather than in a message.
  InvalidTranscript
} derive(Eq, Debug)

///|
pub fn TranscriptCode::to_string(self : TranscriptCode) -> String {
  match self {
    Message(code) => code.to_string()
    UnknownPeer => "UnknownPeer"
    EntryLimit => "EntryLimit"
    ActiveCallLimit => "ActiveCallLimit"
    FindingLimit => "FindingLimit"
    UnsolicitedResponse => "UnsolicitedResponse"
    DuplicateReply => "DuplicateResponse"
    MissingReply => "MissingResponse"
    OutstandingCall => "OutstandingCall"
    ResponseToNotification => "ResponseToNotification"
    WrongResponder => "WrongResponder"
    ActiveIdReused => "ActiveIdReused"
    AmbiguousReplyId => "AmbiguousId"
    WrongReplyForm => "WrongReplyForm"
    InvalidTranscript => "InvalidTranscript"
  }
}

///|
/// A finding about one entry. `entry` is zero-based; `related` lists other
/// entries, such as the call a reply answers or the first reply of a duplicate.
pub(all) struct TranscriptFinding {
  code : TranscriptCode
  severity : @validation.FindingSeverity
  entry : Int32?
  location : SourceLocation?
  sender : PeerName?
  related : Array[Int32]
  finding : Finding?
  message : String
} derive(Eq, Debug)

///|
pub impl @json.ToJson for TranscriptFinding with fn to_json(self) {
  fn number(n : Int32) -> Json {
    Json::number(n.to_double())
  }

  Json::object({
    "code": Json::string(self.code.to_string()),
    "severity": Json::string(
      if self.severity == @validation.Error {
        "error"
      } else {
        "advisory"
      },
    ),
    "entry": self.entry.map(number).unwrap_or(Json::null()),
    "line": self.location.map(l => number(l.line)).unwrap_or(Json::null()),
    "column": self.location.map(l => number(l.column)).unwrap_or(Json::null()),
    "sender": self.sender
    .map(p => Json::string(p.to_string()))
    .unwrap_or(Json::null()),
    "related": Json::array(self.related.map(number)),
    "path": self.finding.map(f => @json.to_json(f.path)).unwrap_or(Json::null()),
    "shape": self.finding
    .map(f => Json::string(f.shape.to_string()))
    .unwrap_or(Json::null()),
    "operation": self.finding
    .bind(f => f.operation)
    .map(id => Json::string(id.to_string()))
    .unwrap_or(Json::null()),
    "message": Json::string(self.message),
  })
}

///|
/// Bounds on the checker's memory and output. Exceeding one gives a finding.
pub struct TranscriptLimits {
  /// Active calls, unreadable entries and pending batches, each per sender.
  active_calls : Int32
  /// Answered IDs and remembered 1.0 notifications per sender.
  answered_ids : Int32
  /// UTF-8 bytes in one entry's message.
  entry_bytes : Int32
  /// Findings for the whole transcript, including the final limit finding.
  findings : Int32
} derive(Eq, Debug)

///|
const DEFAULT_ACTIVE_CALLS : Int32 = 1024

///|
const DEFAULT_ANSWERED_IDS : Int32 = 4096

///|
const DEFAULT_ENTRY_BYTES : Int32 = 1048576

///|
const DEFAULT_FINDINGS : Int32 = 10000

///|
fn TranscriptLimits::default() -> TranscriptLimits {
  {
    active_calls: DEFAULT_ACTIVE_CALLS,
    answered_ids: DEFAULT_ANSWERED_IDS,
    entry_bytes: DEFAULT_ENTRY_BYTES,
    findings: DEFAULT_FINDINGS,
  }
}

///|
pub fn TranscriptLimits::new(
  active_calls~ : Int32 = DEFAULT_ACTIVE_CALLS,
  answered_ids~ : Int32 = DEFAULT_ANSWERED_IDS,
  entry_bytes~ : Int32 = DEFAULT_ENTRY_BYTES,
  findings~ : Int32 = DEFAULT_FINDINGS,
) -> TranscriptLimits raise @validation.ConfigurationError {
  let named = [
    ("active_calls", active_calls),
    ("answered_ids", answered_ids),
    ("entry_bytes", entry_bytes),
    ("findings", findings),
  ]
  for limit in named {
    let (name, value) = limit
    if value < 1 {
      raise @validation.ConfigurationError(
        "I expected a positive transcript limit; \{name} was \{value}.",
      )
    }
  }
  { active_calls, answered_ids, entry_bytes, findings, }
}

///|
pub(all) struct TranscriptSummary {
  /// Findings known only at the end of input.
  findings : Array[TranscriptFinding]
  entries : Int32
  /// Calls, 2.0 unreadable entries and request batches still waiting for a reply.
  outstanding : Int32
  correlation : Bool
  /// False when a limit stopped a check.
  complete : Bool
} derive(Eq, Debug)

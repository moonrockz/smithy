///|
/// A finding that a transcript is expected to produce. The code is the stable
/// name of a TranscriptCode, an rpc FindingCode or a validation FindingCode.
pub struct ExpectedFinding {
  priv code : String
  priv entry : Int32?
  priv related : Int32?
} derive(Eq, Debug)

///|
fn known_code_names() -> Array[String] {
  let rpc_codes : Array[FindingCode] = [
    InvalidJson,
    DuplicateJsonKey,
    JsonInputLimit,
    InvalidEnvelope,
    InvalidVersion,
    InvalidId,
    DiscouragedId,
    UnknownMethod,
    InvalidParams,
    UnsupportedMessage,
    MissingContext,
    LimitedScope,
    InvalidContext,
    IdMismatch,
    UnexpectedResponse,
    InvalidError,
    UnknownError,
    AmbiguousId,
    DuplicateResponse,
    MissingResponse,
  ]
  let value_codes : Array[@validation.FindingCode] = [
    TypeMismatch,
    RequiredMember,
    UnknownMember,
    DuplicateMember,
    InvalidNumber,
    NumericBounds,
    Range,
    Length,
    Pattern,
    UniqueItems,
    EnumValue,
    UnionMember,
    InvalidEncoding,
    InvalidTimestamp,
    UnsupportedValue,
    LimitExceeded,
  ]
  let transcript_codes : Array[TranscriptCode] = [
    UnknownPeer,
    EntryLimit,
    ActiveCallLimit,
    FindingLimit,
    UnsolicitedResponse,
    DuplicateReply,
    MissingReply,
    OutstandingCall,
    ResponseToNotification,
    WrongResponder,
    ActiveIdReused,
    AmbiguousReplyId,
    WrongReplyForm,
    InvalidTranscript,
  ]
  let names = []
  for code in rpc_codes {
    names.push(Message(code).to_string())
  }
  for code in value_codes {
    names.push(Message(Value(code)).to_string())
  }
  for code in transcript_codes {
    names.push(code.to_string())
  }
  names
}

///|
/// None unless `code` is the name of a known finding code.
pub fn ExpectedFinding::new(
  code : String,
  entry~ : Int32? = None,
  related~ : Int32? = None,
) -> ExpectedFinding? {
  if known_code_names().contains(code) {
    Some({ code, entry, related, })
  } else {
    None
  }
}

///|
pub fn ExpectedFinding::code(self : ExpectedFinding) -> String {
  self.code
}

///|
pub fn ExpectedFinding::entry(self : ExpectedFinding) -> Int32? {
  self.entry
}

///|
pub fn ExpectedFinding::related(self : ExpectedFinding) -> Int32? {
  self.related
}

///|
pub(all) struct ExpectationResult {
  /// Expected findings that no actual finding matched.
  missing : Array[ExpectedFinding]
  /// Actual findings that no expectation matched, with any severity.
  unexpected : Array[TranscriptFinding]
} derive(Eq, Debug)

///|
/// True when nothing is missing and no unexpected finding is an error.
pub fn ExpectationResult::is_match(self : ExpectationResult) -> Bool {
  self.missing.is_empty() &&
  !self.unexpected.iter().any(f => f.severity == @validation.Error)
}

///|
fn ExpectedFinding::accepts(
  self : ExpectedFinding,
  finding : TranscriptFinding,
) -> Bool {
  finding.code.to_string() == self.code &&
  (self.entry is None || self.entry == finding.entry) &&
  (
    self.related is None ||
    finding.related.iter().any(r => Some(r) == self.related)
  )
}

///|
/// Tries to give `item` a finding, moving an earlier item to another finding
/// when that frees one.
fn assign(
  expected : Array[ExpectedFinding],
  actual : Array[TranscriptFinding],
  owner : Array[Int32?],
  seen : Array[Bool],
  item : Int32,
) -> Bool {
  for i in 0..<actual.length() {
    if !seen[i] && expected[item].accepts(actual[i]) {
      seen[i] = true
      let free = match owner[i] {
        None => true
        Some(other) => assign(expected, actual, owner, seen, other)
      }
      if free {
        owner[i] = Some(item)
        return true
      }
    }
  }
  false
}

///|
/// Each expected item takes one distinct actual finding, so the largest
/// possible set of items is matched. Order does not matter. An item with no
/// finding is missing. A finding that no item took is unexpected.
pub fn match_expected(
  expected : Array[ExpectedFinding],
  actual : Array[TranscriptFinding],
) -> ExpectationResult {
  let owner : Array[Int32?] = Array::make(actual.length(), None)
  let matched = Array::make(expected.length(), false)
  for item in 0..<expected.length() {
    let seen = Array::make(actual.length(), false)
    matched[item] = assign(expected, actual, owner, seen, item)
  }
  let missing = []
  for item in 0..<expected.length() {
    if !matched[item] {
      missing.push(expected[item])
    }
  }
  let unexpected = []
  for i in 0..<actual.length() {
    if owner[i] is None {
      unexpected.push(actual[i])
    }
  }
  { missing, unexpected, }
}

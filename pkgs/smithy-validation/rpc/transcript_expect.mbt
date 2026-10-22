///|
/// A finding that a transcript is expected to produce. The code is the stable
/// name of a TranscriptCode, an rpc FindingCode or a validation FindingCode.
pub struct ExpectedFinding {
  priv code : String
  priv entry : Int32?
  priv related : Int32?
} derive(Eq, Debug)

///|
/// The successor of each rpc FindingCode in a walk of all variants. The match
/// has no wildcard arm, so a new variant does not compile until it is placed
/// here. `Value` carries the validation codes, which the next walk covers.
fn next_rpc_code(code : FindingCode) -> FindingCode? {
  match code {
    InvalidJson => Some(DuplicateJsonKey)
    DuplicateJsonKey => Some(JsonInputLimit)
    JsonInputLimit => Some(InvalidEnvelope)
    InvalidEnvelope => Some(InvalidVersion)
    InvalidVersion => Some(InvalidId)
    InvalidId => Some(DiscouragedId)
    DiscouragedId => Some(UnknownMethod)
    UnknownMethod => Some(InvalidParams)
    InvalidParams => Some(UnsupportedMessage)
    UnsupportedMessage => Some(MissingContext)
    MissingContext => Some(LimitedScope)
    LimitedScope => Some(InvalidContext)
    InvalidContext => Some(IdMismatch)
    IdMismatch => Some(UnexpectedResponse)
    UnexpectedResponse => Some(InvalidError)
    InvalidError => Some(UnknownError)
    UnknownError => Some(AmbiguousId)
    AmbiguousId => Some(DuplicateResponse)
    DuplicateResponse => Some(MissingResponse)
    // An appended variant must be linked from this arm, and the snapshot test updated.
    MissingResponse => None
    Value(_) => None
  }
}

///|
fn next_value_code(code : @validation.FindingCode) -> @validation.FindingCode? {
  match code {
    TypeMismatch => Some(RequiredMember)
    RequiredMember => Some(UnknownMember)
    UnknownMember => Some(DuplicateMember)
    DuplicateMember => Some(InvalidNumber)
    InvalidNumber => Some(NumericBounds)
    NumericBounds => Some(Range)
    Range => Some(Length)
    Length => Some(Pattern)
    Pattern => Some(UniqueItems)
    UniqueItems => Some(EnumValue)
    EnumValue => Some(UnionMember)
    UnionMember => Some(InvalidEncoding)
    InvalidEncoding => Some(InvalidTimestamp)
    InvalidTimestamp => Some(UnsupportedValue)
    UnsupportedValue => Some(LimitExceeded)
    // An appended variant must be linked from this arm, and the snapshot test updated.
    LimitExceeded => None
  }
}

///|
/// `Message` carries the codes of the two walks above.
fn next_transcript_code(code : TranscriptCode) -> TranscriptCode? {
  match code {
    UnknownPeer => Some(EntryLimit)
    EntryLimit => Some(ActiveCallLimit)
    ActiveCallLimit => Some(FindingLimit)
    FindingLimit => Some(UnsolicitedResponse)
    UnsolicitedResponse => Some(DuplicateReply)
    DuplicateReply => Some(MissingReply)
    MissingReply => Some(OutstandingCall)
    OutstandingCall => Some(ResponseToNotification)
    ResponseToNotification => Some(WrongResponder)
    WrongResponder => Some(ActiveIdReused)
    ActiveIdReused => Some(AmbiguousReplyId)
    AmbiguousReplyId => Some(WrongReplyForm)
    WrongReplyForm => Some(InvalidTranscript)
    // An appended variant must be linked from this arm, and the snapshot test updated.
    InvalidTranscript => None
    Message(_) => None
  }
}

///|
fn[T] walk_codes(first : T, next : (T) -> T?) -> Array[T] {
  let all = [first]
  let mut current = next(first)
  // A cycle from a wrong link stops at the cap and fails the snapshot test.
  while current is Some(code) && all.length() < 256 {
    all.push(code)
    current = next(code)
  }
  all
}

///|
fn rpc_code_names() -> Array[String] {
  walk_codes(InvalidJson, next_rpc_code).map(c => Message(c).to_string())
}

///|
fn value_code_names() -> Array[String] {
  walk_codes(@validation.TypeMismatch, next_value_code).map(c => {
    Message(Value(c)).to_string()
  })
}

///|
fn transcript_code_names() -> Array[String] {
  walk_codes(UnknownPeer, next_transcript_code).map(c => c.to_string())
}

///|
fn known_code_names() -> Array[String] {
  let names = rpc_code_names()
  names.append(value_code_names())
  names.append(transcript_code_names())
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

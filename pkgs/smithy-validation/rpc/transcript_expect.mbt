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
pub struct ExpectationResult {
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
/// True when `finding`, whose code has this item's name, fits the entry and
/// related entry of this item.
fn ExpectedFinding::fits(
  self : ExpectedFinding,
  finding : TranscriptFinding,
) -> Bool {
  (self.entry is None || self.entry == finding.entry) &&
  (
    self.related is None ||
    finding.related.iter().any(r => Some(r) == self.related)
  )
}

///|
/// The state of one match: the findings of each code name in order, the item
/// that owns each finding, and the first position of each code name that can
/// still be free. A finding never becomes free again, so that position only
/// moves forward.
priv struct Matching {
  expected : Array[ExpectedFinding]
  actual : Array[TranscriptFinding]
  by_code : Map[String, Array[Int32]]
  owner : Array[Int32?]
  first_free : Map[String, Int32]
}

///|
fn Matching::bucket(self : Matching, item : Int32) -> Array[Int32] {
  self.by_code.get(self.expected[item].code).unwrap_or([])
}

///|
/// A free finding that `item` accepts, if any.
fn Matching::free_for(self : Matching, item : Int32) -> Int32? {
  let code = self.expected[item].code
  let bucket = self.bucket(item)
  let mut start = self.first_free.get(code).unwrap_or(0)
  while start < bucket.length() && self.owner[bucket[start]] is Some(_) {
    start += 1
  }
  self.first_free[code] = start
  for position in start..<bucket.length() {
    let i = bucket[position]
    if self.owner[i] is None && self.expected[item].fits(self.actual[i]) {
      return Some(i)
    }
  }
  None
}

///|
/// Searches for an augmenting path from the unmatched `root` with an explicit
/// stack, so the search depth does not use the call stack. On success each
/// item on the path moves to the next finding and `root` gets one. `seen`
/// marks findings that the search entered; a failed search changes no owner,
/// so its marks stay valid for the next search, and `touched` lists them for
/// a reset after a success.
fn Matching::augment(
  self : Matching,
  root : Int32,
  seen : Array[Bool],
  touched : Array[Int32],
) -> Bool {
  let items = [root]
  // The next bucket position of each frame; -1 before its free look-ahead.
  let positions = [-1]
  // via[k] is the finding through which frame k + 1 was entered.
  let via : Array[Int32] = []
  while items.length() > 0 {
    let top = items.length() - 1
    let item = items[top]
    let mut taken : Int32? = None
    let mut entered = false
    if positions[top] < 0 {
      positions[top] = 0
      taken = self.free_for(item)
    }
    let bucket = self.bucket(item)
    while taken is None && positions[top] < bucket.length() {
      let i = bucket[positions[top]]
      positions[top] += 1
      if seen[i] || !self.expected[item].fits(self.actual[i]) {
        continue
      }
      seen[i] = true
      touched.push(i)
      match self.owner[i] {
        None => taken = Some(i)
        Some(other) => {
          via.push(i)
          items.push(other)
          positions.push(-1)
          entered = true
          break
        }
      }
    }
    if taken is Some(last) {
      for k in 0..<=top {
        let finding = if k == top { last } else { via[k] }
        self.owner[finding] = Some(items[k])
      }
      return true
    }
    if !entered {
      ignore(items.pop())
      ignore(positions.pop())
      if top > 0 {
        ignore(via.pop())
      }
    }
  }
  false
}

///|
/// Each expected item takes one distinct actual finding, so the largest
/// possible set of items is matched. Order does not matter. An item with no
/// finding is missing. A finding that no item took is unexpected.
///
/// A greedy pass first gives each item a free finding that it accepts. Only
/// the items left then search for an augmenting path, with an explicit stack.
pub fn match_expected(
  expected : Array[ExpectedFinding],
  actual : Array[TranscriptFinding],
) -> ExpectationResult {
  let by_code : Map[String, Array[Int32]] = Map([])
  for i, finding in actual {
    let code = finding.code.to_string()
    match by_code.get(code) {
      Some(bucket) => bucket.push(i)
      None => by_code[code] = [i]
    }
  }
  let matching : Matching = {
    expected,
    actual,
    by_code,
    owner: Array::make(actual.length(), None),
    first_free: Map([]),
  }
  let left = []
  for item in 0..<expected.length() {
    match matching.free_for(item) {
      Some(i) => matching.owner[i] = Some(item)
      None => left.push(item)
    }
  }
  let matched = Array::make(expected.length(), true)
  let seen = Array::make(actual.length(), false)
  let touched = []
  for item in left {
    if matching.augment(item, seen, touched) {
      for i in touched {
        seen[i] = false
      }
      touched.clear()
    } else {
      matched[item] = false
    }
  }
  let missing = []
  for item in 0..<expected.length() {
    if !matched[item] {
      missing.push(expected[item])
    }
  }
  let unexpected = []
  for i in 0..<actual.length() {
    if matching.owner[i] is None {
      unexpected.push(actual[i])
    }
  }
  { missing, unexpected, }
}

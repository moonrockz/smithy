///|
test "known code names are pinned in order" {
  assert_eq(rpc_code_names(), [
    "InvalidJson", "DuplicateJsonKey", "JsonInputLimit", "InvalidEnvelope", "InvalidVersion",
    "InvalidId", "DiscouragedId", "UnknownMethod", "InvalidParams", "UnsupportedMessage",
    "MissingContext", "LimitedScope", "InvalidContext", "IdMismatch", "UnexpectedResponse",
    "InvalidError", "UnknownError", "AmbiguousId", "DuplicateResponse", "MissingResponse",
  ])
  assert_eq(value_code_names(), [
    "TypeMismatch", "RequiredMember", "UnknownMember", "DuplicateMember", "InvalidNumber",
    "NumericBounds", "Range", "Length", "Pattern", "UniqueItems", "EnumValue", "UnionMember",
    "InvalidEncoding", "InvalidTimestamp", "UnsupportedValue", "LimitExceeded",
  ])
  assert_eq(transcript_code_names(), [
    "UnknownPeer", "EntryLimit", "ActiveCallLimit", "FindingLimit", "UnsolicitedResponse",
    "DuplicateResponse", "MissingResponse", "OutstandingCall", "ResponseToNotification",
    "WrongResponder", "ActiveIdReused", "AmbiguousId", "WrongReplyForm", "InvalidTranscript",
    "StateViolation", "CapabilityNotAdvertised", "CancelInactiveCall",
  ])
}

///|
test "every known code name is accepted and unique within its group" {
  for group in [rpc_code_names(), value_code_names(), transcript_code_names()] {
    for i, name in group {
      assert_true(ExpectedFinding::new(name) is Some(_))
      for j in 0..<i {
        assert_true(group[j] != name)
      }
    }
  }
}

///|
/// The size of a maximum match, found by plain recursive augmenting paths. It
/// is a reference for small inputs only.
fn reference_match_size(
  expected : Array[ExpectedFinding],
  actual : Array[TranscriptFinding],
) -> Int32 {
  let owner : Array[Int32?] = Array::make(actual.length(), None)
  fn accepts(item : Int32, i : Int32) -> Bool {
    actual[i].code.to_string() == expected[item].code &&
    expected[item].fits(actual[i])
  }

  fn assign(item : Int32, seen : Array[Bool]) -> Bool {
    for i in 0..<actual.length() {
      if !seen[i] && accepts(item, i) {
        seen[i] = true
        let free = match owner[i] {
          None => true
          Some(other) => assign(other, seen)
        }
        if free {
          owner[i] = Some(item)
          return true
        }
      }
    }
    false
  }

  let mut size = 0
  for item in 0..<expected.length() {
    if assign(item, Array::make(actual.length(), false)) {
      size += 1
    }
  }
  size
}

///|
test "the greedy matcher finds a maximum match" {
  let codes : Array[TranscriptCode] = [
    UnsolicitedResponse,
    DuplicateReply,
    MissingReply,
  ]
  let mut state = 7
  fn next(bound : Int32) -> Int32 {
    state = (state * 1103515245 + 12345) & 0x7fffffff
    state % bound
  }

  fn optional(bound : Int32) -> Int32? {
    let n = next(bound + 1)
    if n == bound {
      None
    } else {
      Some(n)
    }
  }

  for _ in 0..<2000 {
    let actual = Array::makei(next(9), _ => {
      code: codes[next(3)],
      severity: @validation.Error,
      entry: Some(next(3)),
      location: None,
      sender: None,
      related: [next(3)],
      finding: None,
      message: "",
    })
    let expected : Array[ExpectedFinding] = Array::makei(next(9), _ => {
      code: codes[next(3)].to_string(),
      entry: optional(3),
      related: optional(3),
    })
    let size = reference_match_size(expected, actual)
    let result = match_expected(expected, actual)
    assert_eq(result.missing.length(), expected.length() - size)
    assert_eq(result.unexpected.length(), actual.length() - size)
  }
}

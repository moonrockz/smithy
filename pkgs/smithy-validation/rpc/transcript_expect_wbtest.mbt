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

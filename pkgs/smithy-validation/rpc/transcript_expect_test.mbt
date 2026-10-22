///|
fn finding(
  code : @rpc.TranscriptCode,
  entry~ : Int32? = None,
  related~ : Array[Int32] = [],
  severity~ : @validation.FindingSeverity = @validation.Error,
) -> @rpc.TranscriptFinding {
  {
    code,
    severity,
    entry,
    location: None,
    sender: None,
    related,
    finding: None,
    message: "",
  }
}

///|
fn expected(
  code : String,
  entry~ : Int32? = None,
  related~ : Int32? = None,
) -> @rpc.ExpectedFinding {
  @rpc.ExpectedFinding::new(code, entry~, related~).unwrap()
}

///|
test "expectations match codes entries and related entries in any order" {
  let actual = [
    finding(UnsolicitedResponse, entry=Some(3)),
    finding(DuplicateReply, entry=Some(5), related=[2]),
    finding(MissingReply, entry=Some(0)),
  ]
  let result = @rpc.match_expected(
    [
      expected("MissingResponse", entry=Some(0)),
      expected("DuplicateResponse", related=Some(2)),
      expected("UnsolicitedResponse"),
    ],
    actual,
  )
  assert_eq(result.missing, [])
  assert_eq(result.unexpected, [])
  assert_true(result.is_match())
  // A wrong entry or related entry does not match.
  let wrong = @rpc.match_expected(
    [
      expected("UnsolicitedResponse", entry=Some(4)),
      expected("DuplicateResponse", related=Some(3)),
    ],
    actual,
  )
  assert_eq(wrong.missing.length(), 2)
  assert_eq(wrong.unexpected.length(), 3)
  assert_false(wrong.is_match())
}

///|
test "each expectation takes one distinct finding" {
  let actual = [finding(UnsolicitedResponse, entry=Some(1))]
  let result = @rpc.match_expected(
    [expected("UnsolicitedResponse"), expected("UnsolicitedResponse")],
    actual,
  )
  assert_eq(result.missing.length(), 1)
  // A loose expectation does not starve a strict one listed after it.
  let two = [
    finding(UnsolicitedResponse, entry=Some(1)),
    finding(UnsolicitedResponse, entry=Some(2)),
  ]
  let fit = @rpc.match_expected(
    [
      expected("UnsolicitedResponse"),
      expected("UnsolicitedResponse", entry=Some(1)),
    ],
    two,
  )
  assert_true(fit.is_match())
  assert_eq(fit.unexpected, [])
}

///|
test "unlisted advisories do not fail a match but unlisted errors do" {
  let advisory = finding(
    OutstandingCall,
    entry=Some(0),
    severity=@validation.Advisory,
  )
  let error = finding(UnsolicitedResponse, entry=Some(1))
  let only_advisory = @rpc.match_expected([], [advisory])
  assert_eq(only_advisory.unexpected, [advisory])
  assert_true(only_advisory.is_match())
  let with_error = @rpc.match_expected([], [advisory, error])
  assert_false(with_error.is_match())
  let missing = @rpc.match_expected([expected("MissingResponse")], [])
  assert_false(missing.is_match())
}

///|
test "unknown expectation codes are rejected" {
  assert_true(@rpc.ExpectedFinding::new("Nope") is None)
  assert_true(@rpc.ExpectedFinding::new("") is None)
  // Renamed constructors use their rendered names.
  assert_true(@rpc.ExpectedFinding::new("DuplicateReply") is None)
  for
    name in [
      "DuplicateResponse", "MissingResponse", "AmbiguousId", "UnsolicitedResponse",
      "InvalidTranscript", "InvalidId", "TypeMismatch", "LimitExceeded", "UnknownMethod",
    ] {
    assert_true(@rpc.ExpectedFinding::new(name) is Some(_))
  }
  let item = @rpc.ExpectedFinding::new(
    "InvalidId",
    entry=Some(1),
    related=Some(2),
  ).unwrap()
  assert_eq(item.code(), "InvalidId")
  assert_eq(item.entry(), Some(1))
  assert_eq(item.related(), Some(2))
}

///|
test "many identical expectations match without deep recursion" {
  let count = 3000
  let items = Array::makei(count, _ => expected("UnsolicitedResponse"))
  let actual = Array::makei(count, i => {
    finding(UnsolicitedResponse, entry=Some(i))
  })
  let all = @rpc.match_expected(items, actual)
  assert_eq(all.missing, [])
  assert_eq(all.unexpected, [])
  // One finding fewer leaves exactly one expectation missing.
  let short = @rpc.match_expected(items, actual[1:].to_owned())
  assert_eq(short.missing.length(), 1)
  assert_eq(short.unexpected, [])
  // Loose items listed first still leave each strict item its finding.
  let mixed = Array::makei(count, i => {
    if i < count / 2 {
      expected("UnsolicitedResponse")
    } else {
      expected("UnsolicitedResponse", entry=Some(i - count / 2))
    }
  })
  let fit = @rpc.match_expected(mixed, actual)
  assert_eq(fit.missing, [])
  assert_eq(fit.unexpected, [])
}

///|
test "augmenting moves an earlier item to a later finding" {
  // The greedy pass gives the loose item finding 0; the strict item needs
  // finding 0, so the loose item moves to finding 1.
  let actual = [
    finding(UnsolicitedResponse, entry=Some(0)),
    finding(UnsolicitedResponse, entry=Some(1)),
    finding(MissingReply, entry=Some(2)),
  ]
  let result = @rpc.match_expected(
    [
      expected("UnsolicitedResponse"),
      expected("UnsolicitedResponse", entry=Some(0)),
      expected("MissingResponse", entry=Some(3)),
    ],
    actual,
  )
  assert_eq(result.missing, [expected("MissingResponse", entry=Some(3))])
  assert_eq(result.unexpected, [actual[2]])
}

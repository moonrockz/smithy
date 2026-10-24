///|
/// The key of an event that the corpus compares, as in
/// `pkgs/smithy-diff/reference_test.mbt`.
fn event_key(
  id : String,
  shape : String,
  severity : String,
  message : String,
) -> String {
  id + "|" + shape + "|" + severity + "|" + message
}

///|
test "the core diff of every corpus pair equals the Java-verified events" {
  guard @json.parse(repository_file("tests/tck/diff/events.json"))
    is { "cases": Array(cases), .. } else {
    fail("events.json must have a cases array")
  }
  let mut ran = 0
  for item in cases {
    // A mutation case has no file for the new model.
    if item is { "mutations": _, .. } {
      continue
    }
    guard item
      is {
        "old": String(old),
        "new": String(new),
        "breaking": breaking,
        "events": Array(expected),
        ..
      } else {
      fail("a corpus case needs old, new, breaking and events")
    }
    let old_text = repository_file("tests/tck/diff/" + old)
    let new_text = repository_file("tests/tck/diff/" + new)
    let response = @core.handle(
      @core.Session::new(),
      DiffModels(seq=1, old=[(old, old_text)], new=[(new, new_text)]),
    )
    guard response is Diffed(events=Some(events), breaking=actual_breaking, ..) else {
      fail("\{old}: I expected a Diffed answer with events")
    }
    let actual = events.map(e => {
      event_key(e.id, e.shape.unwrap_or("-"), e.severity, e.message)
    })
    let wanted = expected.filter_map(e => {
      guard e
        is {
          "id": String(id),
          "shape": String(shape),
          "severity": String(severity),
          "message": String(message),
          ..
        } else {
        fail("\{old}: an event needs id, shape, severity and message")
      }
      if severity == "SUPPRESSED" {
        None
      } else {
        Some(event_key(id, shape, severity, message))
      }
    })
    actual.sort_by((a, b) => a.lexical_compare(b))
    wanted.sort_by((a, b) => a.lexical_compare(b))
    if actual != wanted {
      fail(
        "\{old}\n  expected: \{wanted.join(", ")}\n  actual:   \{actual.join(", ")}",
      )
    }
    if Json(actual_breaking) != breaking {
      fail(
        "\{old}: breaking is \{actual_breaking} but the corpus has \{breaking.stringify()}",
      )
    }
    ran += 1
  }
  assert_eq(ran, 67)
}

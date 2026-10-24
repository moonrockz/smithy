///|
/// The Java reference results, written by `mise run reference:tour`.
let reference_path : String = "tour/reference-events.json"

///|
/// The known differences from the Java reference.
let allow_path : String = "tour/reference-allow.json"

///|
let reference_sha : String = "30bdab593f0c2cdf96036782cc3ce15c43a711ef"

///|
/// The line that a lesson with a known difference must contain.
let difference_note : String = "> **Reference difference:**"

///|
/// The result of the Java reference for one case.
struct ReferenceCase {
  digest : String
  events : Array[String]
  json_schema : Json?
}

///|
/// The side of the comparison that has the event that the other side does not have.
enum Side {
  Ours
  Reference
}

///|
enum Difference {
  /// The event is removed from the named side only.
  Event(event~ : String, side~ : Side)
  /// The value at the JSON pointer is removed from both JSON Schema documents.
  JsonSchema(pointer~ : String)
}

///|
/// One entry of the allow list.
struct Allowed {
  case_id : String
  difference : Difference
  reason : String
  issue : String
}

///|
fn read_text(path : String) -> String raise {
  @fs.read_file_to_string(path) catch {
    _ => fail(path + ": I cannot read it")
  }
}

///|
fn parse_json(path : String, text : String) -> Json raise {
  @json.parse(text) catch {
    _ => fail(path + ": it is not valid JSON")
  }
}

///|
fn string_member(json : Json, key : String, where_ : String) -> String raise {
  match json {
    Object(members) if members.get(key) is Some(String(value)) => value
    _ => fail(where_ + ": \"" + key + "\" must be a string")
  }
}

///|
fn parse_reference(text : String) -> Map[String, ReferenceCase] raise {
  guard parse_json(reference_path, text)
    is { "reference_sha": String(sha), "cases": Object(cases), .. } else {
    fail(reference_path + ": I expected \"reference_sha\" and \"cases\"")
  }
  guard sha == reference_sha else {
    fail(
      reference_path + ": the reference SHA is " + sha + ", not " + reference_sha,
    )
  }
  let result : Map[String, ReferenceCase] = Map([])
  for id, entry in cases {
    guard entry is { "digest": String(digest), "events": Array(events), .. } else {
      fail(reference_path + ": " + id + " needs \"digest\" and \"events\"")
    }
    result[id] = {
      digest,
      events: events.map(e => {
        guard e is String(s) else {
          fail(reference_path + ": " + id + ": an event must be a string")
        }
        s
      }),
      json_schema: match entry {
        { "json_schema": schema, .. } => Some(schema)
        _ => None
      },
    }
  }
  result
}

///|
fn parse_allow(text : String) -> Array[Allowed] raise {
  guard parse_json(allow_path, text) is Array(entries) else {
    fail(allow_path + ": I expected a JSON array")
  }
  entries.mapi((i, entry) => {
    let where_ = allow_path + " entry " + i.to_string()
    let case_id = string_member(entry, "case", where_)
    let difference = match string_member(entry, "kind", where_) {
      "event" =>
        Event(
          event=string_member(entry, "event", where_),
          side=match string_member(entry, "side", where_) {
            "ours" => Ours
            "reference" => Reference
            other =>
              fail(
                where_ + ": \"side\" must be \"ours\" or \"reference\", not \"" +
                other +
                "\"",
              )
          },
        )
      "json_schema" => JsonSchema(pointer=string_member(entry, "pointer", where_))
      other =>
        fail(
          where_ + ": \"kind\" must be \"event\" or \"json_schema\", not \"" +
          other +
          "\"",
        )
    }
    {
      case_id,
      difference,
      reason: string_member(entry, "reason", where_),
      issue: string_member(entry, "issue", where_),
    }
  })
}

///|
/// Remove one copy of each allowed event from the side that the entry names.
/// `used[i]` becomes true when entry `i` removed an event.
fn remove_allowed_events(
  case_id : String,
  ours : Array[String],
  reference : Array[String],
  allow : Array[Allowed],
  used : Array[Bool],
) -> Unit {
  for i, entry in allow {
    guard entry.case_id == case_id && entry.difference is Event(event~, side~) else {
      continue
    }
    let events = match side {
      Ours => ours
      Reference => reference
    }
    if events.search(event) is Some(j) {
      events.remove(j) |> ignore
      used[i] = true
    }
  }
}

///|
/// The keys of a JSON pointer (RFC 6901).
fn pointer_keys(pointer : String) -> Array[String] raise {
  guard pointer.has_prefix("/") else { fail("not a JSON pointer: " + pointer) }
  pointer[1:]
  .split("/")
  .map(key => key.to_owned().replace_all(old="~1", new="/").replace_all(old="~0", new="~"))
  .to_array()
}

///|
/// The array index of a pointer key: decimal digits only.
fn array_index(key : String) -> Int? {
  guard !key.is_empty() && key.length() < 10 else { return None }
  let mut index = 0
  for c in key {
    guard c.is_ascii_digit() else { return None }
    index = index * 10 + (c.to_int() - '0'.to_int())
  }
  Some(index)
}

///|
/// Remove the value at the pointer. The result is false when no value is there.
fn remove_pointer(json : Json, pointer : String) -> Bool raise {
  let keys = pointer_keys(pointer)
  let mut node = json
  for i, key in keys {
    let last = i == keys.length() - 1
    match node {
      Object(members) =>
        match members.get(key) {
          None => return false
          Some(_) if last => {
            members.remove(key)
            return true
          }
          Some(child) => node = child
        }
      Array(items) =>
        match array_index(key) {
          Some(index) if index < items.length() =>
            if last {
              items.remove(index) |> ignore
              return true
            } else {
              node = items[index]
            }
          _ => return false
        }
      _ => return false
    }
  }
  false
}

///|
/// The pointers where two JSON values differ, for the failure message.
fn json_differences(a : Json, b : Json, at : String) -> Array[String] {
  match (a, b) {
    (Object(x), Object(y)) => {
      let result = []
      for key, value in x {
        let path = at +
          "/" +
          key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
        match y.get(key) {
          Some(other) => result.append(json_differences(value, other, path))
          None => result.push(path + " (only ours)")
        }
      }
      for key, _ in y {
        if !x.contains(key) {
          result.push(at + "/" + key + " (only the reference)")
        }
      }
      result
    }
    (Array(x), Array(y)) if x.length() == y.length() => {
      let result = []
      for i, value in x {
        result.append(json_differences(value, y[i], at + "/" + i.to_string()))
      }
      result
    }
    _ => if a == b { [] } else { [if at == "" { "/" } else { at }] }
  }
}

///|
fn our_events(
  session : @core.Session,
  where_ : String,
  files : Array[(String, String)],
) -> Array[String] raise {
  match @core.handle(session, ValidateFiles(seq=1, files~)) {
    Diagnostics(items~, ..) =>
      items
      .filter(d => @model.is_compared(d.severity))
      .map(d => @model.event_key(d.code, d.severity, d.shape))
    Blocked(reason~, ..) => fail(where_ + ": validation was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
}

///|
fn our_json_schema(
  session : @core.Session,
  where_ : String,
  lesson : @model.Lesson,
  files : Array[(String, String)],
) -> Json raise {
  guard lesson.output is Some(output) else {
    fail(where_ + ": the reference has a JSON Schema, but the lesson has no output")
  }
  match
    @core.handle(
      session,
      TransformFiles(seq=2, files~, output~, selector=lesson.selector),
    ) {
    Transformed(files=out, ..) =>
      match out.search_by(f => f.0 == "schema.json") {
        Some(i) => parse_json(where_ + " schema.json", out[i].1)
        None => fail(where_ + ": the output has no schema.json")
      }
    Blocked(reason~, ..) => fail(where_ + ": the output was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
}

///|
/// The tour, the reference results and the allow list.
fn inputs() -> (@model.Tour, Map[String, ReferenceCase], Array[Allowed]) raise {
  let tour = match @source.read_tour(lessons_root) {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  (
    tour,
    parse_reference(read_text(reference_path)),
    parse_allow(read_text(allow_path)),
  )
}

///|
fn reference_of(
  reference : Map[String, ReferenceCase],
  where_ : String,
) -> ReferenceCase raise {
  match reference.get(where_) {
    Some(entry) => entry
    None =>
      fail(
        where_ +
        ": the reference result is missing or stale; run `mise run reference:tour`",
      )
  }
}

///|
/// Compare our events and JSON Schema with the reference for every case, and
/// mark the allow list entries that remove something.
fn compare_all(
  tour : @model.Tour,
  reference : Map[String, ReferenceCase],
  allow : Array[Allowed],
  events~ : Bool,
  json_schema~ : Bool,
) -> Array[Bool] raise {
  let used = allow.map(_ => false)
  let session = @core.Session::new()
  for lesson in tour.lessons {
    for case in lesson.cases {
      let where_ = lesson.dir + "/" + case.name
      let files = files_of(lesson.case_files(case))
      let expected = reference_of(reference, where_)
      let ours = our_events(session, where_, files)
      let theirs = expected.events.copy()
      remove_allowed_events(where_, ours, theirs, allow, used)
      ours.sort_by(@model.compare_code_units)
      theirs.sort_by(@model.compare_code_units)
      if events && ours != theirs {
        fail(
          where_ +
          ": our events differ from the reference.\n  ours:      " +
          show(ours) +
          "\n  reference: " +
          show(theirs),
        )
      }
      guard expected.json_schema is Some(schema) else { continue }
      let mine = our_json_schema(session, where_, lesson, files)
      let theirs = parse_json(reference_path, schema.stringify())
      for i, entry in allow {
        guard entry.case_id == where_ &&
          entry.difference is JsonSchema(pointer~) else {
          continue
        }
        let a = remove_pointer(mine, pointer)
        let b = remove_pointer(theirs, pointer)
        if a || b {
          used[i] = true
        }
      }
      if json_schema && mine != theirs {
        fail(
          where_ +
          ": our JSON Schema differs from the reference at " +
          show(json_differences(mine, theirs, "")),
        )
      }
    }
  }
  used
}

///|
test "every lesson case has a fresh reference result" {
  let (tour, reference, _) = inputs()
  let known : Array[String] = []
  for lesson in tour.lessons {
    for case in lesson.cases {
      let where_ = lesson.dir + "/" + case.name
      known.push(where_)
      let entry = reference_of(reference, where_)
      if entry.digest != @model.digest(lesson.case_files(case)) {
        fail(
          where_ +
          ": the reference result is missing or stale; run `mise run reference:tour`",
        )
      }
    }
  }
  for id, _ in reference {
    if !known.contains(id) {
      fail(
        id +
        ": the reference has a result for a case that does not exist; run `mise run reference:tour`",
      )
    }
  }
}

///|
test "our events agree with the reference events" {
  let (tour, reference, allow) = inputs()
  ignore(compare_all(tour, reference, allow, events=true, json_schema=false))
}

///|
test "our JSON Schema agrees with the reference JSON Schema" {
  let (tour, reference, allow) = inputs()
  ignore(compare_all(tour, reference, allow, events=false, json_schema=true))
}

///|
test "every allow list entry is used, has an issue, and its lesson says so" {
  let (tour, reference, allow) = inputs()
  let used = compare_all(tour, reference, allow, events=false, json_schema=false)
  for i, entry in allow {
    let where_ = allow_path + " entry " + i.to_string() + " (" + entry.case_id + ")"
    if !used[i] {
      fail(where_ + ": stale allow entry; it removes nothing")
    }
    if !is_issue(entry.issue) {
      fail(where_ + ": the issue \"" + entry.issue + "\" must match smithy-[a-z0-9.]+")
    }
    if entry.reason.trim().is_empty() {
      fail(where_ + ": the entry has no reason")
    }
    let dir = entry.case_id.split("/").next().unwrap_or("").to_owned()
    match tour.lessons.search_by(l => l.dir == dir) {
      Some(l) if tour.lessons[l].text.contains(difference_note) => ()
      Some(_) => fail(where_ + ": " + dir + "/lesson.md has no \"" + difference_note + "\" note")
      None => fail(where_ + ": no lesson has the folder " + dir)
    }
  }
}

///|
/// Whether the text is a beads issue id: `smithy-` and then `[a-z0-9.]+`.
fn is_issue(text : String) -> Bool {
  guard text.has_prefix("smithy-") && text.length() > 7 else { return false }
  text[7:].iter().all(c => c.is_ascii_lowercase() || c.is_ascii_digit() || c == '.')
}

///|
test "an issue id is smithy- and lower-case letters, digits and dots" {
  assert_true(is_issue("smithy-2qe"))
  assert_true(is_issue("smithy-2qe.4"))
  assert_false(is_issue("smithy-"))
  assert_false(is_issue("smithy-ABC"))
  assert_false(is_issue("bd-12"))
}

///|
test "an allowed event is removed once, from the side that the entry names" {
  let allow : Array[Allowed] = [
    {
      case_id: "01-a/start",
      difference: Event(event="X|ERROR|-", side=Ours),
      reason: "r",
      issue: "smithy-1",
    },
    {
      case_id: "01-a/start",
      difference: Event(event="Y|WARNING|-", side=Reference),
      reason: "r",
      issue: "smithy-1",
    },
    {
      case_id: "01-a/other",
      difference: Event(event="X|ERROR|-", side=Ours),
      reason: "r",
      issue: "smithy-1",
    },
    {
      case_id: "01-a/start",
      difference: Event(event="Z|ERROR|-", side=Ours),
      reason: "r",
      issue: "smithy-1",
    },
  ]
  let ours = ["X|ERROR|-", "X|ERROR|-", "Y|WARNING|-"]
  let theirs = ["X|ERROR|-", "Y|WARNING|-"]
  let used = allow.map(_ => false)
  remove_allowed_events("01-a/start", ours, theirs, allow, used)
  assert_eq(ours, ["X|ERROR|-", "Y|WARNING|-"])
  assert_eq(theirs, ["X|ERROR|-"])
  assert_eq(used, [true, true, false, false])
}

///|
test "a JSON pointer removes one member or item, and reports a missing one" {
  let json = parse_json(
    "test",
    "{\"definitions\": {\"a/b\": {\"x\": 1}, \"c~d\": [1, 2]}}",
  )
  assert_true(remove_pointer(json, "/definitions/a~1b/x"))
  assert_true(remove_pointer(json, "/definitions/c~0d/0"))
  assert_false(remove_pointer(json, "/definitions/missing"))
  assert_false(remove_pointer(json, "/definitions/c~0d/5"))
  assert_eq(json, parse_json("test", "{\"definitions\": {\"a/b\": {}, \"c~d\": [2]}}"))
}

///|
test "the JSON differences name the pointers" {
  let a = parse_json("test", "{\"a\": 1, \"b\": {\"c\": true}, \"d\": 2}")
  let b = parse_json("test", "{\"a\": 1, \"b\": {\"c\": false}, \"e\": 2}")
  assert_eq(json_differences(a, b, ""), [
    "/b/c", "/d (only ours)", "/e (only the reference)",
  ])
}

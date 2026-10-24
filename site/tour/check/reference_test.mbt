///|
/// The Java reference results, written by `mise run reference:tour`.
let reference_path : String = "tour/reference-events.json"

///|
/// The known differences from the Java reference. Each entry has `case`
/// (`<dir>/<case>`), `kind`, `reason` and `issue`. Kind `event` has `event`
/// and `side` (`ours` or `reference`), and removes one copy of the event from
/// that side. Kind `json_schema` has `pointer` and no `side`, and removes the
/// value at the pointer from both JSON Schema documents.
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
  events : Array[@model.EventKey]
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
  Event(event~ : @model.EventKey, side~ : Side)
  /// The value at the JSON pointer is removed from both JSON Schema documents.
  JsonSchema(pointer~ : String)
}

///|
/// One entry of the allow list.
struct Allowed {
  case_id : @model.CaseId
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
fn event_member(
  json : Json,
  key : String,
  where_ : String,
) -> @model.EventKey raise {
  let text = string_member(json, key, where_)
  match @model.EventKey::parse(text) {
    Some(event) => event
    None =>
      fail(where_ + ": \"" + text + "\" is not an event id|SEVERITY|shape")
  }
}

///|
fn case_id_of(text : String, where_ : String) -> @model.CaseId raise {
  match @model.CaseId::parse(text) {
    Some(id) => id
    None => fail(where_ + ": \"" + text + "\" is not a case <dir>/<case>")
  }
}

///|
fn parse_reference(text : String) -> Map[@model.CaseId, ReferenceCase] raise {
  guard parse_json(reference_path, text)
    is { "reference_sha": String(sha), "cases": Object(cases), .. } else {
    fail(reference_path + ": I expected \"reference_sha\" and \"cases\"")
  }
  guard sha == reference_sha else {
    fail(
      reference_path +
      ": the reference SHA is " +
      sha +
      ", not " +
      reference_sha,
    )
  }
  let result : Map[@model.CaseId, ReferenceCase] = Map([])
  for id, entry in cases {
    guard entry is { "digest": String(digest), "events": Array(events), .. } else {
      fail(reference_path + ": " + id + " needs \"digest\" and \"events\"")
    }
    result[case_id_of(id, reference_path)] = {
      digest,
      events: events.map(e => {
        guard e is String(s) && @model.EventKey::parse(s) is Some(event) else {
          fail(
            reference_path +
            ": " +
            id +
            ": an event must be a string id|SEVERITY|shape",
          )
        }
        event
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
    let case_id = case_id_of(string_member(entry, "case", where_), where_)
    let difference = match string_member(entry, "kind", where_) {
      "event" =>
        Event(
          event=event_member(entry, "event", where_),
          side=match string_member(entry, "side", where_) {
            "ours" => Ours
            "reference" => Reference
            other =>
              fail(
                where_ +
                ": \"side\" must be \"ours\" or \"reference\", not \"" +
                other +
                "\"",
              )
          },
        )
      "json_schema" => {
        if entry is { "side": _, .. } {
          fail(
            where_ +
            ": \"side\" is for kind \"event\" only; a json_schema entry removes the pointer from both sides",
          )
        }
        JsonSchema(pointer=string_member(entry, "pointer", where_))
      }
      other =>
        fail(
          where_ +
          ": \"kind\" must be \"event\" or \"json_schema\", not \"" +
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
  case_id : @model.CaseId,
  ours : Array[@model.EventKey],
  reference : Array[@model.EventKey],
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
  .map(key => {
    key.to_owned().replace_all(old="~1", new="/").replace_all(old="~0", new="~")
  })
  .to_array()
}

///|
/// The array index of a pointer key: decimal digits only.
fn array_index(key : String) -> Int32? {
  guard !key.is_empty() && key.length() < 10 else { return None }
  let mut index = 0
  for c in key {
    guard c.is_ascii_digit() else { return None }
    index = index * 10 + (c.to_int() - '0'.to_int())
  }
  Some(index)
}

///|
/// Remove the value at the pointer, and give it. The result is `None` when no
/// value is there.
fn remove_pointer(json : Json, pointer : String) -> Json? raise {
  let keys = pointer_keys(pointer)
  let mut node = json
  for i, key in keys {
    let last = i == keys.length() - 1
    match node {
      Object(members) =>
        match members.get(key) {
          None => return None
          Some(value) if last => {
            members.remove(key)
            return Some(value)
          }
          Some(child) => node = child
        }
      Array(items) =>
        match array_index(key) {
          Some(index) if index < items.length() =>
            if last {
              return Some(items.remove(index))
            } else {
              node = items[index]
            }
          _ => return None
        }
      _ => return None
    }
  }
  None
}

///|
/// Remove the value at the pointer from both documents. The result is true
/// only when the values differ, or only one document has a value there.
fn removes_difference(
  ours : Json,
  reference : Json,
  pointer : String,
) -> Bool raise {
  remove_pointer(ours, pointer) != remove_pointer(reference, pointer)
}

///|
/// The key as a JSON pointer token: `~` becomes `~0` and `/` becomes `~1`.
fn pointer_token(key : String) -> String {
  key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
/// The pointers where two JSON values differ, for the failure message.
fn json_differences(a : Json, b : Json, at : String) -> Array[String] {
  match (a, b) {
    (Object(x), Object(y)) => {
      let result = []
      for key, value in x {
        let path = at + "/" + pointer_token(key)
        match y.get(key) {
          Some(other) => result.append(json_differences(value, other, path))
          None => result.push(path + " (only ours)")
        }
      }
      for key, _ in y {
        if !x.contains(key) {
          result.push(at + "/" + pointer_token(key) + " (only the reference)")
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
) -> Array[@model.EventKey] raise {
  match @core.handle(session, ValidateFiles(seq=1, files~)) {
    Diagnostics(items~, ..) => compared(items)
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
    fail(
      where_ + ": the reference has a JSON Schema, but the lesson has no output",
    )
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
fn inputs() -> (@model.Tour, Map[@model.CaseId, ReferenceCase], Array[Allowed]) raise {
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
fn stale(where_ : String) -> String {
  where_ +
  ": the reference result is missing or stale; run `mise run reference:tour`"
}

///|
/// Whether the reference must have a JSON Schema: the lesson output is JSON
/// Schema, and the reference events have no ERROR or DANGER.
fn needs_json_schema(
  output : @core.Output?,
  events : Array[@model.EventKey],
) -> Bool {
  output is Some(JsonSchema) && !events.any(e => e.severity.blocks_output())
}

///|
/// Fail when the reference result is not the result of these case files and
/// this lesson output.
fn check_fresh(
  where_ : String,
  entry : ReferenceCase,
  digest : String,
  output : @core.Output?,
) -> Unit raise {
  if entry.digest != digest ||
    (entry.json_schema is Some(_)) != needs_json_schema(output, entry.events) {
    fail(stale(where_))
  }
}

///|
fn reference_of(
  reference : Map[@model.CaseId, ReferenceCase],
  case_id : @model.CaseId,
) -> ReferenceCase raise {
  match reference.get(case_id) {
    Some(entry) => entry
    None => fail(stale(case_id.to_string()))
  }
}

///|
/// Compare our events and JSON Schema with the reference for every case, and
/// mark the allow list entries that remove a difference.
fn compare_all(
  tour : @model.Tour,
  reference : Map[@model.CaseId, ReferenceCase],
  allow : Array[Allowed],
  events~ : Bool,
  json_schema~ : Bool,
) -> Array[Bool] raise {
  let used = allow.map(_ => false)
  let session = @core.Session::new()
  for lesson in tour.lessons {
    for case in lesson.cases {
      let case_id = lesson.case_id(case)
      let where_ = case_id.to_string()
      let files = files_of(lesson.case_files(case))
      let expected = reference_of(reference, case_id)
      let ours = our_events(session, where_, files)
      let theirs = expected.events.copy()
      remove_allowed_events(case_id, ours, theirs, allow, used)
      ours.sort_by(@model.compare_events)
      theirs.sort_by(@model.compare_events)
      if events && ours != theirs {
        fail(
          where_ +
          ": our events differ from the reference.\n  ours:      " +
          show_events(ours) +
          "\n  reference: " +
          show_events(theirs),
        )
      }
      guard expected.json_schema is Some(schema) else { continue }
      let mine = our_json_schema(session, where_, lesson, files)
      let theirs = parse_json(reference_path, schema.stringify())
      for i, entry in allow {
        guard entry.case_id == case_id &&
          entry.difference is JsonSchema(pointer~) else {
          continue
        }
        if removes_difference(mine, theirs, pointer) {
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
  let known : Array[@model.CaseId] = []
  for lesson in tour.lessons {
    for case in lesson.cases {
      let case_id = lesson.case_id(case)
      known.push(case_id)
      let entry = reference_of(reference, case_id)
      check_fresh(
        case_id.to_string(),
        entry,
        @model.digest(lesson.case_files(case)),
        lesson.output,
      )
    }
  }
  for id, _ in reference {
    if !known.contains(id) {
      fail(
        id.to_string() +
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
  let used = compare_all(
    tour,
    reference,
    allow,
    events=false,
    json_schema=false,
  )
  for i, entry in allow {
    let where_ = allow_path +
      " entry " +
      i.to_string() +
      " (" +
      entry.case_id.to_string() +
      ")"
    if !used[i] {
      fail(where_ + ": stale allow entry; it removes no difference")
    }
    if !is_issue(entry.issue) {
      fail(
        where_ +
        ": the issue \"" +
        entry.issue +
        "\" must match smithy-[a-z0-9.]+",
      )
    }
    if entry.reason.trim().is_empty() {
      fail(where_ + ": the entry has no reason")
    }
    let dir = entry.case_id.dir
    match tour.lessons.search_by(l => l.dir == dir) {
      Some(l) if tour.lessons[l].text.contains(difference_note) => ()
      Some(_) =>
        fail(
          where_ +
          ": " +
          dir +
          "/lesson.md has no \"" +
          difference_note +
          "\" note",
        )
      None => fail(where_ + ": no lesson has the folder " + dir)
    }
  }
}

///|
/// Whether the text is a beads issue id: `smithy-` and then `[a-z0-9.]+`.
fn is_issue(text : String) -> Bool {
  guard text.has_prefix("smithy-") && text.length() > 7 else { return false }
  text[7:]
  .iter()
  .all(c => c.is_ascii_lowercase() || c.is_ascii_digit() || c == '.')
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
  let start : @model.CaseId = { dir: "01-a", name: "start", }
  let other : @model.CaseId = { dir: "01-a", name: "other", }
  let x : @model.EventKey = { id: "X", severity: Error, shape: None, }
  let y : @model.EventKey = { id: "Y", severity: Warning, shape: None, }
  let z : @model.EventKey = { id: "Z", severity: Error, shape: None, }
  let allow : Array[Allowed] = [
    {
      case_id: start,
      difference: Event(event=x, side=Ours),
      reason: "r",
      issue: "smithy-1",
    },
    {
      case_id: start,
      difference: Event(event=y, side=Reference),
      reason: "r",
      issue: "smithy-1",
    },
    {
      case_id: other,
      difference: Event(event=x, side=Ours),
      reason: "r",
      issue: "smithy-1",
    },
    {
      case_id: start,
      difference: Event(event=z, side=Ours),
      reason: "r",
      issue: "smithy-1",
    },
  ]
  let ours = [x, x, y]
  let theirs = [x, y]
  let used = allow.map(_ => false)
  remove_allowed_events(start, ours, theirs, allow, used)
  assert_eq(ours, [x, y])
  assert_eq(theirs, [x])
  assert_eq(used, [true, true, false, false])
}

///|
test "a JSON pointer removes one member or item, and reports a missing one" {
  let json = parse_json(
    "test", "{\"definitions\": {\"a/b\": {\"x\": 1}, \"c~d\": [1, 2]}}",
  )
  assert_eq(remove_pointer(json, "/definitions/a~1b/x"), Some(Json::number(1)))
  assert_eq(remove_pointer(json, "/definitions/c~0d/0"), Some(Json::number(1)))
  assert_eq(remove_pointer(json, "/definitions/missing"), None)
  assert_eq(remove_pointer(json, "/definitions/c~0d/5"), None)
  assert_eq(
    json,
    parse_json("test", "{\"definitions\": {\"a/b\": {}, \"c~d\": [2]}}"),
  )
}

///|
test "the JSON differences name the pointers" {
  let a = parse_json("test", "{\"a\": 1, \"b\": {\"c\": true}, \"d/~\": 2}")
  let b = parse_json("test", "{\"a\": 1, \"b\": {\"c\": false}, \"e/~\": 2}")
  assert_eq(json_differences(a, b, ""), [
    "/b/c", "/d~1~0 (only ours)", "/e~1~0 (only the reference)",
  ])
}

///|
test "a JSON Schema lesson needs a reference schema unless the case has an error" {
  let schema = Some(Json::object({}))
  let entry = fn(events : Array[String], json_schema : Json?) -> ReferenceCase {
    {
      digest: "d",
      events: events.map(e => @model.EventKey::parse(e).unwrap()),
      json_schema,
    }
  }
  check_fresh("a", entry([], schema), "d", Some(JsonSchema))
  check_fresh("a", entry(["W|WARNING|-"], schema), "d", Some(JsonSchema))
  check_fresh("a", entry(["E|ERROR|-"], None), "d", Some(JsonSchema))
  check_fresh("a", entry(["E|DANGER|-"], None), "d", Some(JsonSchema))
  check_fresh("a", entry([], None), "d", Some(JsonAst))
  check_fresh("a", entry([], None), "d", None)
  let stale_message = "a: the reference result is missing or stale; run `mise run reference:tour`"
  for
    bad in [
      (entry([], None), "d", Some(@core.Output::JsonSchema)),
      (entry([], schema), "d", Some(@core.Output::JsonAst)),
      (entry([], schema), "d", None),
      (entry(["E|ERROR|-"], schema), "d", Some(@core.Output::JsonSchema)),
      (entry([], None), "other", None),
    ] {
    try check_fresh("a", bad.0, bad.1, bad.2) catch {
      Failure(message) => assert_true(message.has_suffix(stale_message))
      e => fail("unexpected error: " + e.to_string())
    } noraise {
      _ => fail("a stale result passed")
    }
  }
}

///|
test "a json_schema allow entry is used only when it removes a difference" {
  let ours = parse_json("test", "{\"a\": 1, \"b\": 2, \"c\": 3}")
  let theirs = parse_json("test", "{\"a\": 1, \"b\": 5}")
  let used = ["/a", "/b", "/c", "/d"].map(pointer => {
    removes_difference(ours, theirs, pointer)
  })
  assert_eq(used, [false, true, true, false])
  assert_eq(ours, parse_json("test", "{}"))
  assert_eq(theirs, parse_json("test", "{}"))
}

///|
test "a json_schema allow entry must not name a side" {
  let text = "[{\"case\": \"01-a/start\", \"kind\": \"json_schema\", \"pointer\": \"/a\", \"side\": \"ours\", \"reason\": \"r\", \"issue\": \"smithy-1\"}]"
  try parse_allow(text) catch {
    Failure(message) =>
      assert_true(message.contains("\"side\" is for kind \"event\" only"))
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a json_schema entry with a side was accepted")
  }
}

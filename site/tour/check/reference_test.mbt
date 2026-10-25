///|
/// The Java reference results, written by `mise run reference:tour`.
let reference_path : String = "tour/reference-events.json"

///|
/// The known differences from the Java reference. Each entry has `case`
/// (`<dir>/<case>`), `kind`, `reason` and `issue`. Kind `event` has `event`
/// and `side` (`ours` or `reference`), and removes one copy of the event from
/// that side. Kind `json_schema` has `pointer` and no `side`, and removes the
/// value at the pointer from both JSON Schema documents. Kind `openapi` is the
/// same for the OpenAPI documents. Kind `json_ast` is the same for the JSON AST
/// documents. Kind `selector` has `shape` and `side`, and
/// removes one copy of the shape id from the selected shapes of that side.
let allow_path : String = "tour/reference-allow.json"

///|
/// The `smithy-lang/smithy` commit of the reference results. It is the commit
/// of the vendored prelude, as for the other reference scripts.
let reference_sha : String = "30bdab593f0c2cdf96036782cc3ce15c43a711ef"

///|
/// The commit of the vendored prelude, written by `scripts/vendor-prelude.mbtx`.
let prelude_sha_path : String = "../pkgs/smithy/PRELUDE_SHA"

///|
/// The smithy.rpc trait definitions that `scripts/reference-tour.mbtx` adds to
/// a Java case whose files name the namespace, as the playground core always
/// loads them.
let smithy_rpc_path : String = "tour/smithy-rpc-traits.smithy"

///|
/// The name of the smithy.rpc definitions in the digest of a case that uses
/// them. A lesson file name ends in `.smithy`, so no case file has this name.
let smithy_rpc_source : String = "<smithy-rpc-traits>"

///|
/// The digest of the reference result of a case: `@model.digest` of the case
/// files and, when a file names `smithy.rpc#`, of the definitions as the file
/// `smithy_rpc_source`. A change of the definitions then makes the result
/// stale, as `scripts/reference-tour.mbtx` computes it.
fn reference_digest(
  files : Array[@model.LessonFile],
  definitions : String,
) -> String {
  if files.any(f => f.text.contains("smithy.rpc#")) {
    @model.digest(files + [{ name: smithy_rpc_source, text: definitions, }])
  } else {
    @model.digest(files)
  }
}

///|
/// The line that a lesson with a known difference must contain.
let difference_note : String = "> **Reference difference:**"

///|
/// The result of the Java reference for one case.
struct ReferenceCase {
  digest : String
  events : Array[@model.EventKey]
  json_schema : Json?
  /// None: no entry. Some(null): the reference conversion failed.
  openapi : Json?
  /// None: no entry. Some(null): the reference selector did not parse.
  selector : Json?
  json_ast : Json?
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
  /// The value at the JSON pointer is removed from both OpenAPI documents.
  OpenApi(pointer~ : String)
  /// The value at the JSON pointer is removed from both JSON AST documents.
  JsonAst(pointer~ : String)
  /// The shape id is removed from the selected shapes of the named side only.
  Selected(shape~ : String, side~ : Side)
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
      openapi: match entry {
        { "openapi": document, .. } => Some(document)
        _ => None
      },
      selector: match entry {
        { "selector": selected, .. } => Some(selected)
        _ => None
      },
      json_ast: match entry {
        { "json_ast": document, .. } => Some(document)
        _ => None
      },
    }
  }
  result
}

///|
fn side_member(entry : Json, where_ : String) -> Side raise {
  match string_member(entry, "side", where_) {
    "ours" => Ours
    "reference" => Reference
    other =>
      fail(
        where_ +
        ": \"side\" must be \"ours\" or \"reference\", not \"" +
        other +
        "\"",
      )
  }
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
          side=side_member(entry, where_),
        )
      "selector" =>
        Selected(
          shape=string_member(entry, "shape", where_),
          side=side_member(entry, where_),
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
      "openapi" => {
        if entry is { "side": _, .. } {
          fail(
            where_ +
            ": \"side\" is for kind \"event\" only; an openapi entry removes the pointer from both sides",
          )
        }
        OpenApi(pointer=string_member(entry, "pointer", where_))
      }
      "json_ast" => {
        if entry is { "side": _, .. } {
          fail(
            where_ +
            ": \"side\" is for kind \"event\" only; a json_ast entry removes the pointer from both sides",
          )
        }
        JsonAst(pointer=string_member(entry, "pointer", where_))
      }
      other =>
        fail(
          where_ +
          ": \"kind\" must be \"event\", \"json_schema\", \"openapi\", \"json_ast\" or \"selector\", not \"" +
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
/// The array index of a pointer key: `0`, or decimal digits without a leading
/// zero (RFC 6901).
fn array_index(key : String) -> Int32? {
  guard !key.is_empty() &&
    key.length() < 10 &&
    (key == "0" || !key.has_prefix("0")) else {
    return None
  }
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
  output : @core.Output?,
) -> Array[@model.EventKey] raise {
  match @core.handle(session, @core.lesson_validate(seq=1, files~, output~)) {
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
  selector : String?,
) -> Json raise {
  guard lesson.output is Some(output) else {
    fail(
      where_ + ": the reference has a JSON Schema, but the lesson has no output",
    )
  }
  match
    @core.handle(session, TransformFiles(seq=2, files~, output~, selector~)) {
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
/// Our JSON AST: the `model.json` file of the transform.
fn our_json_ast(
  session : @core.Session,
  where_ : String,
  lesson : @model.Lesson,
  files : Array[(String, String)],
  selector : String?,
) -> Json raise {
  guard lesson.output is Some(output) else {
    fail(
      where_ + ": the reference has a JSON AST, but the lesson has no output",
    )
  }
  match
    @core.handle(session, TransformFiles(seq=2, files~, output~, selector~)) {
    Transformed(files=out, ..) =>
      match out.search_by(f => f.0 == "model.json") {
        Some(i) => parse_json(where_ + " model.json", out[i].1)
        None => fail(where_ + ": the output has no model.json")
      }
    Blocked(reason~, ..) => fail(where_ + ": the output was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
}

///|
/// Our OpenAPI document, or None when the transform is blocked (the model
/// has no single service with a protocol trait, or the conversion fails).
fn our_openapi(
  session : @core.Session,
  where_ : String,
  lesson : @model.Lesson,
  files : Array[(String, String)],
  selector : String?,
) -> Json? raise {
  guard lesson.output is Some(output) else {
    fail(
      where_ +
      ": the reference has an OpenAPI document, but the lesson has no output",
    )
  }
  match
    @core.handle(session, TransformFiles(seq=2, files~, output~, selector~)) {
    Transformed(files=out, ..) =>
      match out.search_by(f => f.0.has_suffix(".openapi.json")) {
        Some(i) => Some(parse_json(where_ + " OpenAPI", out[i].1))
        None => fail(where_ + ": the output has no .openapi.json file")
      }
    Blocked(kind=Other, ..) => None
    Blocked(reason~, ..) => fail(where_ + ": the output was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
}

///|
/// The two documents to compare. Both sides must agree on failure: a blocked
/// output of ours goes with a failed reference conversion (null).
fn document_pair(
  where_ : String,
  ours : Json?,
  reference : Json,
) -> (Json, Json)? raise {
  match (ours, reference) {
    (None, Null) => None
    (Some(_), Null) =>
      fail(
        where_ +
        ": the reference OpenAPI conversion failed, but ours gave a document",
      )
    (None, _) =>
      fail(
        where_ +
        ": our OpenAPI output was blocked, but the reference gave a document",
      )
    (Some(a), b) => Some((a, b))
  }
}

///|
/// The shape ids that our selector selects, one per line of `selector.txt`, or
/// None when the transform is blocked (the selector does not parse).
fn our_selection(
  session : @core.Session,
  where_ : String,
  lesson : @model.Lesson,
  files : Array[(String, String)],
  selector : String?,
) -> Array[String]? raise {
  guard lesson.output is Some(output) else {
    fail(
      where_ + ": the reference has a selection, but the lesson has no output",
    )
  }
  match
    @core.handle(session, TransformFiles(seq=2, files~, output~, selector~)) {
    Transformed(files=out, ..) =>
      match out.search_by(f => f.0 == "selector.txt") {
        Some(i) =>
          Some(
            out[i].1
            .split("\n")
            .filter(l => l != "")
            .map(l => l.to_owned())
            .collect(),
          )
        None => fail(where_ + ": the output has no selector.txt")
      }
    Blocked(kind=Other, ..) => None
    Blocked(reason~, ..) => fail(where_ + ": the output was blocked: " + reason)
    _ => fail(where_ + ": unexpected answer")
  }
}

///|
/// The two selections to compare. Both sides must agree on failure: a blocked
/// output of ours goes with a reference selector that did not parse (null).
fn selection_pair(
  where_ : String,
  ours : Array[String]?,
  reference : Json,
) -> (Array[String], Array[String])? raise {
  match (ours, reference) {
    (None, Null) => None
    (Some(_), Null) =>
      fail(where_ + ": the reference selector failed, but ours gave a result")
    (None, _) =>
      fail(where_ + ": our selector failed, but the reference gave a result")
    (Some(a), Array(items)) =>
      Some(
        (
          a,
          items.map(item => {
            guard item is String(id) else {
              fail(
                reference_path +
                ": " +
                where_ +
                ": a selected shape must be a string",
              )
            }
            id
          }),
        ),
      )
    (Some(_), _) =>
      fail(
        reference_path +
        ": " +
        where_ +
        ": the selector must be an array or null",
      )
  }
}

///|
/// The tour, the reference results and the allow list.
fn inputs() -> (@model.Tour, Map[@model.CaseId, ReferenceCase], Array[Allowed]) raise {
  let tour = match @source.read_tour(lessons_root, repo="..") {
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
/// Whether the reference must have a JSON AST: the lesson output is JsonAst,
/// and the reference events have no ERROR or DANGER.
fn needs_json_ast(
  output : @core.Output?,
  events : Array[@model.EventKey],
) -> Bool {
  output is Some(JsonAst) && !events.any(e => e.severity.blocks_output())
}

///|
/// Whether the reference must have an OpenAPI entry: the lesson output is
/// OpenApi30 or OpenApi31, and the reference events have no ERROR or DANGER.
fn needs_openapi(
  output : @core.Output?,
  events : Array[@model.EventKey],
) -> Bool {
  (output is Some(OpenApi30) || output is Some(OpenApi31)) &&
  !events.any(e => e.severity.blocks_output())
}

///|
/// Whether the reference must have a selector entry: the lesson output is
/// Selector, and the reference events have no ERROR or DANGER.
fn needs_selector(
  output : @core.Output?,
  events : Array[@model.EventKey],
) -> Bool {
  output is Some(Selector) && !events.any(e => e.severity.blocks_output())
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
    (entry.json_schema is Some(_)) != needs_json_schema(output, entry.events) ||
    (entry.openapi is Some(_)) != needs_openapi(output, entry.events) ||
    (entry.selector is Some(_)) != needs_selector(output, entry.events) ||
    (entry.json_ast is Some(_)) != needs_json_ast(output, entry.events) {
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
/// Compare our OpenAPI document with the reference one for a case. An allow
/// entry of the case with kind `openapi` removes its pointer from both
/// documents, and is marked used when that removes a difference. Fail on a
/// difference that remains when `openapi` is true.
fn compare_openapi(
  case_id : @model.CaseId,
  ours : Json?,
  reference : Json,
  allow : Array[Allowed],
  used : Array[Bool],
  openapi~ : Bool,
) -> Unit raise {
  let where_ = case_id.to_string()
  guard document_pair(where_, ours, reference) is Some((mine, theirs)) else {
    return
  }
  for i, entry in allow {
    guard entry.case_id == case_id && entry.difference is OpenApi(pointer~) else {
      continue
    }
    if removes_difference(mine, theirs, pointer) {
      used[i] = true
    }
  }
  if openapi && mine != theirs {
    fail(
      where_ +
      ": our OpenAPI differs from the reference at " +
      show(json_differences(mine, theirs, "")),
    )
  }
}

///|
/// Compare our JSON AST with the reference one for a case. An allow entry of
/// the case with kind `json_ast` removes its pointer from both documents, and
/// is marked used when that removes a difference. Fail on a difference that
/// remains when `json_ast` is true.
fn compare_json_ast(
  case_id : @model.CaseId,
  mine : Json,
  theirs : Json,
  allow : Array[Allowed],
  used : Array[Bool],
  json_ast~ : Bool,
) -> Unit raise {
  let where_ = case_id.to_string()
  for i, entry in allow {
    guard entry.case_id == case_id && entry.difference is JsonAst(pointer~) else {
      continue
    }
    if removes_difference(mine, theirs, pointer) {
      used[i] = true
    }
  }
  if json_ast && mine != theirs {
    fail(
      where_ +
      ": our JSON AST differs from the reference at " +
      show(json_differences(mine, theirs, "")),
    )
  }
}

///|
/// Compare our selected shapes with the reference ones for a case. An allow
/// entry of the case with kind `selector` removes one copy of its shape from the
/// side that it names, and is marked used when it removes one. Fail on a
/// difference that remains when `selector` is true.
fn compare_selector(
  case_id : @model.CaseId,
  ours : Array[String]?,
  reference : Json,
  allow : Array[Allowed],
  used : Array[Bool],
  selector~ : Bool,
) -> Unit raise {
  let where_ = case_id.to_string()
  guard selection_pair(where_, ours, reference) is Some((mine, theirs)) else {
    return
  }
  for i, entry in allow {
    guard entry.case_id == case_id &&
      entry.difference is Selected(shape~, side~) else {
      continue
    }
    let selected = match side {
      Ours => mine
      Reference => theirs
    }
    if selected.search(shape) is Some(j) {
      selected.remove(j) |> ignore
      used[i] = true
    }
  }
  mine.sort_by(@model.compare_code_units)
  theirs.sort_by(@model.compare_code_units)
  if selector && mine != theirs {
    fail(
      where_ +
      ": our selected shapes differ from the reference.\n  ours:      " +
      mine.join(" ") +
      "\n  reference: " +
      theirs.join(" "),
    )
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
  openapi~ : Bool,
  selector~ : Bool,
  json_ast~ : Bool,
) -> Array[Bool] raise {
  let used = allow.map(_ => false)
  let session = @core.Session::new()
  for lesson in tour.lessons {
    for case in lesson.cases {
      let case_id = lesson.case_id(case)
      let where_ = case_id.to_string()
      let files = files_of(
        @model.model_files(lesson.engine, lesson.case_files(case)),
      )
      let query = @model.query_of(
        lesson.case_files(case),
        fixed=lesson.selector,
      )
      let expected = reference_of(reference, case_id)
      let ours = our_events(session, where_, files, lesson.output)
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
      if expected.json_schema is Some(schema) {
        let mine = our_json_schema(session, where_, lesson, files, query)
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
      if expected.openapi is Some(document) {
        let theirs = parse_json(reference_path, document.stringify())
        let mine = our_openapi(session, where_, lesson, files, query)
        compare_openapi(case_id, mine, theirs, allow, used, openapi~)
      }
      if expected.json_ast is Some(document) {
        let theirs = parse_json(reference_path, document.stringify())
        let mine = our_json_ast(session, where_, lesson, files, query)
        compare_json_ast(case_id, mine, theirs, allow, used, json_ast~)
      }
      if expected.selector is Some(selected) {
        let mine = our_selection(session, where_, lesson, files, query)
        compare_selector(case_id, mine, selected, allow, used, selector~)
      }
    }
  }
  used
}

///|
test "every lesson case has a fresh reference result" {
  let (tour, reference, _) = inputs()
  let definitions = read_text(smithy_rpc_path)
  let known : Array[@model.CaseId] = []
  for lesson in tour.lessons {
    for case in lesson.cases {
      let case_id = lesson.case_id(case)
      known.push(case_id)
      let entry = reference_of(reference, case_id)
      check_fresh(
        case_id.to_string(),
        entry,
        reference_digest(lesson.case_files(case), definitions),
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
  ignore(
    compare_all(
      tour,
      reference,
      allow,
      events=true,
      json_schema=false,
      openapi=false,
      selector=false,
      json_ast=false,
    ),
  )
}

///|
test "our JSON Schema agrees with the reference JSON Schema" {
  let (tour, reference, allow) = inputs()
  ignore(
    compare_all(
      tour,
      reference,
      allow,
      events=false,
      json_schema=true,
      openapi=false,
      selector=false,
      json_ast=false,
    ),
  )
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
    openapi=false,
    selector=false,
    json_ast=false,
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
test "the reference results use the commit of the vendored prelude" {
  assert_eq(read_text(prelude_sha_path).trim().to_owned(), reference_sha)
}

///|
test "the reference loads the smithy.rpc definitions that the core loads" {
  assert_eq(read_text(smithy_rpc_path), @rpc.trait_definitions())
}

///|
test "the digest of a smithy.rpc case changes when the definitions change" {
  let rpc : Array[@model.LessonFile] = [
    { name: "model.smithy", text: "use smithy.rpc#jsonRpc", },
  ]
  let plain : Array[@model.LessonFile] = [
    { name: "model.smithy", text: "namespace example", },
  ]
  assert_true(reference_digest(rpc, "a") != reference_digest(rpc, "b"))
  assert_eq(
    reference_digest(rpc, "a"),
    @model.digest(rpc + [{ name: smithy_rpc_source, text: "a", }]),
  )
  assert_eq(reference_digest(plain, "a"), @model.digest(plain))
  assert_eq(reference_digest(plain, "b"), @model.digest(plain))
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
test "an array index of a JSON pointer is 0 or has no leading zero" {
  assert_eq(array_index("0"), Some(0))
  assert_eq(array_index("12"), Some(12))
  assert_eq(array_index("01"), None)
  assert_eq(array_index("00"), None)
  assert_eq(array_index(""), None)
  assert_eq(array_index("1a"), None)
  assert_eq(array_index("-1"), None)
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
      openapi: None,
      selector: None,
      json_ast: None,
    }
  }
  check_fresh("a", entry([], schema), "d", Some(JsonSchema))
  check_fresh("a", entry(["W|WARNING|-"], schema), "d", Some(JsonSchema))
  check_fresh("a", entry(["E|ERROR|-"], None), "d", Some(JsonSchema))
  check_fresh("a", entry(["E|DANGER|-"], None), "d", Some(JsonSchema))
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

///|
test "an OpenAPI lesson needs a reference document unless the case has an error" {
  let doc = Some(Json::object({}))
  let entry = fn(events : Array[String], openapi : Json?) -> ReferenceCase {
    {
      digest: "d",
      events: events.map(e => @model.EventKey::parse(e).unwrap()),
      json_schema: None,
      openapi,
      selector: None,
      json_ast: None,
    }
  }
  check_fresh("a", entry([], doc), "d", Some(OpenApi30))
  check_fresh("a", entry([], Some(Json::null())), "d", Some(OpenApi31))
  check_fresh("a", entry(["E|ERROR|-"], None), "d", Some(OpenApi30))
  let stale_message = "a: the reference result is missing or stale; run `mise run reference:tour`"
  for
    bad in [
      (entry([], None), "d", Some(@core.Output::OpenApi30)),
      (entry([], doc), "d", Some(@core.Output::JsonAst)),
      (entry(["E|DANGER|-"], doc), "d", Some(@core.Output::OpenApi31)),
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
test "a failed reference conversion agrees only with a blocked output" {
  let x = Json::object({ "x": Json::number(1.0) })
  let y = Json::object({ "y": Json::number(2.0) })
  assert_true(document_pair("a", None, Json::null()) is None)
  assert_eq(document_pair("a", Some(x), y), Some((x, y)))
  try document_pair("a", Some(x), Json::null()) catch {
    Failure(message) =>
      assert_true(
        message.has_suffix(
          "a: the reference OpenAPI conversion failed, but ours gave a document",
        ),
      )
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a document against a failed conversion passed")
  }
  try document_pair("a", None, y) catch {
    Failure(message) =>
      assert_true(
        message.has_suffix(
          "a: our OpenAPI output was blocked, but the reference gave a document",
        ),
      )
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a blocked output against a document passed")
  }
}

///|
test "an openapi allow entry must not name a side" {
  let text = "[{\"case\": \"01-a/start\", \"kind\": \"openapi\", \"pointer\": \"/a\", \"side\": \"ours\", \"reason\": \"r\", \"issue\": \"smithy-1\"}]"
  try parse_allow(text) catch {
    Failure(message) =>
      assert_true(message.contains("\"side\" is for kind \"event\" only"))
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("an openapi entry with a side was accepted")
  }
}

///|
test "our OpenAPI agrees with the reference OpenAPI" {
  let (tour, reference, allow) = inputs()
  ignore(
    compare_all(
      tour,
      reference,
      allow,
      events=false,
      json_schema=false,
      openapi=true,
      selector=false,
      json_ast=false,
    ),
  )
}

///|
test "the OpenAPI comparison fails on a difference and honors the allow list" {
  let json = (text : String) => parse_json("test", text)
  let ours = json("{\"a\": 1, \"b\": 2}")
  let theirs = json("{\"a\": 1, \"b\": 3}")
  let start : @model.CaseId = { dir: "01-a", name: "start", }
  let other : @model.CaseId = { dir: "01-a", name: "other", }
  let allowed = (case_id : @model.CaseId, pointer : String) => {
    case_id,
    difference: OpenApi(pointer~),
    reason: "r",
    issue: "smithy-1",
  }
  // equal documents pass
  compare_openapi(
    start,
    Some(json("{\"a\": 1}")),
    json("{\"a\": 1}"),
    [],
    [],
    openapi=true,
  )
  // different documents fail with the pointer
  try compare_openapi(start, Some(ours), theirs, [], [], openapi=true) catch {
    Failure(message) =>
      assert_true(
        message.contains(
          "01-a/start: our OpenAPI differs from the reference at [/b",
        ),
      )
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a different document passed")
  }
  // a matching entry is used and the check passes
  let allow = [allowed(start, "/b")]
  let used = [false]
  compare_openapi(
    start,
    Some(json("{\"a\": 1, \"b\": 2}")),
    json("{\"a\": 1, \"b\": 3}"),
    allow,
    used,
    openapi=true,
  )
  assert_eq(used, [true])
  // a wrong case or pointer stays unused and the difference fails
  for wrong in [allowed(other, "/b"), allowed(start, "/c")] {
    let used = [false]
    try
      compare_openapi(
        start,
        Some(json("{\"a\": 1, \"b\": 2}")),
        json("{\"a\": 1, \"b\": 3}"),
        [wrong],
        used,
        openapi=true,
      )
    catch {
      Failure(message) => assert_true(message.contains("our OpenAPI differs"))
      e => fail("unexpected error: " + e.to_string())
    } noraise {
      _ => fail("a difference passed with a wrong allow entry")
    }
    assert_eq(used, [false])
  }
  // a blocked output and a failed conversion agree
  compare_openapi(start, None, Json::null(), [], [], openapi=true)
}

///|
test "our OpenAPI document is the .openapi.json file of the transform" {
  let model = "$version: \"2\"\nnamespace example.web\nuse aws.protocols#restJson1\n@restJson1\nservice Weather { version: \"1\", operations: [GetCity] }\n@readonly\n@http(method: \"GET\", uri: \"/city\")\noperation GetCity { output: CityOutput }\nstructure CityOutput { name: String }\n"
  let lesson : @model.Lesson = {
    dir: "99-x",
    number: 99,
    slug: "x",
    title: "x",
    section: "x",
    engine: Model,
    extension: false,
    output: Some(OpenApi30),
    selector: None,
    spec: "",
    text: "",
    files: [],
    cases: [],
  }
  let document = our_openapi(
    @core.Session::new(),
    "a",
    lesson,
    [("model.smithy", model)],
    None,
  )
  guard document
    is Some({ "openapi": String("3.0.2"), "paths": Object(paths), .. }) else {
    fail("the OpenAPI document is missing or has no version 3.0.2 and paths")
  }
  assert_true(paths.contains("/city"))
}

///|
test "a Selector lesson needs a reference selection unless the case has an error" {
  let list = Some(Json::array([Json::string("a#B")]))
  let entry = fn(events : Array[String], selector : Json?) -> ReferenceCase {
    {
      digest: "d",
      events: events.map(e => @model.EventKey::parse(e).unwrap()),
      json_schema: None,
      openapi: None,
      selector,
      json_ast: None,
    }
  }
  check_fresh("a", entry([], list), "d", Some(Selector))
  check_fresh("a", entry([], Some(Json::null())), "d", Some(Selector))
  check_fresh("a", entry(["E|ERROR|-"], None), "d", Some(Selector))
  let stale_message = "a: the reference result is missing or stale; run `mise run reference:tour`"
  for
    bad in [
      (entry([], None), "d", Some(@core.Output::Selector)),
      (entry([], list), "d", Some(@core.Output::JsonAst)),
      (
        entry(["E|DANGER|-"], Some(Json::array([]))),
        "d",
        Some(@core.Output::Selector),
      ),
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
test "a failed reference selector agrees only with a blocked output" {
  let list = Json::array([Json::string("a#B")])
  assert_true(selection_pair("a", None, Json::null()) is None)
  assert_eq(selection_pair("a", Some(["a#B"]), list), Some((["a#B"], ["a#B"])))
  try selection_pair("a", Some([]), Json::null()) catch {
    Failure(message) =>
      assert_true(
        message.has_suffix(
          "a: the reference selector failed, but ours gave a result",
        ),
      )
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a result against a failed selector passed")
  }
  try selection_pair("a", None, list) catch {
    Failure(message) =>
      assert_true(
        message.has_suffix(
          "a: our selector failed, but the reference gave a result",
        ),
      )
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a blocked output against a result passed")
  }
}

///|
test "an allowed shape is removed once, from the side that the entry names" {
  let start : @model.CaseId = { dir: "01-a", name: "start", }
  let allowed = (side : Side) => {
    case_id: start,
    difference: Selected(shape="smithy.rpc#X", side~),
    reason: "r",
    issue: "smithy-1",
  }
  let reference = Json::array([Json::string("a#A")])
  let used = [false]
  compare_selector(
    start,
    Some(["a#A", "smithy.rpc#X"]),
    reference,
    [allowed(Ours)],
    used,
    selector=true,
  )
  assert_eq(used, [true])
  // the same entry on the other side removes nothing: stale, and the difference fails
  let used = [false]
  try
    compare_selector(
      start,
      Some(["a#A", "smithy.rpc#X"]),
      reference,
      [allowed(Reference)],
      used,
      selector=true,
    )
  catch {
    Failure(message) =>
      assert_true(message.contains("our selected shapes differ"))
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a difference passed with a wrong side")
  }
  assert_eq(used, [false])
  // the order of the lines does not matter: both sides sort by code unit
  compare_selector(
    start,
    Some(["a#B", "a#A"]),
    Json::array([Json::string("a#A"), Json::string("a#B")]),
    [],
    [],
    selector=true,
  )
}

///|
test "a selector allow entry names a shape and a side" {
  let text = "[{\"case\": \"01-a/start\", \"kind\": \"selector\", \"shape\": \"smithy.rpc#X\", \"side\": \"ours\", \"reason\": \"r\", \"issue\": \"smithy-1\"}]"
  let allow = parse_allow(text)
  assert_eq(allow.length(), 1)
  assert_true(allow[0].difference is Selected(shape="smithy.rpc#X", side=Ours))
}

///|
test "our selector results agree with the reference" {
  let (tour, reference, allow) = inputs()
  ignore(
    compare_all(
      tour,
      reference,
      allow,
      events=false,
      json_schema=false,
      openapi=false,
      selector=true,
      json_ast=false,
    ),
  )
}

///|
test "a JsonAst lesson needs a reference document unless the case has an error" {
  let doc = Some(Json::object({}))
  let entry = fn(events : Array[String], json_ast : Json?) -> ReferenceCase {
    {
      digest: "d",
      events: events.map(e => @model.EventKey::parse(e).unwrap()),
      json_schema: None,
      openapi: None,
      selector: None,
      json_ast,
    }
  }
  check_fresh("a", entry([], doc), "d", Some(JsonAst))
  check_fresh("a", entry(["W|WARNING|-"], doc), "d", Some(JsonAst))
  check_fresh("a", entry(["E|ERROR|-"], None), "d", Some(JsonAst))
  let stale_message = "a: the reference result is missing or stale; run `mise run reference:tour`"
  for
    bad in [
      (entry([], None), "d", Some(@core.Output::JsonAst)),
      (entry([], doc), "d", Some(@core.Output::JsonSchema)),
      (entry([], doc), "d", None),
      (entry(["E|DANGER|-"], doc), "d", Some(@core.Output::JsonAst)),
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
test "a json_ast allow entry must not name a side" {
  let text = "[{\"case\": \"01-a/start\", \"kind\": \"json_ast\", \"pointer\": \"/a\", \"side\": \"ours\", \"reason\": \"r\", \"issue\": \"smithy-1\"}]"
  try parse_allow(text) catch {
    Failure(message) =>
      assert_true(message.contains("\"side\" is for kind \"event\" only"))
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a json_ast entry with a side was accepted")
  }
  let ok = "[{\"case\": \"01-a/start\", \"kind\": \"json_ast\", \"pointer\": \"/a\", \"reason\": \"r\", \"issue\": \"smithy-1\"}]"
  assert_true(parse_allow(ok)[0].difference is JsonAst(pointer="/a"))
}

///|
test "the JSON AST comparison fails on a difference and honors the allow list" {
  let json = (text : String) => parse_json("test", text)
  let start : @model.CaseId = { dir: "01-a", name: "start", }
  let other : @model.CaseId = { dir: "01-a", name: "other", }
  let allowed = (case_id : @model.CaseId, pointer : String) => {
    case_id,
    difference: JsonAst(pointer~),
    reason: "r",
    issue: "smithy-1",
  }
  compare_json_ast(
    start,
    json("{\"a\": 1}"),
    json("{\"a\": 1}"),
    [],
    [],
    json_ast=true,
  )
  try
    compare_json_ast(
      start,
      json("{\"a\": 1, \"b\": 2}"),
      json("{\"a\": 1, \"b\": 3}"),
      [],
      [],
      json_ast=true,
    )
  catch {
    Failure(message) =>
      assert_true(
        message.contains(
          "01-a/start: our JSON AST differs from the reference at [/b",
        ),
      )
    e => fail("unexpected error: " + e.to_string())
  } noraise {
    _ => fail("a different document passed")
  }
  let used = [false]
  compare_json_ast(
    start,
    json("{\"a\": 1, \"b\": 2}"),
    json("{\"a\": 1, \"b\": 3}"),
    [allowed(start, "/b")],
    used,
    json_ast=true,
  )
  assert_eq(used, [true])
  for wrong in [allowed(other, "/b"), allowed(start, "/c")] {
    let used = [false]
    try
      compare_json_ast(
        start,
        json("{\"a\": 2}"),
        json("{\"a\": 3}"),
        [wrong],
        used,
        json_ast=true,
      )
    catch {
      Failure(message) => assert_true(message.contains("our JSON AST differs"))
      e => fail("unexpected error: " + e.to_string())
    } noraise {
      _ => fail("a difference passed with a wrong allow entry")
    }
    assert_eq(used, [false])
  }
}

///|
test "our JSON AST is the model.json file of the transform" {
  let lesson : @model.Lesson = {
    dir: "99-x",
    number: 99,
    slug: "x",
    title: "x",
    section: "x",
    engine: Model,
    extension: false,
    output: Some(JsonAst),
    selector: None,
    spec: "",
    text: "",
    files: [],
    cases: [],
  }
  let document = our_json_ast(
    @core.Session::new(),
    "a",
    lesson,
    [("model.smithy", "$version: \"2\"\nnamespace example\nstring Name\n")],
    None,
  )
  guard document is { "smithy": String("2.0"), "shapes": Object(shapes), .. } else {
    fail("the JSON AST is missing the version 2.0 and shapes")
  }
  assert_true(shapes.contains("example#Name"))
}

///|
test "our JSON AST agrees with the reference JSON AST" {
  let (tour, reference, allow) = inputs()
  ignore(
    compare_all(
      tour,
      reference,
      allow,
      events=false,
      json_schema=false,
      openapi=false,
      selector=false,
      json_ast=true,
    ),
  )
}

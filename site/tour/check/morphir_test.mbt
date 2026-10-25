///|
/// The vendored Morphir sources, at their paths in finos/morphir.
let morphir_root : String = "tour/morphir/upstream"

///|
fn morphir_path(path : String) -> String {
  morphir_root + "/" + path
}

///|
fn morphir_text(path : String) -> String raise {
  @fs.read_file_to_string(morphir_path(path)) catch {
    IOError(reason) =>
      fail(path + ": I cannot read the vendored file: " + reason)
  }
}

///|
fn morphir_json(path : String) -> Json raise {
  @json.parse(morphir_text(path)) catch {
    _ => fail(path + ": the vendored file is not valid JSON")
  }
}

///|
/// The Git blob identity of `content`: SHA-1 of "blob <length>\0" and then the
/// bytes, as `scripts/vendor-morphir.mbtx` computes it.
fn git_blob(content : Bytes) -> String {
  let header = @utf8.encode("blob " + content.length().to_string() + "\u{0000}")
  let object_ = Bytes::from_array(header.to_array() + content.to_array())
  @crypto.bytes_to_hex_string(@crypto.sha1(object_))
}

///|
/// The files under `dir`, as paths relative to `morphir_root`, sorted.
fn vendored_files(dir : String) -> Array[String] raise {
  let found : Array[String] = []
  let todo = [dir]
  while todo.pop() is Some(rel) {
    let full = if rel == "" { morphir_root } else { morphir_path(rel) }
    let names = @fs.read_dir(full) catch {
      IOError(reason) => fail(full + ": I cannot list the folder: " + reason)
    }
    for name in names {
      let path = if rel == "" { name } else { rel + "/" + name }
      let is_dir = @fs.is_dir(morphir_path(path)) catch {
        IOError(reason) => fail(path + ": I cannot read it: " + reason)
      }
      if is_dir {
        todo.push(path)
      } else {
        found.push(path)
      }
    }
  }
  found.sort_by(@model.compare_code_units)
  found
}

///|
/// The node at the JSON pointer `pointer` of `json`.
fn at_pointer(json : Json, pointer : String) -> Json? {
  if pointer == "" {
    return Some(json)
  }
  let mut node = json
  for token in pointer.split("/").drop(1) {
    let key = token
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    match node {
      Object(members) =>
        match members.get(key) {
          Some(next) => node = next
          None => return None
        }
      Array(items) => {
        let i = @string.parse_int(key) catch { _ => return None }
        guard i >= 0 && i < items.length() else { return None }
        node = items[i]
      }
      _ => return None
    }
  }
  Some(node)
}

///|
test "the vendored Morphir files match inventory.json" {
  let inventory_path = "tour/morphir/inventory.json"
  let inventory = @json.parse(
    @fs.read_file_to_string(inventory_path) catch {
      IOError(reason) => fail(inventory_path + ": " + reason)
    },
  ) catch {
    _ => fail(inventory_path + ": it is not valid JSON")
  }
  guard inventory is Object(top) && top.get("files") is Some(Array(entries)) else {
    fail(inventory_path + ": I expected an object with \"files\"")
  }
  let listed : Array[String] = []
  for entry in entries {
    guard entry is Object(e) &&
      e.get("path") is Some(String(path)) &&
      e.get("gitBlob") is Some(String(blob)) else {
      fail(inventory_path + ": an entry has no path or gitBlob")
    }
    listed.push(path)
    let bytes = @fs.read_file_to_bytes(morphir_path(path)) catch {
      _ =>
        fail(
          path +
          ": the vendored file is missing; run `mise run tour:vendor:morphir`",
        )
    }
    if git_blob(bytes) != blob {
      fail(
        path + ": the vendored file changed; run `mise run tour:vendor:morphir`",
      )
    }
  }
  listed.sort_by(@model.compare_code_units)
  for path in vendored_files("") {
    if !listed.contains(path) {
      fail(
        path +
        ": the file is not in inventory.json; run `mise run tour:vendor:morphir`",
      )
    }
  }
}

///|
/// The text of the file `name` of a lesson, from its own files.
fn lesson_file(lesson : @model.Lesson, name : String) -> String raise {
  match lesson.files.search_by(f => f.name == name) {
    Some(i) => lesson.files[i].text
    None => fail(lesson.dir + " has no file " + name)
  }
}

///|
test "the Morphir lessons share the IR model files" {
  let ir = ["34-morphir-ir-types", "38-morphir-values", "39-morphir-limits"]
  let sdk = ["36-morphir-vocabulary", "37-morphir-sdk"]
  let first = lesson_in(ir[0])
  for dir in ir {
    let lesson = lesson_in(dir)
    for name in ["names.smithy", "type.smithy"] {
      if lesson_file(lesson, name) != lesson_file(first, name) {
        fail(dir + "/files/" + name + " differs from " + first.dir)
      }
    }
  }
  for dir in ["35-morphir-names", ..sdk] {
    if lesson_file(lesson_in(dir), "names.smithy") !=
      lesson_file(first, "names.smithy") {
      fail(dir + "/files/names.smithy differs from " + first.dir)
    }
  }
  // Lesson 37 describes the SDK with the vocabulary of lesson 36.
  for name in ["dsl.smithy", "basics.smithy"] {
    if lesson_file(lesson_in(sdk[1]), name) !=
      lesson_file(lesson_in(sdk[0]), name) {
      fail(sdk[1] + "/files/" + name + " differs from " + sdk[0])
    }
  }
}

///|
/// The JSON AST of the model files of a lesson, as the playground core gives it.
fn json_ast_of(lesson : @model.Lesson) -> Json raise {
  let files = files_of(@model.model_files(lesson.engine, lesson.files))
  match
    @core.handle(
      @core.Session::new(),
      TransformFiles(seq=1, files~, output=JsonAst, selector=None),
    ) {
    Transformed(files=[(_, text), ..], ..) =>
      @json.parse(text) catch {
        _ => fail(lesson.dir + ": the JSON AST is not valid JSON")
      }
    _ => fail(lesson.dir + ": I expected a JSON AST")
  }
}

///|
/// The `@pattern` of a shape in a JSON AST.
fn pattern_of(ast : Json, shape : String) -> String raise {
  match at_pointer(ast, "/shapes/" + shape + "/traits/smithy.api#pattern") {
    Some(String(pattern)) => pattern
    _ => fail(shape + " has no @pattern")
  }
}

///|
/// A string at a JSON pointer of the vendored schema.
fn schema_string(schema : Json, pointer : String) -> String raise {
  match at_pointer(schema, pointer) {
    Some(String(text)) => text
    _ => fail("morphir-ir-v4.json has no string at " + pointer)
  }
}

///|
test "the lesson patterns are the patterns of the Morphir schema" {
  let schema = morphir_json("website/static/schemas/morphir-ir-v4.json")
  let ir = json_ast_of(lesson_in("38-morphir-values"))
  for
    pair in [
      ("morphir.ir.v4#Name", "/definitions/NameString/pattern"),
      ("morphir.ir.v4#Path", "/definitions/PathString/pattern"),
      ("morphir.ir.v4#FQName", "/definitions/FQNameString/pattern"),
    ] {
    let (shape, pointer) = pair
    assert_eq(pattern_of(ir, shape), schema_string(schema, pointer))
  }
  let dsl = json_ast_of(lesson_in("36-morphir-vocabulary"))
  assert_eq(
    pattern_of(dsl, "morphir.dsl#typeVariable"),
    schema_string(schema, "/definitions/VariableType/oneOf/0/pattern"),
  )
}

///|
/// Every example of the vendored Morphir sources, in a fixed order.
fn morphir_examples() -> Array[@morphir.Example] raise {
  let examples = @morphir.schema_examples(
    morphir_json("website/static/schemas/morphir-ir-v4.json"),
  )
  let folder = "website/static/ir/examples/v4"
  guard morphir_json(folder + "/index.json")
    is Object({ "examples": Array(listed), .. }) else {
    fail(folder + "/index.json: I expected the list \"examples\"")
  }
  for entry in listed {
    guard entry is Object({ "file": String(file), .. }) else {
      fail(folder + "/index.json: an example has no \"file\"")
    }
    let source = folder + "/" + file
    examples.append(@morphir.file_examples(source, morphir_json(source)))
  }
  for source in ["spec/ir/mck/types.feature", "spec/ir/mck/names.feature"] {
    match @morphir.kit_examples(source, morphir_text(source)) {
      Ok(found) => examples.append(found)
      Err(e) => fail(e)
    }
  }
  let corpus = "docs/spec/ir/fixtures/naming-conformance.json"
  examples.append(@morphir.naming_examples(corpus, morphir_json(corpus)))
  examples
}

///|
test "the Morphir examples" (t : @test.Test) {
  for example in morphir_examples() {
    t.write(example.line() + "\n")
  }
  t.snapshot(filename="morphir-examples.txt")
}

///|
fn show_triples(items : Array[(String, String, String)]) -> String {
  show(items.map(i => "\{i.0} \{i.1} \"\{i.2}\""))
}

///|
test "every Morphir example gives the findings of its verdict and form" {
  let lesson = lesson_in("38-morphir-values")
  guard lesson.engine is Value(setup) else {
    fail(lesson.dir + " is not a value lesson")
  }
  let files = files_of(lesson.files.filter(f => f.name != setup.file))
  let session = @core.Session::new()
  let failures : Array[String] = []
  for example in morphir_examples() {
    let found = match
      @core.handle(
        session,
        CheckValue(
          seq=1,
          files~,
          shape=example.kind.shape(),
          value=example.value.stringify(),
          options=@samples.ValueOptions::default(),
        ),
      ) {
      DataChecked(findings~, ..) =>
        findings.map(f => {
          match f {
            Found(code~, path~, message~, ..) => (code, path, message)
            Stopped(code~, message~, ..) => ("Stopped:" + code, "-", message)
          }
        })
      Blocked(reason~, ..) => fail("the value check was blocked: " + reason)
      _ => fail("the value check gave an unexpected answer")
    }
    let compare = fn(
      a : (String, String, String),
      b : (String, String, String),
    ) {
      let c = @model.compare_code_units(a.1, b.1)
      if c != 0 {
        c
      } else {
        let d = @model.compare_code_units(a.0, b.0)
        if d != 0 {
          d
        } else {
          @model.compare_code_units(a.2, b.2)
        }
      }
    }
    found.sort_by(compare)
    let stopped = found.any(f => f.0.has_prefix("Stopped:"))
    let form = @morphir.sort(example.kind, example.value)
    let problem = match example.verdict {
      _ if stopped => Some("the check stopped")
      Accepted =>
        match form {
          Expanded =>
            if found.is_empty() {
              None
            } else {
              Some("expected no findings")
            }
          Other(expected) => {
            let wanted = expected.map(e => (e.code, e.pointer, e.message))
            wanted.sort_by(compare)
            if found == wanted {
              None
            } else {
              Some("expected " + show_triples(wanted))
            }
          }
          Unknown(pointer) =>
            Some("the sort does not know the spelling at " + pointer)
        }
      Legacy(_) =>
        if !found.is_empty() &&
          found.all(f => {
            ["UnknownMember", "RequiredMember", "TypeMismatch"].contains(f.0)
          }) {
          None
        } else {
          Some(
            "expected findings with the codes UnknownMember, RequiredMember or TypeMismatch",
          )
        }
      Rejected(diagnostic) =>
        match @morphir.rejected_code(diagnostic) {
          Some(code) =>
            if found.any(f => f.0 == code) {
              None
            } else {
              Some("expected a finding with the code " + code)
            }
          None => Some("the tour does not know the diagnostic " + diagnostic)
        }
    }
    if problem is Some(text) {
      failures.push(
        example.line() + ": " + text + "; found " + show_triples(found),
      )
    }
  }
  if !failures.is_empty() {
    fail(
      failures.length().to_string() +
      " Morphir examples fail:\n" +
      failures.join("\n"),
    )
  }
}

///|
test "lesson 39 shows the message of every other spelling" {
  let shown : Array[String] = []
  for case in lesson_in("39-morphir-limits").cases {
    shown.append(case.expect.output_contains)
  }
  let missing : Array[String] = []
  for example in morphir_examples() {
    guard example.verdict is Accepted &&
      @morphir.sort(example.kind, example.value) is Other(expected) else {
      continue
    }
    for e in expected {
      if !shown.any(s => s.contains(e.message)) && !missing.contains(e.message) {
        missing.push(e.message)
      }
    }
  }
  assert_eq(missing, [])
}

///|
test "quoted Morphir values are the upstream values" {
  for quote in @morphir.quotes {
    let lesson = lesson_in(quote.lesson)
    let text = case_file(lesson, quote.case_, quote.file)
    let value = @json.parse(text) catch {
      _ =>
        fail(quote.lesson + "/" + quote.case_ + "/" + quote.file + ": not JSON")
    }
    match at_pointer(morphir_json(quote.source), quote.at) {
      Some(upstream) =>
        if value != upstream {
          fail(
            quote.lesson +
            "/" +
            quote.case_ +
            "/" +
            quote.file +
            " is not the value at " +
            quote.source +
            "#" +
            quote.at,
          )
        }
      None => fail(quote.source + " has no node at " + quote.at)
    }
  }
}

///|
/// The commit of the vendored Morphir sources, from inventory.json.
fn morphir_commit() -> String raise {
  let path = "tour/morphir/inventory.json"
  let text = @fs.read_file_to_string(path) catch {
    IOError(reason) => fail(path + ": " + reason)
  }
  let json = @json.parse(text) catch {
    _ => fail(path + ": it is not valid JSON")
  }
  match json {
    Object({ "commit": String(commit), .. }) => commit
    _ => fail(path + ": I expected the string \"commit\"")
  }
}

///|
/// The commits in the finos/morphir links of a text, in order.
fn morphir_link_commits(text : String) -> Array[String] {
  let prefix = "https://github.com/finos/morphir/blob/"
  let found : Array[String] = []
  for part in text.split(prefix).drop(1) {
    let rest = part.to_owned()
    let end = rest.find("/").unwrap_or(rest.length())
    found.push(rest[:end].to_owned())
  }
  found
}

///|
test "morphir_link_commits finds the commit of each finos/morphir link" {
  let text = "[a](https://github.com/finos/morphir/blob/abc/x.md#L1) and " +
    "[b](https://github.com/finos/morphir-elm/blob/def/y.elm) and " +
    "[c](https://github.com/finos/morphir/blob/ghi/z.json)"
  assert_eq(morphir_link_commits(text), ["abc", "ghi"])
}

///|
/// A lesson cites the Morphir lines of the vendored commit. After a refresh,
/// each link must name the new commit, and its lines must be checked again.
test "every lesson link to finos/morphir uses the vendored commit" {
  let commit = morphir_commit()
  let tour = match @source.read_tour(lessons_root, repo="..") {
    Ok(tour) => tour
    Err(e) => fail("I cannot read the tour: " + e)
  }
  let mut links = 0
  for lesson in tour.lessons {
    for found in morphir_link_commits(lesson.text) {
      links += 1
      if found != commit {
        fail(
          lesson.dir +
          ": a finos/morphir link uses the commit " +
          found +
          ", but inventory.json has " +
          commit +
          ". Change the link and check the cited lines",
        )
      }
    }
  }
  assert_true(links > 0)
}

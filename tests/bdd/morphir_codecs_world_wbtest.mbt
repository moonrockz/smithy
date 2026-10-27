// Morphir v3/v4 codec conformance: the models of examples/morphir-codecs/model, the Morphir adapters and the
// pinned cases of examples/morphir-codecs/cases.json, run through PreparedCodec.

///|
let morphir_dir : String = "../examples/morphir-codecs/"

///|
let morphir_model_files : Array[String] = [
  "morphir-v3.smithy", "morphir-v4.smithy", "morphir-bundle.smithy",
]

///|
/// Load the Morphir models with the serialization traits. Any error or danger event fails.
fn morphir_model() -> @smithy.Model raise {
  let mut loader = @codec_contract.loader()
  for file in morphir_model_files {
    loader = loader.add_idl(
      "model/" + file,
      @xfs.read_file_to_string(morphir_dir + "model/" + file),
    )
  }
  let loaded = loader.assemble()
  let errors = loaded.diagnostics.filter(d => d.severity == Error)
  if !errors.is_empty() {
    fail(errors.map(d => d.message).join("\n"))
  }
  for event in loaded.validation_events() {
    if event.severity == "ERROR" || event.severity == "DANGER" {
      fail(event.id + ": " + event.message)
    }
  }
  loaded.model.unwrap()
}

///|
/// Remove the whitespace outside JSON strings. Number tokens and member order are kept.
fn minify_json(text : String) -> String {
  let out = StringBuilder()
  let mut in_string = false
  let mut escaped = false
  for c in text {
    if in_string {
      out.write_char(c)
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
    } else if c == '"' {
      in_string = true
      out.write_char(c)
    } else if !(c is (' ' | '\n' | '\r' | '\t')) {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// The prepared codecs and file texts of one conformance run.
struct MorphirSuite {
  model : @smithy.Model
  adapters : @codec.AdapterRegistry
  codecs : Map[String, @codec.PreparedCodec]
  texts : Map[String, String]
  cases : Map[String, Json]
  order : Array[String]
}

///|
fn MorphirSuite::load() -> MorphirSuite raise {
  let parsed = @json.parse(@xfs.read_file_to_string(morphir_dir + "cases.json"))
  guard parsed is { "cases": Array(items), .. } else {
    fail("cases.json has no cases")
  }
  let cases : Map[String, Json] = Map([])
  let order : Array[String] = []
  for item in items {
    guard item is { "id": String(id), .. } else { fail("a case has no id") }
    cases[id] = item
    order.push(id)
  }
  {
    model: morphir_model(),
    adapters: @morphir.registry(),
    codecs: Map([]),
    texts: Map([]),
    cases,
    order,
  }
}

///|
fn MorphirSuite::codec(
  self : MorphirSuite,
  root : String,
  profile : String,
) -> @codec.PreparedCodec raise {
  let key = root + " " + profile
  match self.codecs.get(key) {
    Some(codec) => codec
    None => {
      let codec = @codec.PreparedCodec::prepare(
        self.model,
        @smithy.ShapeId::parse(root).unwrap(),
        profile=Some(@codec_contract.ProfileId::parse(profile)),
        adapters=self.adapters,
      )
      self.codecs[key] = codec
      codec
    }
  }
}

///|
fn MorphirSuite::file(self : MorphirSuite, path : String) -> String raise {
  match self.texts.get(path) {
    Some(text) => text
    None => {
      let text = @xfs.read_file_to_string(morphir_dir + path)
      self.texts[path] = text
      text
    }
  }
}

///|
fn json_at(value : Json, pointer : String) -> Json? {
  if pointer.is_empty() {
    return Some(value)
  }
  let mut current = value
  for token in pointer[1:].split("/") {
    let key = token.to_owned()
    match current {
      Object(fields) =>
        match fields.get(key) {
          Some(v) => current = v
          None => return None
        }
      Array(items) => {
        guard !key.is_empty() && key.iter().all(c => c >= '0' && c <= '9') else {
          return None
        }
        let mut index = 0
        for c in key {
          index = index * 10 + (c.to_int() - '0'.to_int())
        }
        guard index < items.length() else { return None }
        current = items[index]
      }
      _ => return None
    }
  }
  Some(current)
}

///|
/// The input JSON text of a case, or None for a case outside the JSON profile (a YAML file).
fn MorphirSuite::input(self : MorphirSuite, case_ : Json) -> String? raise {
  guard case_ is { "file": String(file), .. } else {
    fail("a case has no file")
  }
  let content = self.file(file)
  match case_ {
    { "line": Number(line, ..), "fence": String(fence), .. } => {
      let lines = content.split("\n").map(l => l.to_owned()).to_array()
      let body : Array[String] = []
      let mut i = line.to_int()
      while i < lines.length() && lines[i] != "```" {
        body.push(lines[i])
        i += 1
      }
      if fence.has_prefix("```text") {
        let path = body[0].trim().to_owned()
        if path.has_suffix(".yaml") {
          return None
        }
        return Some(self.file("upstream/finos-morphir/" + path))
      }
      Some(body.join("\n"))
    }
    { "pointer": String(pointer), .. } => {
      let document = @validation.parse_json_value(content)
      let inner = match case_ {
        { "input": String(input), .. } => input
        _ => ""
      }
      guard json_at(document, pointer + inner) is Some(value) else {
        fail("\{pointer}\{inner} does not resolve")
      }
      match (inner, value) {
        ("/source", String(source)) => Some(source)
        _ => Some(value.stringify())
      }
    }
    _ => Some(content)
  }
}

///|
/// The expected canonical output of a valid case, if the case defines one.
fn MorphirSuite::output(self : MorphirSuite, case_ : Json) -> String? raise {
  match case_ {
    { "output": { "self": True, .. }, .. } => self.input(case_).map(minify_json)
    { "output": { "case": String(id), .. }, .. } =>
      match self.cases.get(id) {
        Some(other) => self.input(other).map(minify_json)
        None => fail("unknown output case \{id}")
      }
    { "output": { "file": True, .. }, "file": String(file), .. } => {
      let text = self.file(file)
      Some(
        if text.has_suffix("\n") {
          text[:text.length() - 1].to_owned()
        } else {
          text
        },
      )
    }
    { "output": { "json": String(text), .. }, .. } => Some(minify_json(text))
    _ => None
  }
}

///|
fn findings_text(result : @codec.CodecResult) -> String {
  let parts = result.findings.map(f => {
    f.code.to_string() + " at " + f.path.pointer() + ": " + f.message
  })
  if !result.complete {
    parts.push("incomplete")
  }
  parts.join("; ")
}

///|
fn abbreviate(text : String) -> String {
  if text.length() > 300 {
    text[:300].to_owned() + "..."
  } else {
    text
  }
}

///|
/// Run one case. Ok(None) is a pass, Ok(Some(reason)) a skip, and Err(reason) a failure.
fn MorphirSuite::run(
  self : MorphirSuite,
  id : String,
) -> Result[String?, String] raise {
  guard self.cases.get(id) is Some(case_) else { fail("unknown case \{id}") }
  guard self.input(case_) is Some(text) else {
    return Ok(Some("outside the JSON profile"))
  }
  guard case_
    is {
      "root": String(root),
      "profile": String(profile),
      "expected": String(expected),
      ..
    } else {
    fail("case \{id} has no root, profile or expected outcome")
  }
  let codec = self.codec(root, profile) catch {
    error => return Err("preparation: \{error}")
  }
  match expected {
    "invalid" => {
      let result = codec.check(text)
      if result.is_valid() {
        Err("accepted an invalid input")
      } else {
        Ok(None)
      }
    }
    "other-node" => {
      guard case_ is { "expectNode": String(node), .. } else {
        fail("case \{id} has no expectNode")
      }
      let value = codec.decode(text) catch {
        @codec.CodecFailure(result) => return Err(findings_text(result))
      }
      match value.logical() {
        Union(name, _) if name == node => Ok(None)
        Union(name, _) => Err("decoded as \{name}, not \{node}")
        _ => Err("decoded as no union member")
      }
    }
    _ => {
      let out = codec.canonicalize(text) catch {
        @codec.CodecFailure(result) => return Err(findings_text(result))
      }
      if self.output(case_) is Some(want) && want != out {
        return Err(
          "canonical output differs:\n  want " +
          abbreviate(want) +
          "\n  got  " +
          abbreviate(out),
        )
      }
      let again = codec.canonicalize(out) catch {
        @codec.CodecFailure(result) =>
          return Err(
            "canonical output does not decode: " + findings_text(result),
          )
      }
      if again != out {
        return Err("canonicalization is not idempotent")
      }
      Ok(None)
    }
  }
}

///|
/// Run a case and compare the result with its recorded gap: a case with a "gap" must still fail, so the gap
/// list in COVERAGE.md cannot go stale.
fn MorphirSuite::verdict(self : MorphirSuite, id : String) -> String raise {
  let gap = match self.cases.get(id) {
    Some({ "gap": String(gap), .. }) => Some(gap)
    _ => None
  }
  match (self.run(id), gap) {
    (Ok(None), None) => "pass"
    (Ok(Some(reason)), _) => "skip: " + reason
    (Err(_), Some(gap)) => "gap " + gap
    (Ok(None), Some(gap)) => "UNEXPECTED PASS (gap \{gap})"
    (Err(reason), None) => "FAIL: " + reason
  }
}

///|
test "every Morphir conformance case has its recorded outcome" {
  let suite = MorphirSuite::load()
  let counts : Map[String, Int32] = Map([])
  let problems : Array[String] = []
  for id in suite.order {
    let verdict = suite.verdict(id)
    let kind = if verdict.has_prefix("gap") {
      "gap"
    } else if verdict.has_prefix("skip") {
      "skip"
    } else {
      verdict
    }
    if verdict.has_prefix("FAIL") || verdict.has_prefix("UNEXPECTED") {
      problems.push(id + ": " + verdict)
      counts["problem"] = counts.get("problem").unwrap_or(0) + 1
    } else {
      counts[kind] = counts.get(kind).unwrap_or(0) + 1
    }
  }
  println(
    "Morphir conformance: \{suite.order.length()} cases, \{counts.get("pass").unwrap_or(0)} pass, \{counts.get("gap").unwrap_or(0)} recorded gaps, \{counts.get("skip").unwrap_or(0)} skipped, \{problems.length()} problems",
  )
  for problem in problems {
    println(problem)
  }
  assert_eq(problems, [])
}

///|
struct MorphirCodecsWorld {
  mut suite : MorphirSuite?
  mut root : String
  mut profile : String
  mut output : String?
  mut result : @codec.CodecResult?
  mut problem : String?
  mut bundle : @codec.PreparedBundle?
}

///|
fn MorphirCodecsWorld::new() -> MorphirCodecsWorld {
  {
    suite: None,
    root: "",
    profile: "",
    output: None,
    result: None,
    problem: None,
    bundle: None,
  }
}

///|
fn MorphirCodecsWorld::current(self : MorphirCodecsWorld) -> MorphirSuite raise {
  match self.suite {
    Some(suite) => suite
    None => {
      let suite = MorphirSuite::load()
      self.suite = Some(suite)
      suite
    }
  }
}

///|
fn MorphirCodecsWorld::canonicalize(
  self : MorphirCodecsWorld,
  text : String,
) -> Unit raise {
  self.output = None
  self.result = None
  let codec = self.current().codec(self.root, self.profile)
  try codec.canonicalize(text) catch {
    @codec.CodecFailure(result) => self.result = Some(result)
  } noraise {
    out => self.output = Some(out)
  }
}

///|
fn MorphirCodecsWorld::through_bundle(
  self : MorphirCodecsWorld,
  text : String,
  output : String?,
) -> Unit raise {
  self.output = None
  self.result = None
  guard self.bundle is Some(bundle) else { fail("no bundle") }
  let output = output.map(p => @codec_contract.ProfileId::parse(p))
  try bundle.canonicalize(text, output~) catch {
    @codec.CodecFailure(result) => self.result = Some(result)
  } noraise {
    out => self.output = Some(out)
  }
}

///|
impl @moonspec.World for MorphirCodecsWorld with fn configure(self, setup) {
  setup.given0("the Morphir codec models and adapters", fn() raise {
    ignore(self.current())
  })
  setup.given2("the root {string} with profile {string}", fn(
    root : String,
    profile : String,
  ) raise {
    self.root = root
    self.profile = profile
    ignore(self.current().codec(root, profile))
  })
  setup.given0("the Morphir document bundle", fn() raise {
    let suite = self.current()
    self.bundle = Some(
      @codec.PreparedBundle::prepare(
        suite.model,
        @codec_contract.BundleId::parse("morphir"),
        adapters=suite.adapters,
      ),
    )
  })
  setup.when1("I canonicalize the document {string} with the bundle", fn(
    text : String,
  ) raise {
    self.through_bundle(text, None)
  })
  setup.when2(
    "I canonicalize the document {string} with the bundle and output profile {string}",
    fn(text : String, profile : String) raise {
      self.through_bundle(text, Some(profile))
    },
  )
  setup.when1("I canonicalize the file {string} with the bundle", fn(
    path : String,
  ) raise {
    self.through_bundle(self.current().file(path), None)
  })
  setup.when1("I decode the document {string} with the bundle", fn(
    text : String,
  ) raise {
    self.output = None
    self.result = None
    guard self.bundle is Some(bundle) else { fail("no bundle") }
    try bundle.decode(text) catch {
      @codec.CodecFailure(result) => self.result = Some(result)
    } noraise {
      value => self.output = Some(value.release().to_string())
    }
  })
  setup.then1("the decoded release is {string}", fn(release : String) raise {
    assert_eq(self.output, Some(release))
  })
  setup.when1("I run the conformance case {string}", fn(id : String) raise {
    self.problem = Some(self.current().verdict(id))
  })
  setup.then0("the case has its expected outcome", fn() raise {
    guard self.problem is Some(verdict) else { fail("no case ran") }
    assert_true(
      verdict == "pass" || verdict.has_prefix("gap"),
      msg="verdict: " + verdict,
    )
  })
  setup.when1("I canonicalize the file {string}", fn(path : String) raise {
    self.canonicalize(self.current().file(path))
  })
  setup.when1("I canonicalize {string}", fn(text : String) raise {
    self.canonicalize(text)
  })
  setup.when1("I check {string}", fn(text : String) raise {
    self.output = None
    self.result = Some(
      self.current().codec(self.root, self.profile).check(text),
    )
  })
  setup.then1("the output is the file {string}", fn(path : String) raise {
    let text = self.current().file(path)
    let want = if text.has_suffix("\n") {
      text[:text.length() - 1].to_owned()
    } else {
      text
    }
    assert_eq(self.output, Some(want))
  })
  setup.then1("the output is {string}", fn(text : String) raise {
    assert_eq(self.output, Some(text))
  })
  setup.then1("the output is the canonical JSON of case {string}", fn(
    id : String,
  ) raise {
    let suite = self.current()
    guard suite.cases.get(id) is Some(case_) else { fail("unknown case " + id) }
    assert_eq(self.output, suite.input(case_).map(minify_json))
  })
  setup.then1("the output starts with {string}", fn(prefix : String) raise {
    guard self.output is Some(output) else {
      fail("no output: " + self.result.map(findings_text).unwrap_or(""))
    }
    assert_true(output.has_prefix(prefix), msg=abbreviate(output))
  })
  setup.then0("canonicalizing the output again gives the same text", fn() raise {
    guard self.output is Some(output) else { fail("no output") }
    let codec = self.current().codec(self.root, self.profile)
    assert_eq(codec.canonicalize(output), output)
  })
  setup.then1("the input is refused with {string}", fn(code : String) raise {
    let result = match self.result {
      Some(result) => result
      None => fail("the input was accepted: " + self.output.unwrap_or(""))
    }
    assert_false(result.is_valid())
    assert_true(
      result.findings.iter().any(f => f.code.to_string() == code),
      msg=findings_text(result),
    )
  })
  setup.then0("the input is refused", fn() raise {
    match self.result {
      Some(result) => assert_false(result.is_valid())
      None => fail("the input was accepted: " + self.output.unwrap_or(""))
    }
  })
  setup.then0("the input is valid", fn() raise {
    match self.result {
      Some(result) => assert_true(result.is_valid(), msg=findings_text(result))
      None => assert_true(self.output is Some(_))
    }
  })
}

///|
async test "Morphir codec conformance feature" {
  @moonspec.run_or_fail(
    MorphirCodecsWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/morphir-codecs.feature"),
    ]),
  )
  |> ignore
}

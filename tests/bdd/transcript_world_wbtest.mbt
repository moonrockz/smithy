///|
struct TranscriptWorld {
  mut model : @smithy.Model?
  mut protocol : @smithy.ShapeId?
  mut text : String
  mut findings : Array[@rpc.TranscriptFinding]
  mut summary : @rpc.TranscriptSummary?
  mut expectations : @rpc.ExpectationResult?
}

///|
fn TranscriptWorld::new() -> TranscriptWorld {
  {
    model: None,
    protocol: None,
    text: "",
    findings: [],
    summary: None,
    expectations: None,
  }
}

///|
/// Reads the transcript, checks it with the selected protocol and matches its
/// expect list, as `smithy validate rpc transcript` does.
fn TranscriptWorld::check(
  self : TranscriptWorld,
  text : String,
  completeness~ : @rpc.Completeness? = None,
) -> Unit raise {
  let (document, read) = @rpc.read_json_transcript(text)
  let protocol = @rpc.ProtocolDescription::from_smithy(
    self.model.unwrap(),
    self.protocol.unwrap(),
    document.version.unwrap(),
  )
  let completeness = match completeness {
    Some(chosen) => chosen
    None => document.completeness.unwrap_or(Partial)
  }
  let checker = @rpc.TranscriptChecker::new(protocol, completeness~)
  let findings = read + checker.feed_all(document.entries)
  let summary = checker.finish()
  findings.append(summary.findings)
  self.text = text
  self.findings = findings
  self.summary = Some(summary)
  self.expectations = document.expect.map(expect => {
    @rpc.match_expected(expect, findings)
  })
}

///|
fn TranscriptWorld::has(
  self : TranscriptWorld,
  severity : @validation.FindingSeverity,
  code : String,
  entry : Int32,
) -> Bool {
  self.findings.any(f => {
    f.severity == severity &&
    f.code.to_string() == code &&
    f.entry == Some(entry)
  })
}

///|
impl @moonspec.World for TranscriptWorld with fn configure(self, setup) {
  setup.given2("the {string} protocol in {string}", fn(
    protocol : String,
    file : String,
  ) raise {
    let source = @xfs.read_file_to_string("../examples/json-rpc/" + file)
    let loaded = @rpc.loader().add_idl(file, source).assemble()
    self.model = loaded.model
    self.protocol = @smithy.ShapeId::parse(protocol)
  })
  setup.when1("I check the transcript file {string}", fn(file : String) raise {
    self.check(
      @xfs.read_file_to_string("../examples/json-rpc/transcripts/" + file),
    )
  })
  setup.when1("I check the transcript:", fn(doc : @moonspec.DocString) raise {
    self.check(doc.content)
  })
  setup.when0("I check the same transcript as complete", fn() raise {
    self.check(self.text, completeness=Some(Complete))
  })
  setup.then0("the transcript is valid", fn() raise {
    assert_true(self.summary.unwrap().complete)
    assert_false(
      self.findings.any(f => f.severity == @validation.Error),
      msg=self.findings.map(f => f.message).join("\n"),
    )
  })
  setup.then0("the transcript is invalid", fn() raise {
    assert_true(self.findings.any(f => f.severity == @validation.Error))
  })
  setup.then0("the transcript has no findings", fn() raise {
    assert_eq(self.findings.map(f => f.message), [])
  })
  setup.then2("the transcript has the error {string} at entry {int}", fn(
    code : String,
    entry : Int32,
  ) raise {
    assert_true(
      self.has(@validation.Error, code, entry),
      msg=self.findings.map(f => f.message).join("\n"),
    )
  })
  setup.then2("the transcript has the advisory {string} at entry {int}", fn(
    code : String,
    entry : Int32,
  ) raise {
    assert_true(
      self.has(@validation.Advisory, code, entry),
      msg=self.findings.map(f => f.message).join("\n"),
    )
  })
  setup.then1("the transcript has no finding at entry {int}", fn(
    entry : Int32,
  ) raise {
    assert_false(self.findings.any(f => f.entry == Some(entry)))
  })
  setup.then1("{int} call is outstanding", fn(count : Int32) raise {
    assert_eq(self.summary.unwrap().outstanding, count)
  })
  setup.then0("the transcript matches its expected findings", fn() raise {
    let result = self.expectations.unwrap()
    assert_true(
      result.is_match(),
      msg="missing: \{result.missing.map(e => e.code()).join(", ")}; unexpected: \{result.unexpected.map(f => f.message).join("; ")}",
    )
  })
}

///|
async test "JSON-RPC transcript acceptance" {
  @moonspec.run_or_fail(
    TranscriptWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/json-rpc-transcripts.feature"),
    ]),
  )
  |> ignore
}

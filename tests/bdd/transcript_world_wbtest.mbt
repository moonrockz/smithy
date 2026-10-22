///|
struct TranscriptWorld {
  mut model : @smithy.Model?
  mut protocol : @smithy.ShapeId?
  mut text : String
  mut markdown : Bool
  mut findings : Array[@rpc.TranscriptFinding]
  mut summary : @rpc.TranscriptSummary?
  mut expectations : @rpc.ExpectationResult?
  /// The sender of each `dir` value of a dir-message log.
  directions : Map[String, @rpc.PeerName]
  mut counts : @rpc.LogCounts?
}

///|
fn TranscriptWorld::new() -> TranscriptWorld {
  {
    model: None,
    protocol: None,
    text: "",
    markdown: false,
    findings: [],
    summary: None,
    expectations: None,
    directions: Map([]),
    counts: None,
  }
}

///|
/// Reads the transcript, checks it with the selected protocol and matches its
/// expect list, as `smithy validate rpc transcript` does.
fn TranscriptWorld::check(
  self : TranscriptWorld,
  text : String,
  markdown~ : Bool = false,
  completeness~ : @rpc.Completeness? = None,
) -> Unit raise {
  let (document, read) = if markdown {
    @rpc.read_markdown_transcript(text)
  } else {
    @rpc.read_json_transcript(text)
  }
  let protocol = @rpc.ProtocolDescription::from_smithy(
    self.model.unwrap(),
    self.protocol.unwrap(),
    document.version.unwrap(),
  )
  let run = @rpc.run_transcript(protocol, document, read, completeness?)
  self.text = text
  self.markdown = markdown
  self.findings = run.findings
  self.summary = Some(run.summary)
  self.expectations = run.expectations
}

///|
/// Reads a dir-message log with a LogReader and feeds each entry to the
/// checker, as `smithy validate rpc transcript` does for JSONL input. A log
/// has no header, so the version is given.
fn TranscriptWorld::check_log(
  self : TranscriptWorld,
  version : String,
  text : String,
) -> Unit raise {
  let version : @rpc.ProtocolVersion = match version {
    "1.0" => V1_0
    "2.0" => V2_0
    _ => fail("I expected version 1.0 or 2.0, and I found \{version}.")
  }
  let protocol = @rpc.ProtocolDescription::from_smithy(
    self.model.unwrap(),
    self.protocol.unwrap(),
    version,
  )
  let reader = @rpc.LogReader::new(
    @rpc.LogMapping::dir_message(self.directions),
  )
  let checker = @rpc.TranscriptChecker::new(protocol)
  let findings = []
  for read in [reader.push_text(text), reader.end()] {
    let (entries, problems) = read
    findings.append(problems)
    findings.append(checker.feed_all(entries))
  }
  let summary = checker.finish()
  findings.append(summary.findings)
  self.findings = findings
  self.summary = Some(summary)
  self.expectations = None
  self.counts = Some(reader.counts())
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
      markdown=file.has_suffix(".md"),
    )
  })
  setup.when1("I check the transcript:", fn(doc : @moonspec.DocString) raise {
    self.check(doc.content)
  })
  setup.when1("I check the Markdown transcript:", fn(
    doc : @moonspec.DocString,
  ) raise {
    self.check(doc.content, markdown=true)
  })
  setup.given2("the log direction {string} is sent by {string}", fn(
    dir : String,
    peer : String,
  ) raise {
    guard @rpc.PeerName::parse(peer) is Some(name) else {
      fail("I expected a peer name, and I found \{peer}.")
    }
    self.directions[dir] = name
  })
  setup.when2("I check the version {string} log file {string}", fn(
    version : String,
    file : String,
  ) raise {
    self.check_log(
      version,
      @xfs.read_file_to_string("../examples/json-rpc/transcripts/" + file),
    )
  })
  setup.when2("I check the version {string} log:", fn(
    version : String,
    doc : @moonspec.DocString,
  ) raise {
    self.check_log(version, doc.content)
  })
  setup.when0("I check the same transcript as complete", fn() raise {
    self.check(self.text, markdown=self.markdown, completeness=Some(Complete))
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
  setup.then3("the log has {int} lines, {int} not JSON and {int} skipped", fn(
    lines : Int32,
    not_json : Int32,
    skipped : Int32,
  ) raise {
    let counts = self.counts.unwrap()
    assert_eq(
      (counts.lines, counts.not_json, counts.skipped),
      (lines, not_json, skipped),
    )
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

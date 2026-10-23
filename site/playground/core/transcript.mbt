///|
/// A piece of the transcript in text order: an entry for the checker, or a
/// problem that the reader found in the text.
priv enum Item {
  Entry(@rpc.TranscriptEntry)
  Problem(@rpc.TranscriptFinding)
}

///|
/// A transcript that the page is stepping through.
priv struct Active {
  checker : @rpc.TranscriptChecker
  items : Array[Item]
  entries : Array[@rpc.TranscriptEntry]
  expect : Array[@rpc.ExpectedFinding]?
  reader : @rpc.LogReader?
  findings : Array[@rpc.TranscriptFinding]
  mut cursor : Int32
  mut fed : Int32
  mut summary : SummaryView?
}

///|
/// The state of the playground between requests: the transcript in progress.
pub struct Session {
  priv mut active : Active?
}

///|
pub fn Session::new() -> Session {
  { active: None, }
}

///|
pub fn FindingView::from_finding(
  finding : @rpc.TranscriptFinding,
) -> FindingView {
  {
    code: finding.code.to_string(),
    severity: if finding.severity == @validation.Error {
      "error"
    } else {
      "advisory"
    },
    message: finding.message,
    entry: finding.entry,
    line: finding.location.map(at => at.line),
    column: finding.location.map(at => at.column),
    sender: finding.sender.map(peer => peer.to_string()),
    related: finding.related,
    path: finding.finding.map(f => f.path.pointer()),
    shape: finding.finding.map(f => f.shape.to_string()),
    operation: finding.finding.bind(f => f.operation).map(id => id.to_string()),
  }
}

///|
fn expected_view(expected : @rpc.ExpectedFinding) -> ExpectedView {
  {
    code: expected.code(),
    entry: expected.entry(),
    related: expected.related(),
  }
}

///|
fn is_error(finding : @rpc.TranscriptFinding) -> Bool {
  finding.severity == @validation.Error
}

///|
fn progress(seq : Int32, active : Active) -> Response {
  let entries = active.entries.mapi((index, entry) => {
    index,
    sender: entry.sender.to_string(),
    receiver: entry.receiver.map(peer => peer.to_string()),
    message: entry.message,
    line: entry.location.map(at => at.line),
    column: entry.location.map(at => at.column),
    checked: index < active.fed,
  })
  TranscriptProgress(
    seq~,
    entries~,
    findings=active.findings.map(FindingView::from_finding),
    done=active.summary is Some(_),
    summary=active.summary,
  )
}

///|
/// Feed the next `count` entries to the checker. The problems of the reader that
/// come before the next entry are reported with the entry before them. After
/// the last entry, finish the check.
fn Active::advance(self : Active, count : Int32) -> Unit {
  if self.summary is Some(_) {
    return
  }
  let mut taken = 0
  while true {
    while self.cursor < self.items.length() &&
          self.items[self.cursor] is Problem(_) {
      if self.items[self.cursor] is Problem(problem) {
        self.findings.push(problem)
      }
      self.cursor += 1
    }
    if taken >= count || self.cursor >= self.items.length() {
      break
    }
    if self.items[self.cursor] is Entry(entry) {
      self.findings.append(self.checker.feed(entry))
      self.fed += 1
      taken += 1
    }
    self.cursor += 1
  }
  if self.cursor >= self.items.length() {
    self.finish()
  }
}

///|
fn Active::finish(self : Active) -> Unit {
  let result = self.checker.finish()
  self.findings.append(result.findings)
  let expectations = self.expect.map(expect => {
    let matched = @rpc.match_expected(expect, self.findings)
    {
      matched: matched.is_match(),
      missing: matched.missing.map(expected_view),
      unexpected: matched.unexpected
      .filter(is_error)
      .map(FindingView::from_finding),
    }
  })
  let counts = self.reader.map(reader => reader.counts())
  self.summary = Some({
    valid: result.complete && !self.findings.any(is_error),
    complete: result.complete,
    entries: result.entries,
    errors: self.findings.filter(is_error).length(),
    outstanding: result.outstanding,
    correlation: result.correlation,
    lines: counts.map(c => c.lines).unwrap_or(0),
    not_json: counts.map(c => c.not_json).unwrap_or(0),
    skipped: counts.map(c => c.skipped).unwrap_or(0),
    expectations,
  })
}

///|
/// The reader of a JSONL log for a preset: "dir-message", "dir-message:value=peer,...",
/// or "raw:peer".
fn log_mapping(
  preset : String?,
  protocol : @rpc.ProtocolDescription,
) -> Result[@rpc.LogMapping, String] {
  let peers = protocol.peers()
  let known = peers.map(peer => peer.to_string()).join(", ")
  fn peer(text : String) -> Result[@rpc.PeerName, String] {
    match @rpc.PeerName::parse(text) {
      Some(name) if peers.contains(name) => Ok(name)
      _ =>
        Err(
          "I expected a peer of the protocol (\{known}), but found '\{text}'.",
        )
    }
  }

  let text = preset.unwrap_or("dir-message")
  let (kind, argument) = match text.find(":") {
    Some(at) => (text[:at].to_owned(), Some(text[at + 1:].to_owned()))
    None => (text, None)
  }
  match (kind, argument) {
    ("raw", Some(name)) =>
      match peer(name) {
        Ok(sender) => Ok(@rpc.LogMapping::raw(sender))
        Err(reason) => Err(reason)
      }
    ("raw", None) =>
      Err("I expected a sender for the raw preset, as raw:<peer>.")
    ("dir-message", _) => {
      let directions : Map[String, @rpc.PeerName] = Map([])
      match argument {
        None => {
          directions["request"] = peers[0]
          directions["response"] = peers[1]
        }
        Some(list) =>
          for pair in list.split(",") {
            let pair = pair.to_owned()
            guard pair.rev_find("=") is Some(at) &&
              at > 0 &&
              at < pair.length() - 1 else {
              return Err(
                "I expected value=peer in the log preset, but found '\{pair}'.",
              )
            }
            let value = pair[:at].to_owned()
            if directions.contains(value) {
              return Err("The log preset gives the value '\{value}' twice.")
            }
            match peer(pair[at + 1:].to_owned()) {
              Ok(name) => directions[value] = name
              Err(reason) => return Err(reason)
            }
          }
      }
      try @rpc.LogMapping::dir_message(directions) catch {
        @validation.ConfigurationError(message) => Err(message)
      } noraise {
        mapping => Ok(mapping)
      }
    }
    _ =>
      Err(
        "I expected the log preset dir-message or raw:<peer>, but found '\{text}'.",
      )
  }
}

///|
/// Merge the problems of a log into its entries by line, as the CLI does.
fn merge_log(
  entries : Array[@rpc.TranscriptEntry],
  problems : Array[@rpc.TranscriptFinding],
) -> Array[Item] {
  fn line(location : @rpc.SourceLocation?) -> Int32 {
    location.map(at => at.line).unwrap_or(0)
  }

  let items = []
  let mut next = 0
  for entry in entries {
    while next < problems.length() &&
          line(problems[next].location) < line(entry.location) {
      items.push(Problem(problems[next]))
      next += 1
    }
    items.push(Entry(entry))
  }
  for problem in problems[next:] {
    items.push(Problem(problem))
  }
  items
}

///|
/// `--complete` makes the check complete. Without it, the document decides, and
/// a document that says nothing is partial: the defaults of the CLI.
fn completeness(
  complete : Bool,
  document : @rpc.Completeness?,
) -> @rpc.Completeness {
  if complete {
    @rpc.Complete
  } else {
    document.unwrap_or(@rpc.Partial)
  }
}

///|
fn protocol_error(error : Error) -> String {
  match error {
    @rpc.InvalidContract(id, message) => id.to_string() + ": " + message
    @validation.UnsupportedConstraint(id, message) =>
      id.to_string() + ": " + message
    other => other.to_string()
  }
}

///|
/// Start a transcript. A Markdown or JSON document gives its own version. A
/// JSONL log gives none, so it needs `version` ("1.0" or "2.0"), as the CLI
/// needs `--version`. `handle` passes no version, so a log is blocked there
/// until the request has a version field.
pub fn Session::start_transcript(
  self : Session,
  seq~ : Int32,
  model~ : String,
  protocol~ : String,
  format~ : TranscriptFormat,
  complete~ : Bool,
  log_preset~ : String?,
  text~ : String,
  version? : String,
) -> Response {
  self.active = None
  let given = match version {
    None => None
    Some(text) =>
      match @rpc.ProtocolVersion::parse(text) {
        Some(parsed) => Some(parsed)
        None =>
          return blocked(seq~, reason="I expected 1.0 or 2.0 for the version.")
      }
  }
  if format == Jsonl && given is None {
    return blocked(
      seq~,
      reason="A JSONL log gives no JSON-RPC version. I need version 1.0 or 2.0.",
    )
  }
  let assembled = match clean_model(load(model)) {
    Ok(assembled) => assembled
    Err((reason, kind)) => return Blocked(seq~, reason~, kind~)
  }
  guard @smithy.ShapeId::parse(protocol) is Some(id) else {
    return blocked(
      seq~,
      reason="I expected a shape ID for the protocol, but found '\{protocol}'.",
    )
  }
  guard assembled.shapes.get(id) is Some(_) else {
    return blocked(seq~, reason="I found no shape \{protocol} in the model.")
  }
  let (document, read_findings) = match format {
    Markdown => {
      let (document, findings) = @rpc.read_markdown_transcript(text)
      (Some(document), findings)
    }
    Json => {
      let (document, findings) = @rpc.read_json_transcript(text)
      (Some(document), findings)
    }
    Jsonl => (None, [])
  }
  let version = match (given, document.bind(d => d.version)) {
    (Some(version), _) | (None, Some(version)) => version
    (None, None) => {
      // A document that I could not read may have lost its version. Its error
      // findings explain the problem better than a missing version, as in the CLI.
      if read_findings.any(is_error) {
        return unread_document(seq, document.unwrap(), read_findings)
      }
      return blocked(
        seq~,
        reason="The transcript gives no JSON-RPC version. Add version: 1.0 or version: 2.0 to it.",
      )
    }
  }
  let description = @rpc.ProtocolDescription::from_smithy(
    assembled, id, version,
  ) catch {
    error => return blocked(seq~, reason=protocol_error(error))
  }
  let active = match document {
    Some(document) => {
      let items : Array[Item] = read_findings.map(problem => Problem(problem))
      for entry in document.entries {
        items.push(Entry(entry))
      }
      {
        checker: @rpc.TranscriptChecker::new(
          description,
          completeness=completeness(complete, document.completeness),
        ),
        items,
        entries: document.entries,
        expect: document.expect,
        reader: None,
        findings: [],
        cursor: 0,
        fed: 0,
        summary: None,
      }
    }
    None => {
      let mapping = match log_mapping(log_preset, description) {
        Ok(mapping) => mapping
        Err(reason) => return blocked(seq~, reason~)
      }
      let reader = @rpc.LogReader::new(mapping) catch {
        @validation.ConfigurationError(message) =>
          return blocked(seq~, reason=message)
      }
      let (entries, problems) = reader.push_text(text)
      let (more_entries, more_problems) = reader.end()
      let all_entries = entries + more_entries
      let all_problems = problems + more_problems
      {
        checker: @rpc.TranscriptChecker::new(
          description,
          completeness=completeness(complete, None),
          correlation=!reader.single_sender(),
        ),
        items: merge_log(all_entries, all_problems),
        entries: all_entries,
        expect: None,
        reader: Some(reader),
        findings: [],
        cursor: 0,
        fed: 0,
        summary: None,
      }
    }
  }
  active.advance(0)
  self.active = Some(active)
  progress(seq, active)
}

///|
fn step_transcript(session : Session, seq : Int32, count : Int32) -> Response {
  guard session.active is Some(active) else {
    return blocked(
      seq~,
      reason="I have no transcript to check. Start one first.",
    )
  }
  active.advance(count)
  progress(seq, active)
}

///|
/// The response for a document that I cannot check: its reader findings only,
/// and a summary that is not valid and not complete. The CLI writes the same.
fn unread_document(
  seq : Int32,
  document : @rpc.TranscriptDocument,
  read_findings : Array[@rpc.TranscriptFinding],
) -> Response {
  let entries = document.entries.mapi((index, entry) => {
    index,
    sender: entry.sender.to_string(),
    receiver: entry.receiver.map(peer => peer.to_string()),
    message: entry.message,
    line: entry.location.map(at => at.line),
    column: entry.location.map(at => at.column),
    checked: false,
  })
  TranscriptProgress(
    seq~,
    entries~,
    findings=read_findings.map(FindingView::from_finding),
    done=true,
    summary=Some({
      valid: false,
      complete: false,
      entries: 0,
      errors: read_findings.filter(is_error).length(),
      outstanding: 0,
      correlation: true,
      lines: 0,
      not_json: 0,
      skipped: 0,
      expectations: None,
    }),
  )
}

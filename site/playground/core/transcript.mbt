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
  /// The number of findings that a response has given.
  mut reported : Int32
  /// The peer names of the protocol.
  peers : Array[String]
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
/// True for the text of a JSON-RPC response: an object with no `method`, or a
/// batch whose first item is one.
fn is_reply(message : String) -> Bool {
  let value = @json.parse(message) catch { _ => return false }
  match value {
    Object(fields) => !fields.contains("method")
    Array([Object(fields), ..]) => !fields.contains("method")
    _ => false
  }
}

///|
/// The entries for the page. An entry goes to the other peer, so a request
/// with no named receiver gets the other peer of `peers`; a reply gets none.
fn entry_views(
  entries : Array[@rpc.TranscriptEntry],
  peers : Array[String],
) -> Array[EntryView] {
  entries.mapi((index, entry) => {
    let sender = entry.sender.to_string()
    let receiver = match entry.receiver {
      Some(peer) => Some(peer.to_string())
      None if is_reply(entry.message) => None
      None => peers.iter().find_first(peer => peer != sender)
    }
    {
      index,
      sender,
      receiver,
      message: entry.message,
      line: entry.location.map(at => at.line),
      column: entry.location.map(at => at.column),
    }
  })
}

///|
/// The change since the previous response: the entries at the start, and the
/// findings that no response has given yet.
fn progress(seq : Int32, active : Active, first~ : Bool) -> Response {
  let findings = active.findings[active.reported:]
    .iter()
    .map(FindingView::from_finding)
    .to_array()
  active.reported = active.findings.length()
  TranscriptProgress(
    seq~,
    entries=if first { entry_views(active.entries, active.peers) } else { [] },
    findings~,
    checked=active.fed,
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
/// The reader of a JSONL log for a preset. The peers must be peers of the
/// protocol, as the CLI checks them.
fn log_mapping(
  preset : LogPreset?,
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

  match preset.unwrap_or(DirMessage([])) {
    Raw(sender~) => peer(sender).map(@rpc.LogMapping::raw)
    DirMessage(directions) => {
      let map : Map[String, @rpc.PeerName] = Map([])
      if directions.is_empty() {
        map["request"] = peers[0]
        map["response"] = peers[1]
      }
      for direction in directions {
        if direction.value == "" {
          return Err(
            "I expected a dir value for the peer \{direction.peer}, but found none.",
          )
        }
        if map.contains(direction.value) {
          return Err(
            "The log preset gives the value '\{direction.value}' twice.",
          )
        }
        match peer(direction.peer) {
          Ok(name) => map[direction.value] = name
          Err(reason) => return Err(reason)
        }
      }
      try @rpc.LogMapping::dir_message(map) catch {
        @validation.ConfigurationError(message) => Err(message)
      } noraise {
        mapping => Ok(mapping)
      }
    }
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
/// Start a transcript of the one model file `MODEL_FILE`.
pub fn Session::start_transcript(
  self : Session,
  seq~ : Int32,
  model~ : String,
  protocol~ : String,
  format~ : TranscriptFormat,
  complete~ : Bool,
  log_preset~ : LogPreset?,
  version~ : String?,
  text~ : String,
) -> Response {
  self.start_transcript_files(
    seq~,
    files=[(MODEL_FILE, model)],
    protocol~,
    format~,
    complete~,
    log_preset~,
    version~,
    text~,
  )
}

///|
/// Start a transcript. A Markdown or JSON document gives its own version. A
/// JSONL log gives none, so it needs `version` ("1.0" or "2.0"), as the CLI
/// needs `--version`. A version for a document must equal the document's. The
/// checks come in the order of the CLI: the options, the model, then the text.
/// The model has several files, as (name, text).
pub fn Session::start_transcript_files(
  self : Session,
  seq~ : Int32,
  files~ : Array[(String, String)],
  protocol~ : String,
  format~ : TranscriptFormat,
  complete~ : Bool,
  log_preset~ : LogPreset?,
  version~ : String?,
  text~ : String,
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
  if format != Jsonl && log_preset is Some(_) {
    return blocked(seq~, reason="A log preset applies only to a JSONL log.")
  }
  if format == Jsonl && given is None {
    return blocked(
      seq~,
      reason="A JSONL log gives no JSON-RPC version. I need version 1.0 or 2.0.",
    )
  }
  let assembled = match clean_model(load(files)) {
    Ok(assembled) => assembled
    Err((reason, kind)) => return Blocked(seq~, reason~, kind~)
  }
  guard @smithy.ShapeId::parse(protocol) is Some(id) else {
    return blocked(
      seq~,
      reason="I expected a shape ID for the protocol, but found '\{protocol}'.",
    )
  }
  guard assembled.shapes.get(id) is Some(shape) else {
    return blocked(seq~, reason="I found no shape \{protocol} in the model.")
  }
  let peers = protocol_peers(shape)
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
    (Some(chosen), Some(written)) if chosen != written =>
      return blocked(
        seq~,
        reason="The version \{chosen.to_string()} conflicts with version \{written.to_string()} in the transcript.",
      )
    (Some(version), _) | (None, Some(version)) => version
    (None, None) => {
      // A document that I could not read may have lost its version. Its error
      // findings explain the problem better than a missing version, as in the CLI.
      if read_findings.any(is_error) {
        return unread_document(seq, document.unwrap(), read_findings, peers)
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
        reported: 0,
        peers,
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
        reported: 0,
        peers,
      }
    }
  }
  active.advance(0)
  self.active = Some(active)
  progress(seq, active, first=true)
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
  progress(seq, active, first=false)
}

///|
/// The response for a document that I cannot check: its reader findings only,
/// and a summary that is not valid and not complete. The CLI writes the same.
/// The CLI matches only an `--expect` file against these findings, not the
/// expect list of the document, so the summary has no expectations.
fn unread_document(
  seq : Int32,
  document : @rpc.TranscriptDocument,
  read_findings : Array[@rpc.TranscriptFinding],
  peers : Array[String],
) -> Response {
  TranscriptProgress(
    seq~,
    entries=entry_views(document.entries, peers),
    findings=read_findings.map(FindingView::from_finding),
    checked=0,
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

///|
/// The place and subject of a finding as the CLI writes them:
/// `<file>:<line>:<column>: entry <n> <sender>`, with no part that the finding
/// does not have.
fn finding_place(file : String, finding : FindingView) -> String {
  let location = match (finding.line, finding.column) {
    (Some(line), Some(column)) => "\{file}:\{line}:\{column}"
    _ => file
  }
  let subject = []
  if finding.entry is Some(entry) {
    subject.push("entry \{entry}")
  }
  if finding.sender is Some(sender) {
    subject.push(sender)
  }
  if subject.is_empty() {
    location
  } else {
    "\{location}: \{subject.join(" ")}"
  }
}

///|
/// The line that `smithy validate rpc transcript` writes for the finding:
/// `<file>:<line>:<column>: entry <n> <sender>: <severity> <code>: <message>`,
/// with no part that the finding does not have.
pub fn FindingView::cli_line(self : FindingView, file~ : String) -> String {
  "\{finding_place(file, self)}: \{self.severity} \{self.code}: \{self.message}"
}

///|
/// The expect lines that the CLI writes after the findings: one per missing
/// item, then one per unexpected error.
pub fn ExpectationView::cli_lines(
  self : ExpectationView,
  file~ : String,
) -> Array[String] {
  let lines = self.missing.map(expected => {
    let entry = expected.entry.map(n => " at entry \{n}").unwrap_or("")
    let related = expected.related
      .map(n => " related to entry \{n}")
      .unwrap_or("")
    "\{file}: expect: I expected \{expected.code}\{entry}\{related}; no finding matches it."
  })
  for finding in self.unexpected {
    lines.push(
      "\{finding_place(file, finding)}: expect: I did not expect error \{finding.code}.",
    )
  }
  lines
}

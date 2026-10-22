///|
fn pick(n : Int32, size : Int32) -> Int32 {
  (n % size + size) % size
}

///|
/// One entry from a pool of calls, replies, notifications, batches, invalid and
/// wrong-ID entries for the Editor protocol, in both directions.
fn pooled_entry(choice : Int32, id : Int32) -> @rpc.TranscriptEntry {
  let id = pick(id, 4).to_string()
  let pool = [
    ("client", hover(id)),
    ("server", hover_reply(id)),
    ("client", "{\"jsonrpc\": \"2.0\", \"method\": \"exit\"}"),
    ("client", "{\"jsonrpc\": \"2.0\", \"method\": "),
    ("server", hover_reply("\"" + id + "\"")),
    (
      "server",
      "{\"jsonrpc\": \"2.0\", \"id\": " +
      id +
      ", \"method\": \"workspace/configuration\", \"params\": {}}",
    ),
    ("client", "{\"jsonrpc\": \"2.0\", \"id\": " + id + ", \"result\": []}"),
    (
      "server", "{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32700, \"message\": \"Parse error\"}, \"id\": null}",
    ),
    ("client", "{\"jsonrpc\": \"2.0\", \"id\": null, \"method\": \"shutdown\"}"),
    ("nobody", "{}"),
    ("client", "[" + hover(id) + "]"),
    ("client", "[" + hover(id) + "," + hover("\"" + id + "\"") + "]"),
    ("server", "[" + hover_reply(id) + "]"),
    (
      "server",
      "[" + hover_reply("\"" + id + "\"") + "," + hover_reply(id) + "]",
    ),
    ("client", "[]"),
    ("client", "[1, {\"jsonrpc\": \"2.0\", \"method\": \"exit\"}]"),
    (
      "server", "[{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32600, \"message\": \"Invalid Request\"}, \"id\": null}]",
    ),
    (
      "server", "{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32600, \"message\": \"Invalid Request\"}, \"id\": null}",
    ),
  ]
  let (sender, message) = pool[pick(choice, pool.length())]
  { sender: peer(sender), message, receiver: None, location: None, }
}

///|
test "chunking does not change findings" {
  let protocol = editor()
  @quickcheck.check(
    (input : (Array[(Int32, Int32)], Array[Int32], Bool)) => {
      let (choices, groups, complete) = input
      let entries = choices.map(c => pooled_entry(c.0, c.1))
      let completeness : @rpc.Completeness = if complete {
        Complete
      } else {
        Partial
      }
      let limits = @rpc.TranscriptLimits::new(
        active_calls=3,
        answered_ids=2,
        findings=40,
      ) catch {
        _ => return false
      }
      let single = @rpc.TranscriptChecker::new(protocol, completeness~, limits~)
      let one_by_one = []
      for entry in entries {
        one_by_one.append(single.feed(entry))
      }
      let grouped = @rpc.TranscriptChecker::new(
        protocol,
        completeness~,
        limits~,
      )
      let in_groups = []
      let mut start = 0
      let mut g = 0
      while start < entries.length() {
        let size = if groups.is_empty() {
          1
        } else {
          pick(groups[g % groups.length()], 5) + 1
        }
        let end = if start + size < entries.length() {
          start + size
        } else {
          entries.length()
        }
        in_groups.append(grouped.feed_all(entries[start:end].to_owned()))
        start = end
        g += 1
      }
      let whole = @rpc.TranscriptChecker::new(protocol, completeness~, limits~)
      let at_once = whole.feed_all(entries)
      let summary = single.finish()
      one_by_one == in_groups &&
      one_by_one == at_once &&
      summary == grouped.finish() &&
      summary == whole.finish()
    },
    count=200,
    max_size=40,
    seed=3408,
  )
}

///|
/// Arbitrary text, alone or inside call, reply and batch shapes with exact,
/// null and structured IDs.
fn shaped(text : String, choice : Int32) -> String {
  let ids = ["1", "null", "[1, {\"a\": 2}]", "1.0e400", "\"x\""]
  let id = ids[pick(choice / 15, ids.length())]
  let quoted = Json::string(text).stringify()
  let reply = "{\"jsonrpc\": \"2.0\", \"id\": " +
    id +
    ", \"result\": " +
    quoted +
    "}"
  match pick(choice / 3, 6) {
    0 => text
    1 => "{\"method\": " + quoted + ", \"params\": [], \"id\": " + id + "}"
    2 => "{\"result\": null, \"error\": null, \"id\": " + id + "}"
    3 => reply
    4 => "[" + reply + ", " + text + "]"
    _ => "[" + text + "]"
  }
}

///|
test "the checker never panics on arbitrary text" {
  let protocols = [chat(), editor()]
  @quickcheck.check(
    (input : (Array[(String, String, Int32)], Bool)) => {
      let (raw, complete) = input
      for protocol in protocols {
        let checker = @rpc.TranscriptChecker::new(
          protocol,
          completeness=if complete { Complete } else { Partial },
        )
        let known = protocol.peers()
        let mut fed = 0
        for item in raw {
          let (name, message, choice) = item
          let sender = match pick(choice, 3) {
            0 => known[0]
            1 => known[1]
            _ => @rpc.PeerName::parse(name).unwrap_or(peer("stranger"))
          }
          let found = checker.feed({
            sender,
            receiver: None,
            message: shaped(message, choice),
            location: None,
          })
          let index = fed
          fed += 1
          if found.iter().any(f => f.entry != Some(index)) {
            return false
          }
        }
        let summary = checker.finish()
        if summary.entries != raw.length() ||
          summary.findings.iter().any(f => f.entry is None) {
          return false
        }
      }
      true
    },
    count=300,
    max_size=30,
    seed=3409,
  )
}

///|
/// Gives `text` to a new reader, cut at `cuts` (UTF-16 offsets, which can
/// split a surrogate pair or a CRLF).
fn read_cut(
  mapping : @rpc.LogMapping,
  text : String,
  cuts : Array[Int32],
  line_bytes : Int32,
) -> (
  Array[@rpc.TranscriptEntry],
  Array[@rpc.TranscriptFinding],
  @rpc.LogCounts,
) {
  let reader = @rpc.LogReader::new(mapping, line_bytes~)
  let entries = []
  let findings = []
  let mut start = 0
  for cut in cuts + [text.length()] {
    let (e, f) = reader.push_text(text.unsafe_substring(start~, end=cut))
    entries.append(e)
    findings.append(f)
    start = cut
  }
  let (e, f) = reader.end()
  (entries + e, findings + f, reader.counts())
}

///|
test "text chunking does not change log entries" {
  let problems = editor_dir_ndjson() +
    "{\"dir\": \"sideways\", \"message\": {\"jsonrpc\": \"2.0\", \"method\": \"exit\"}}\n" +
    "{\"dir\": \"request\"}\n" +
    "plain 🐢 text\n" +
    "{\"dir\": \"request\", \"message\": {\"jsonrpc\": \"2.0\", \"method\": \"exit\", \"params\": {\"note\": \"" +
    "😀".repeat(40) +
    "\"}}}\n"
  let fixtures = [
    (in_out(), editor_jsonl(), 1048576),
    (request_response(), editor_dir_ndjson(), 1048576),
    (mcp_like_mapping(), mcp_like_jsonl(), 1048576),
    (request_response(), problems, 120),
  ]
  @quickcheck.check(
    (input : (Int32, Array[Int32], Int32)) => {
      let (choice, raw_cuts, variant) = input
      let (mapping, base, line_bytes) = fixtures[pick(choice, fixtures.length())]
      let reader = @rpc.LogReader::new(mapping, line_bytes~)
      let (one_entries, one_findings) = reader.push_text(base)
      let (rest, tail) = reader.end()
      let expected = (one_entries + rest, one_findings + tail, reader.counts())
      // The same log with CRLF, a leading BOM or no final newline.
      let mut text = base
      if pick(variant, 2) == 1 {
        text = text.replace_all(old="\n", new="\r\n")
      }
      if pick(variant / 2, 2) == 1 {
        text = "\u{FEFF}" + text
      }
      if pick(variant / 4, 2) == 1 {
        text = text.trim_end(chars="\r\n").to_owned()
      }
      let cuts = raw_cuts.map(c => pick(c, text.length() + 1))
      cuts.sort()
      read_cut(mapping, text, cuts, line_bytes) == expected
    },
    count=400,
    max_size=24,
    seed=3410,
  )
}

///|
test "formats agree apart from locations" {
  let (json, json_read) = @rpc.read_json_transcript(editor_json())
  let (markdown, markdown_read) = @rpc.read_markdown_transcript(
    editor_markdown(),
  )
  let (entries, log_read, _) = read_log(request_response(), editor_dir_ndjson())
  assert_eq(json_read, [])
  assert_eq(markdown_read, [])
  assert_eq(log_read, [])
  let log : @rpc.TranscriptDocument = {
    version: None,
    completeness: None,
    entries,
    expect: None,
  }
  let documents = [json, markdown, log]
  let senders = documents.map(d => d.entries.map(e => (e.sender, e.message)))
  assert_eq(senders[1], senders[0])
  assert_eq(senders[2], senders[0])
  fn unlocated(
    findings : Array[@rpc.TranscriptFinding],
  ) -> Array[@rpc.TranscriptFinding] {
    findings.map(f => { ..f, location: None, })
  }

  let mut found = 0
  for protocol in [editor(), chat()] {
    for completeness in [@rpc.Complete, @rpc.Partial] {
      let runs = documents.map(d => {
        let run = @rpc.run_transcript(protocol, d, [], completeness~)
        let summary = run.summary
        (
          unlocated(run.findings),
          unlocated(summary.findings),
          (
            summary.entries,
            summary.outstanding,
            summary.correlation,
            summary.complete,
          ),
        )
      })
      assert_eq(runs[1], runs[0])
      assert_eq(runs[2], runs[0])
      found += runs[0].0.length()
    }
  }
  // The 1.0 chat protocol rejects the 2.0 messages, so the law compares real
  // findings, not only empty lists.
  assert_true(found > 0)
}

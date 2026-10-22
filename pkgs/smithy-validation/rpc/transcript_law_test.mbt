///|
fn pick(n : Int32, size : Int32) -> Int32 {
  (n % size + size) % size
}

///|
/// One entry from a pool of calls, replies, notifications, invalid and
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
  ]
  let (sender, message) = pool[pick(choice, pool.length())]
  { sender: peer(sender), message, location: None, }
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
  match pick(choice / 3, 5) {
    0 => text
    1 => "{\"method\": " + quoted + ", \"params\": [], \"id\": " + id + "}"
    2 => "{\"result\": null, \"error\": null, \"id\": " + id + "}"
    3 =>
      "{\"jsonrpc\": \"2.0\", \"id\": " + id + ", \"result\": " + quoted + "}"
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

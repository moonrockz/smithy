///|
/// One case of `cli-cases.json`: the arguments and files of a CLI run, and the
/// status and lines that the CLI printed.
priv struct CliCase {
  id : String
  args : Array[String]
  files : Map[String, String]
  status : Int32
  lines : Array[String]
}

///|
/// The text of a repository file; the tests run in `site/`.
fn repository_file(path : String) -> String raise {
  @fs.read_file_to_string("../" + path)
}

///|
fn string_of(json : Json, what : String) -> String raise {
  guard json is String(text) else {
    fail("I expected a string for \{what}, but found \{json.stringify()}")
  }
  text
}

///|
/// The ids that the file must hold: a case lost in a merge fails.
let expected_ids : Array[String] = [
  "value-consumer-valid", "value-consumer-invalid", "value-unknown-reject", "value-unknown-ignore",
  "value-json-names", "value-member-target", "value-not-json", "value-duplicate-key",
  "value-missing-target", "value-invalid-model", "value-unsupported-pattern", "value-unsupported-timestamp",
  "value-json-limit", "rpc-call", "rpc-invalid", "rpc-reply", "rpc-error", "rpc-reply-no-context",
  "rpc-not-json", "rpc-missing-service", "rpc-legacy-call", "rpc-legacy-error", "rpc-legacy-opaque",
  "rpc-legacy-version-2", "rpc-envelope-only", "rpc-unknown-reject", "rpc-unknown-ignore",
  "diff-constraints-added",
]

///|
fn load_cases() -> Array[CliCase] raise {
  let cases = read_cases()
  let seen : Array[String] = []
  for c in cases {
    if seen.contains(c.id) {
      fail("duplicate case id \{c.id}")
    }
    seen.push(c.id)
  }
  if cases.is_empty() {
    fail("cli-cases.json has no case")
  }
  if seen != expected_ids {
    fail(
      "the case ids are \{Json(seen).stringify()} but I expected \{Json(expected_ids).stringify()}",
    )
  }
  cases
}

///|
fn read_cases() -> Array[CliCase] raise {
  let json = @json.parse(
    @fs.read_file_to_string("playground/cli_check/cli-cases.json"),
  )
  guard json is { "cases": Array(items), .. } else {
    fail("cli-cases.json must have a cases array")
  }
  items.map(item => {
    guard item
      is {
        "id": String(id),
        "args": Array(args),
        "files": Array(files),
        "status": Number(status, ..),
        "lines": Array(lines),
        ..
      } else {
      fail("a case needs id, args, files, status and lines")
    }
    let by_name : Map[String, String] = Map([])
    for file in files {
      guard file is { "name": String(name), .. } else {
        fail("\{id}: a file needs a name")
      }
      by_name[name] = match file {
        { "text": _, "from": _, .. } =>
          fail("\{id}: file \{name} needs exactly one of text and from")
        { "text": String(text), .. } => text
        { "from": String(from), .. } => repository_file(from)
        _ => fail("\{id}: file \{name} needs exactly one of text and from")
      }
    }
    {
      id,
      args: args.map(arg => string_of(arg, id + " argument")),
      files: by_name,
      status: status.to_int(),
      lines: lines.map(line => string_of(line, id + " line")),
    }
  })
}

///|
fn file_of(files : Map[String, String], name : String) -> String raise {
  match files.get(name) {
    Some(text) => text
    None => fail("the case has no file '\{name}'")
  }
}

///|
/// The core request for the arguments of a CLI run, and the input file name
/// that `cli_line` prints. It knows `validate value`, `validate rpc` and `diff --old A --new B`
/// (one file each).
fn request_of(
  args : Array[String],
  files : Map[String, String],
) -> (@core.Request, String) raise {
  match args {
    ["validate", "value", .. rest] => value_request_of(rest, files)
    ["validate", "rpc", .. rest] => rpc_request_of(rest, files)
    ["diff", "--old", old, "--new", new] =>
      (
        DiffModels(seq=1, old=[(old, file_of(files, old))], new=[
          (new, file_of(files, new)),
        ]),
        "",
      )
    _ =>
      fail("the differential test does not know the command \{args.join(" ")}")
  }
}

///|
/// `validate value` with `--shape`, `--value`, `--unknown-members` and
/// `--member-names`; any other argument is a model file.
fn value_request_of(
  rest : ArrayView[String],
  files : Map[String, String],
) -> (@core.Request, String) raise {
  let models : Array[(String, String)] = []
  let mut shape : String? = None
  let mut value : String? = None
  let mut unknown_members : @core.UnknownMembers = Reject
  let mut member_names : @core.MemberNames = Smithy
  let mut i = 0
  let option_value = fn(i : Int32, name : String) -> String raise {
    guard i + 1 < rest.length() else {
      fail("the option \{name} needs a value")
    }
    rest[i + 1]
  }
  while i < rest.length() {
    match rest[i] {
      "--shape" => {
        shape = Some(option_value(i, "--shape"))
        i += 2
      }
      "--value" => {
        value = Some(option_value(i, "--value"))
        i += 2
      }
      "--unknown-members" => {
        unknown_members = match option_value(i, "--unknown-members") {
          "reject" => Reject
          "ignore" => Ignore
          other => fail("I do not know --unknown-members \{other}")
        }
        i += 2
      }
      "--member-names" => {
        member_names = match option_value(i, "--member-names") {
          "smithy" => Smithy
          "json" => JsonName
          other => fail("I do not know --member-names \{other}")
        }
        i += 2
      }
      option if option.has_prefix("--") =>
        fail("the differential test does not know the option \{option}")
      model => {
        models.push((model, file_of(files, model)))
        i += 1
      }
    }
  }
  guard shape is Some(shape) && value is Some(value) else {
    fail("a value case needs --shape and --value")
  }
  (
    CheckValue(seq=1, files=models, shape~, value=file_of(files, value), options={
      unknown_members,
      member_names,
    }),
    value,
  )
}

///|
/// `validate rpc` for one message: `--version`, `--service`, `--message` or
/// `--response`, the response context (`--method`, `--operation`, `--request`,
/// `--envelope-only`), `--legacy-errors` and `--unknown-members`; any other argument is a model file. The presence of
/// `--legacy-errors` gives `Some`, its absence `None`, as the CLI tells them apart.
fn rpc_request_of(
  rest : ArrayView[String],
  files : Map[String, String],
) -> (@core.Request, String) raise {
  let models : Array[(String, String)] = []
  let mut version : @core.RpcVersion? = None
  let mut service : String? = None
  let mut message : String? = None
  let mut response : String? = None
  let mut context : @core.ResponseContext? = None
  let mut legacy_errors : @core.LegacyErrors? = None
  let mut unknown_members : @core.UnknownMembers = Reject
  let set_context = fn(next : @core.ResponseContext) -> Unit raise {
    if context is Some(_) {
      fail("a case needs at most one response context")
    }
    context = Some(next)
  }
  let mut i = 0
  while i < rest.length() {
    let option = rest[i]
    if option == "--envelope-only" {
      set_context(EnvelopeOnly)
      i += 1
      continue
    }
    if !option.has_prefix("--") {
      models.push((option, file_of(files, option)))
      i += 1
      continue
    }
    guard i + 1 < rest.length() else {
      fail("the option \{option} needs a value")
    }
    let argument = rest[i + 1]
    match option {
      "--version" =>
        version = Some(
          match argument {
            "1.0" => V1_0
            "2.0" => V2_0
            other => fail("I do not know --version \{other}")
          },
        )
      "--service" => service = Some(argument)
      "--message" => message = Some(argument)
      "--response" => response = Some(argument)
      "--method" => set_context(Method(argument))
      "--operation" => set_context(Operation(argument))
      "--request" => set_context(OriginalRequest(file_of(files, argument)))
      "--legacy-errors" =>
        legacy_errors = Some(
          match argument {
            "opaque" => Opaque
            "code-message-data" => CodeMessageData
            other => fail("I do not know --legacy-errors \{other}")
          },
        )
      "--unknown-members" =>
        unknown_members = match argument {
          "reject" => Reject
          "ignore" => Ignore
          other => fail("I do not know --unknown-members \{other}")
        }
      _ => fail("the differential test does not know the option \{option}")
    }
    i += 2
  }
  guard version is Some(version) && service is Some(service) else {
    fail("an rpc case needs --version and --service")
  }
  let (file, kind) = match (message, response) {
    (Some(file), None) => (file, @core.MessageKind::RequestMessage)
    (None, Some(file)) => (file, ResponseMessage(context~, legacy_errors~))
    _ => fail("an rpc case needs exactly one of --message and --response")
  }
  (
    CheckMessage(
      seq=1,
      files=models,
      service~,
      version~,
      message=file_of(files, file),
      kind~,
      options={ unknown_members, member_names: Smithy, },
    ),
    file,
  )
}

///|
/// The lines of `smithy diff --old A --new B`: the events (stdout), then, on
/// stderr, the ERROR, DANGER and WARNING findings of each model with its path.
/// `ModelNotBuilt` is a finding for the page only; the CLI prints no line for it.
fn diff_lines(
  old_path : String,
  new_path : String,
  old : Array[@core.Diagnostic],
  new : Array[@core.Diagnostic],
  events : Array[@core.DiffEvent]?,
) -> Array[String] {
  let lines = match events {
    Some(events) => events.map(@core.DiffEvent::cli_line)
    None => []
  }
  for side in [(old_path, old), (new_path, new)] {
    for d in side.1 {
      if d.code != "ModelNotBuilt" &&
        (
          d.severity == "ERROR" ||
          d.severity == "DANGER" ||
          d.severity == "WARNING"
        ) {
        let event : @core.DiffEvent = {
          id: d.code,
          severity: d.severity,
          shape: d.shape,
          message: d.message,
        }
        lines.push("\{side.0}: \{event.cli_line()}")
      }
    }
  }
  lines
}

///|
test "ModelNotBuilt never enters the CLI lines" {
  let page_only : @core.Diagnostic = {
    severity: "ERROR",
    code: "ModelNotBuilt",
    message: "I could not build a model from the text, and I have no error to show.",
    file: "",
    start_line: 0,
    start_column: 0,
    end_line: 0,
    end_column: 0,
    shape: None,
  }
  assert_eq(diff_lines("a", "b", [page_only], [page_only], None), [])
}

///|
test "every CLI case gives the CLI lines and the CLI status in the core" {
  for c in load_cases() {
    let (request, file) = request_of(c.args, c.files)
    match @core.handle(@core.Session::new(), request) {
      DataChecked(valid~, findings~, ..) => {
        let lines = findings.map(f => f.cli_line(file~))
        if lines != c.lines {
          fail(
            "\{c.id}: the core gave \{Json(lines).stringify()} but the CLI printed \{Json(c.lines).stringify()}",
          )
        }
        if valid != (c.status == 0) {
          fail("\{c.id}: valid is \{valid} but the CLI status is \{c.status}")
        }
      }
      // A usage error before any check: the CLI prints `smithy: <reason>`, status 2.
      Blocked(reason~, kind=Other, ..) => {
        let lines = ["smithy: \{reason}"]
        if lines != c.lines || c.status != 2 {
          fail(
            "\{c.id}: the core blocked with \{Json(lines).stringify()} but the CLI printed \{Json(c.lines).stringify()} with status \{c.status}",
          )
        }
      }
      Diffed(old~, new~, events~, breaking~, ..) => {
        let (old_path, new_path) = match c.args {
          ["diff", "--old", old, "--new", new] => (old, new)
          _ => fail("\{c.id}: I expected diff arguments")
        }
        let lines = diff_lines(old_path, new_path, old, new, events)
        if lines != c.lines {
          fail(
            "\{c.id}: the core gave \{Json(lines).stringify()} but the CLI printed \{Json(c.lines).stringify()}",
          )
        }
        let status = if events is Some(_) && !breaking { 0 } else { 1 }
        if status != c.status {
          fail(
            "\{c.id}: the core means status \{status} but the CLI status is \{c.status}",
          )
        }
      }
      other =>
        fail(
          "\{c.id}: I expected DataChecked, but found \{@json.to_json(other).stringify()}",
        )
    }
  }
}

///|
test "the consumer cases use the model and the values of examples/validation-consumer" {
  let main = repository_file("examples/validation-consumer/main.mbtx")
  let by_id : Map[String, CliCase] = Map([])
  for c in load_cases() {
    by_id[c.id] = c
  }
  let valid = by_id["value-consumer-valid"]
  let invalid = by_id["value-consumer-invalid"]
  for
    text in [
      file_of(valid.files, "example.smithy"),
      file_of(valid.files, "value.json"),
      file_of(invalid.files, "value.json"),
    ] {
    // A MoonBit literal of this ASCII text has the same escapes as JSON.
    let literal = Json::string(text).stringify()
    assert_true(main.contains(literal), msg="main.mbtx lacks \{literal}")
  }
}

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
  "value-json-limit",
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
/// that `cli_line` prints. It knows `validate value` with `--shape`, `--value`,
/// `--unknown-members` and `--member-names`; any other argument is a model file.
fn request_of(
  args : Array[String],
  files : Map[String, String],
) -> (@core.Request, String) raise {
  guard args is ["validate", "value", .. rest] else {
    fail("the differential test does not know the command \{args.join(" ")}")
  }
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

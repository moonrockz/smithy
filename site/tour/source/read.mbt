///|
/// Read the lessons folder. The error names the folder and the problem.
/// `repo` is the repository root that include paths are relative to.
pub fn read_tour(root : String, repo~ : String) -> Result[@model.Tour, String] {
  Ok(read_root(root, repo)) catch {
    Failure(msg) => Err(msg)
    e => Err("\{root}: \{e}")
  }
}

///|
fn io(path : String, f : () -> String raise @fs.IOError) -> String raise {
  f() catch {
    IOError(reason) => fail("\{path}: I cannot read it: \{reason}")
  }
}

///|
/// The names in the folder, sorted, without the names that start with `.`
/// (such as `.DS_Store`): they are not part of a lesson.
fn list_dir(path : String) -> Array[String] raise {
  let names = @fs.read_dir(path) catch {
    IOError(reason) => fail("\{path}: I cannot list the folder: \{reason}")
  }
  let sorted = names.filter(n => !n.has_prefix("."))
  sorted.sort_by(@model.compare_code_units)
  sorted
}

///|
fn is_dir(path : String) -> Bool raise {
  @fs.is_dir(path) catch {
    IOError(reason) => fail("\{path}: I cannot read it: \{reason}")
  }
}

///|
fn read_root(root : String, repo : String) -> @model.Tour raise {
  let lessons : Array[@model.Lesson] = []
  for name in list_dir(root) {
    let path = "\{root}/\{name}"
    if !is_dir(path) {
      continue
    }
    lessons.push(read_lesson(root, name, repo))
  }
  if lessons.is_empty() {
    fail("\{root}: I found no lesson folder")
  }
  for i, lesson in lessons {
    if i > 0 && lessons[i - 1].number == lesson.number {
      fail(
        "\{lessons[i - 1].dir} and \{lesson.dir}: both lessons have the number \{lesson.number}",
      )
    }
    let expected = i + 1
    if lesson.number != expected {
      fail(
        "\{lesson.dir}: I expected the number \{expected}, because the numbers start at 1 and have no gap. The number \{expected} is missing",
      )
    }
    for j in 0..<i {
      if lessons[j].slug == lesson.slug {
        fail(
          "\{lessons[j].dir} and \{lesson.dir}: both lessons have the slug \"\{lesson.slug}\"",
        )
      }
    }
  }
  { lessons, }
}

///|
fn parse_number(dir : String) -> Int32 raise {
  let chars = dir.to_array()
  if chars.length() < 4 ||
    !(chars[0].is_ascii_digit() && chars[1].is_ascii_digit()) ||
    chars[2] != '-' {
    fail("\{dir}: I expected a folder name like \"01-slug\"")
  }
  let a = chars[0].to_int() - '0'.to_int()
  let b = chars[1].to_int() - '0'.to_int()
  a * 10 + b
}

///|
fn read_lesson(
  root : String,
  dir : String,
  repo : String,
) -> @model.Lesson raise {
  let base = "\{root}/\{dir}"
  let number = parse_number(dir)
  let meta = read_json("\{base}/lesson.json")
  check_keys(meta, lesson_keys, "\{dir}/lesson.json")
  let slug = string_field(meta, "slug", dir)
  // A link to a lesson text resolves to its page by the folder name alone.
  if dir != @model.lesson_dir(number, slug) {
    fail(
      "\{dir}: I expected the folder name \"\{@model.lesson_dir(number, slug)}\", because the slug is \"\{slug}\"",
    )
  }
  let title = string_field(meta, "title", dir)
  let section = string_field(meta, "section", dir)
  let spec = string_field(meta, "spec", dir)
  if !spec.has_prefix(@model.spec_url_prefix) &&
    @content.doc_route(spec) is None {
    fail(
      "\{dir}: \"spec\" must be a smithy.io URL or the repository path of a docs page, not \"\{spec}\"",
    )
  }
  let output = match optional_string_field(meta, "output", dir) {
    None => None
    Some(name) =>
      Some(
        @json.from_json(Json::string(name)) catch {
          _ => fail("\{dir}: \"output\" has the unknown value \"\{name}\"")
        },
      )
  }
  let engine = read_engine(meta, dir, output is Some(_))
  let extension = read_extension(meta, dir, engine)
  let selector = optional_string_field(meta, "selector", dir)
  if selector is Some(_) && !(output is Some(@samples.Output::Selector)) {
    fail("\{dir}: \"selector\" is for the output Selector only")
  }
  let raw = io("\{base}/lesson.md", () => {
    @fs.read_file_to_string("\{base}/lesson.md")
  })
  let first = raw.split("\n").next().unwrap_or("")
  if first.trim_end(chars="\r").to_owned() != "# \{title}" {
    fail(
      "\{dir}/lesson.md: I expected the first line \"# \{title}\", but found \"\{first}\"",
    )
  }
  let text = match check_hand_written(raw) {
    Ok(_) => text_of(dir, repo, raw)
    Err(e) => fail("\{dir}/lesson.md: \{e}")
  }
  if engine is Static {
    if @fs.path_exists("\{base}/files") || @fs.path_exists("\{base}/cases") {
      fail(
        "\{dir}: a static lesson has no files/ and no cases/: its blocks come from include blocks",
      )
    }
    return {
      dir,
      number,
      slug,
      title,
      section,
      engine,
      extension,
      output,
      selector,
      spec,
      text,
      files: [],
      cases: [],
    }
  }
  let data = engine.data_files()
  let files = read_files("\{base}/files", "\{dir}/files", data)
  if files.is_empty() {
    fail("\{dir}: I found no starting file in files/")
  }
  for name in data {
    if !files.any(f => f.name == name) {
      fail(
        "\{dir}: the value file \"\{name}\" is not a starting file in files/",
      )
    }
  }
  let cases = read_cases(dir, "\{base}/cases", output is Some(_), engine)
  {
    dir,
    number,
    slug,
    title,
    section,
    engine,
    extension,
    output,
    selector,
    spec,
    text,
    files,
    cases,
  }
}

///|
fn text_of(dir : String, repo : String, raw : String) -> String raise {
  let text = match
    @markdown.expand_includes(raw, inc => resolve_include(repo, inc)) {
    Ok(text) => text
    Err(e) => fail("\{dir}/lesson.md: \{e}")
  }
  if check_expanded(text) is Err(e) {
    fail("\{dir}/lesson.md: \{e}")
  }
  text
}

///|
/// Whether `lesson.json` has the flag `key` set to `true`. `false` for a flag
/// that is absent or `false`.
fn flag_field(meta : Json, key : String, where_ : String) -> Bool raise {
  guard meta is Object(m) else { fail("\{where_}: I expected a JSON object") }
  match m.get(key) {
    None | Some(False) => false
    Some(True) => true
    Some(_) => fail("\{where_}: \"\{key}\" must be true or false")
  }
}

///|
/// The `extension` flag. Only a static lesson sets it: the other lessons with
/// an engine of ours always say it.
fn read_extension(
  meta : Json,
  dir : String,
  engine : @model.Engine,
) -> Bool raise {
  let where_ = "\{dir}/lesson.json"
  let extension = flag_field(meta, "extension", where_)
  if extension && !(engine is Static) {
    fail("\{where_}: \"extension\" is for a static lesson")
  }
  extension
}

///|
/// The engine of a lesson: at most one of `output`, `value`, or `static`. A
/// lesson with none of them validates its model.
fn read_engine(
  meta : Json,
  dir : String,
  has_output : Bool,
) -> @model.Engine raise {
  guard meta is Object(m) else {
    fail("\{dir}/lesson.json: I expected a JSON object")
  }
  let where_ = "\{dir}/lesson.json"
  if flag_field(meta, "static", where_) {
    for key in ["output", "selector", "value", "message", "diff", "transcript"] {
      if m.contains(key) {
        fail(
          "\{where_}: a static lesson cannot have \"\{key}\": it has no editor and no output",
        )
      }
    }
    return Static
  }
  let value = m.get("value")
  if has_output && value is Some(_) {
    fail("\{where_}: I expected at most one of output, value, message, diff")
  }
  guard value is Some(setup) else { return Model }
  check_keys(setup, value_keys, "\{where_} \"value\"")
  let file = string_field(setup, "file", "\{where_} \"value\"")
  if !file.has_suffix(".json") {
    fail("\{where_}: the value file \"\{file}\" must end in .json")
  }
  let shape = string_field(setup, "shape", "\{where_} \"value\"")
  let unknown_members : @samples.UnknownMembers = match
    optional_string_field(setup, "unknown_members", where_) {
    None | Some("reject") => Reject
    Some("ignore") => Ignore
    Some(other) =>
      fail(
        "\{where_}: \"unknown_members\" must be \"reject\" or \"ignore\", not \"\{other}\"",
      )
  }
  let member_names : @samples.MemberNames = match
    optional_string_field(setup, "member_names", where_) {
    None | Some("smithy") => Smithy
    Some("json") => JsonName
    Some(other) =>
      fail(
        "\{where_}: \"member_names\" must be \"smithy\" or \"json\", not \"\{other}\"",
      )
  }
  Value({ file, shape, options: { unknown_members, member_names, }, })
}

///|
/// The files directly in the folder `path`. `where_` names the folder in an
/// error. The playground core reads every model file as IDL, so a file name
/// must end in `.smithy`. `data` are the names of the data files of the
/// engine; they are the only other files.
fn read_files(
  path : String,
  where_ : String,
  data : Array[String],
) -> Array[@model.LessonFile] raise {
  let files : Array[@model.LessonFile] = []
  if !@fs.path_exists(path) {
    return files
  }
  for name in list_dir(path) {
    let file = "\{path}/\{name}"
    if is_dir(file) {
      fail(
        "\{where_}/\{name}: I found a folder in the files of a lesson. Put each file directly in \{where_}",
      )
    }
    if !name.has_suffix(".smithy") && !data.contains(name) {
      fail(
        "\{where_}/\{name}: the name of a lesson file must end in .smithy, because the playground core reads every file as IDL",
      )
    }
    files.push({ name, text: io(file, () => @fs.read_file_to_string(file)), })
  }
  files
}

///|
fn read_cases(
  dir : String,
  path : String,
  has_output : Bool,
  engine : @model.Engine,
) -> Array[@model.Case] raise {
  if !@fs.path_exists("\{path}/start") {
    fail("\{dir}: I found no cases/start folder")
  }
  let names = list_dir(path).filter(n => n != "start" && is_dir("\{path}/\{n}"))
  let cases = [read_case(dir, path, "start", has_output, engine)]
  for name in names {
    cases.push(read_case(dir, path, name, has_output, engine))
  }
  cases
}

///|
fn read_case(
  dir : String,
  path : String,
  name : String,
  has_output : Bool,
  engine : @model.Engine,
) -> @model.Case raise {
  let base = "\{path}/\{name}"
  let expect_path = "\{base}/expect.json"
  if !@fs.path_exists(expect_path) {
    fail("\{dir}/cases/\{name}: I found no expect.json")
  }
  let json = read_json(expect_path)
  check_keys(json, expect_keys, "\{dir}/cases/\{name}/expect.json")
  let events = string_array_field(json, "events", "\{dir}/cases/\{name}").map(event => {
    match @model.EventKey::parse(event) {
      Some(key) => key
      None =>
        fail(
          "\{dir}/cases/\{name}: the event \"\{event}\" must have the form id|SEVERITY|shape, and SEVERITY must be WARNING, DANGER or ERROR",
        )
    }
  })
  let output_contains = match json {
    Object(m) if m.contains("output_contains") =>
      string_array_field(json, "output_contains", "\{dir}/cases/\{name}")
    _ => []
  }
  if output_contains.contains("") {
    fail(
      "\{dir}/cases/\{name}: a string of \"output_contains\" is empty, and an empty string matches every output",
    )
  }
  let where_ = "\{dir}/cases/\{name}"
  let findings = optional_keys_field(json, "findings", where_)
  let diff = optional_keys_field(json, "diff", where_)
  match engine {
    Value(_) =>
      if !(json is Object(m) && m.contains("findings")) {
        fail("\{where_}: a value lesson needs \"findings\" in expect.json")
      }
    Static => fail("\{where_}: a static lesson has no cases")
    Model =>
      if !findings.is_empty() || has_key(json, "findings") {
        fail("\{where_}: \"findings\" is for a value or message lesson")
      }
  }
  if !diff.is_empty() || has_key(json, "diff") {
    fail("\{where_}: \"diff\" is for a diff lesson")
  }
  for key in findings {
    if !@model.is_finding_key(key) {
      fail(
        "\{where_}: the finding \"\{key}\" must have the form code|error|pointer|shape or code|stopped|source",
      )
    }
  }
  let blocked = optional_string_field(json, "blocked", where_)
  if blocked is Some(_) {
    if !output_contains.is_empty() {
      fail(
        "\{where_}: \"blocked\" and \"output_contains\" cannot be together, because a blocked output has no text",
      )
    }
    if !has_output {
      fail("\{where_}: \"blocked\" needs a lesson output")
    }
    if events.any(e => e.severity.blocks_output()) {
      fail(
        "\{where_}: \"blocked\" cannot have an ERROR or DANGER event, because the block reason would be the model errors",
      )
    }
  }
  {
    name,
    files: read_files("\{base}/files", "\{where_}/files", engine.data_files()),
    expect: { events, output_contains, blocked, findings, diff, },
  }
}

///|
/// The keys of `lesson.json`.
let lesson_keys : Array[String] = [
  "slug", "title", "section", "spec", "output", "selector", "value", "static", "extension",
]

///|
/// The keys of `value` in `lesson.json`.
let value_keys : Array[String] = [
  "file", "shape", "unknown_members", "member_names",
]

///|
/// The keys of `expect.json`.
let expect_keys : Array[String] = [
  "events", "output_contains", "blocked", "findings", "diff",
]

///|
/// Fail on a key that is not in `keys`. A misspelt key would otherwise drop
/// what it holds without a message.
fn check_keys(json : Json, keys : Array[String], where_ : String) -> Unit raise {
  guard json is Object(m) else { fail("\{where_}: I expected a JSON object") }
  for key, _ in m {
    if !keys.contains(key) {
      fail(
        "\{where_}: I do not know the key \"\{key}\". The keys are \{keys.join(", ")}",
      )
    }
  }
}

///|
fn read_json(path : String) -> Json raise {
  let text = io(path, () => @fs.read_file_to_string(path))
  @json.parse(text) catch {
    _ => fail("\{path}: it is not valid JSON")
  }
}

///|
fn optional_string_field(
  json : Json,
  key : String,
  where_ : String,
) -> String? raise {
  match json {
    Object(m) =>
      match m.get(key) {
        None => None
        Some(String(s)) => Some(s)
        Some(_) => fail("\{where_}: \"\{key}\" must be a string")
      }
    _ => fail("\{where_}: I expected a JSON object")
  }
}

///|
fn string_field(json : Json, key : String, where_ : String) -> String raise {
  match optional_string_field(json, key, where_) {
    Some(s) => s
    None => fail("\{where_}: lesson.json has no \"\{key}\"")
  }
}

///|
fn string_array_field(
  json : Json,
  key : String,
  where_ : String,
) -> Array[String] raise {
  match json {
    Object(m) =>
      match m.get(key) {
        Some(Array(items)) =>
          items.map(item => {
            match item {
              String(s) => s
              _ => fail("\{where_}: every item of \"\{key}\" must be a string")
            }
          })
        _ =>
          fail("\{where_}: expect.json needs \"\{key}\" as an array of strings")
      }
    _ => fail("\{where_}: I expected a JSON object")
  }
}

///|
fn has_key(json : Json, key : String) -> Bool {
  json is Object(m) && m.contains(key)
}

///|
/// The strings of an optional array field; empty when the field is missing.
fn optional_keys_field(
  json : Json,
  key : String,
  where_ : String,
) -> Array[String] raise {
  if has_key(json, key) {
    string_array_field(json, key, where_)
  } else {
    []
  }
}

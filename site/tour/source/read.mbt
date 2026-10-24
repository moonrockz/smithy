///|
/// Read the lessons folder. The error names the folder and the problem.
pub fn read_tour(root : String) -> Result[@model.Tour, String] {
  Ok(read_root(root)) catch {
    Failure(msg) => Err(msg)
    e => Err("\{root}: \{e}")
  }
}

///|
fn io(path : String, f : () -> String raise @fs.IOError) -> String raise {
  f() catch {
    _ => fail("\{path}: I cannot read it")
  }
}

///|
fn list_dir(path : String) -> Array[String] raise {
  let names = @fs.read_dir(path) catch {
    _ => fail("\{path}: I cannot list the folder")
  }
  let sorted = names.to_owned()
  sorted.sort_by(@model.compare_code_units)
  sorted
}

///|
fn is_dir(path : String) -> Bool raise {
  @fs.is_dir(path) catch {
    _ => fail("\{path}: I cannot read it")
  }
}

///|
fn read_root(root : String) -> @model.Tour raise {
  let lessons : Array[@model.Lesson] = []
  for name in list_dir(root) {
    let path = "\{root}/\{name}"
    if !is_dir(path) {
      continue
    }
    lessons.push(read_lesson(root, name))
  }
  if lessons.is_empty() {
    fail("\{root}: I found no lesson folder")
  }
  for i, lesson in lessons {
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
fn read_lesson(root : String, dir : String) -> @model.Lesson raise {
  let base = "\{root}/\{dir}"
  let number = parse_number(dir)
  let meta = read_json("\{base}/lesson.json")
  let slug = string_field(meta, "slug", dir)
  let title = string_field(meta, "title", dir)
  let section = string_field(meta, "section", dir)
  let spec = string_field(meta, "spec", dir)
  let output = match optional_string_field(meta, "output", dir) {
    None => None
    Some(name) =>
      Some(
        @json.from_json(Json::string(name)) catch {
          _ => fail("\{dir}: \"output\" has the unknown value \"\{name}\"")
        },
      )
  }
  let selector = optional_string_field(meta, "selector", dir)
  let text = io("\{base}/lesson.md", () => {
    @fs.read_file_to_string("\{base}/lesson.md")
  })
  let first = text.split("\n").next().unwrap_or("")
  if first.trim_end(chars="\r").to_owned() != "# \{title}" {
    fail(
      "\{dir}/lesson.md: I expected the first line \"# \{title}\", but found \"\{first}\"",
    )
  }
  let files = read_files("\{base}/files")
  if files.is_empty() {
    fail("\{dir}: I found no starting file in files/")
  }
  let cases = read_cases(dir, "\{base}/cases")
  {
    dir,
    number,
    slug,
    title,
    section,
    output,
    selector,
    spec,
    text,
    files,
    cases,
  }
}

///|
fn read_files(path : String) -> Array[@model.LessonFile] raise {
  let files : Array[@model.LessonFile] = []
  if !@fs.path_exists(path) {
    return files
  }
  for name in list_dir(path) {
    let file = "\{path}/\{name}"
    if is_dir(file) {
      continue
    }
    files.push({ name, text: io(file, () => @fs.read_file_to_string(file)), })
  }
  files
}

///|
fn read_cases(dir : String, path : String) -> Array[@model.Case] raise {
  if !@fs.path_exists("\{path}/start") {
    fail("\{dir}: I found no cases/start folder")
  }
  let names = list_dir(path).filter(n => n != "start" && is_dir("\{path}/\{n}"))
  let cases = [read_case(dir, path, "start")]
  for name in names {
    cases.push(read_case(dir, path, name))
  }
  cases
}

///|
fn read_case(dir : String, path : String, name : String) -> @model.Case raise {
  let base = "\{path}/\{name}"
  let expect_path = "\{base}/expect.json"
  if !@fs.path_exists(expect_path) {
    fail("\{dir}/cases/\{name}: I found no expect.json")
  }
  let json = read_json(expect_path)
  let events = string_array_field(json, "events", "\{dir}/cases/\{name}")
  for event in events {
    let parts = event.split("|").to_array()
    if parts.length() != 3 ||
      !(parts[1] == "WARNING" || parts[1] == "DANGER" || parts[1] == "ERROR") {
      fail(
        "\{dir}/cases/\{name}: the event \"\{event}\" must have the form id|SEVERITY|shape, and SEVERITY must be WARNING, DANGER or ERROR",
      )
    }
  }
  let output_contains = match json {
    Object(m) if m.contains("output_contains") =>
      string_array_field(json, "output_contains", "\{dir}/cases/\{name}")
    _ => []
  }
  {
    name,
    files: read_files("\{base}/files"),
    expect: { events, output_contains, },
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

///|
fn audit_validation_files(dir : String) -> Array[String] raise {
  let files : Array[String] = []
  for name in @fs.read_dir(dir) {
    let path = dir + "/" + name
    if @fs.is_dir(path) {
      files.append(audit_validation_files(path))
    } else if path.has_suffix(".errors") {
      files.push(path)
    }
  }
  files.sort()
  files
}

///|
test "complete validation corpus matches reference event identities" {
  let report : Array[Json] = []
  let mut passed = 0
  let mut total = 0
  for errors_file in audit_validation_files("tck/validation") {
    let stem = errors_file[:errors_file.length() - 7].to_owned()
    let source_file = if @fs.path_exists(stem + ".smithy") {
      stem + ".smithy"
    } else if @fs.path_exists(stem + ".json") {
      stem + ".json"
    } else {
      continue
    }
    let reference = @json.parse(
      @fs.read_file_to_string("tck/validation-events.json"),
    )
    let key = source_file[15:].to_owned()
    let expected : Array[String] = match reference {
      Object(values) =>
        match values.get(key) {
          Some(Array(events)) =>
            events.map(e => {
              match e {
                String(key) => key
                _ => abort("Invalid reference event")
              }
            })
          _ => abort("Missing reference model: " + key)
        }
      _ => abort("Invalid reference validation manifest")
    }
    expected.sort()
    let text = @fs.read_file_to_string(source_file)
    let loader = @smithy.Loader::new()
    if source_file.has_suffix(".smithy") {
      ignore(loader.add_idl(source_file, text))
    } else {
      ignore(loader.add_json(source_file, text))
    }
    let result = loader.assemble()
    let actual = result
      .validation_events()
      .map(e => {
        e.id +
        "|" +
        e.severity +
        "|" +
        e.shape.map(id => id.to_string()).unwrap_or("-")
      })

    actual.sort()
    total += 1
    if actual == expected {
      passed += 1
    } else {
      report.push(
        Json::object({
          "file": Json::string(source_file),
          "expected": Json::array(expected.map(Json::string)),
          "actual": Json::array(actual.map(Json::string)),
        }),
      )
    }
  }
  assert_eq(total, 277)
  assert_eq(
    passed,
    total,
    msg="validation parity: " +
      passed.to_string() +
      "/" +
      total.to_string() +
      "\n" +
      Json::array(report).stringify(indent=2),
  )
}

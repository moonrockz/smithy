///|
fn build_case_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn build_case_strings(value : Json, key : String) -> Array[String] {
  match build_case_field(value, key) {
    Some(Array(values)) =>
      values.map(v => {
        match v {
          String(s) => s
          _ => abort("Expected string in " + key)
        }
      })
    _ => []
  }
}

///|
fn build_case_string(value : Json, key : String) -> String {
  match build_case_field(value, key) {
    Some(String(s)) => s
    _ => abort("Missing " + key)
  }
}

///|
fn build_case_parent(path : String) -> String {
  let pieces = path.split("/").map(p => p.to_owned()).to_array()
  ignore(pieces.pop())
  pieces.join("/")
}

///|
fn build_case_config(value : Json) -> @build.BuildConfig raise {
  let environment : Map[String, String] = Map([])
  if build_case_field(value, "environment") is Some(Object(entries)) {
    for key, entry in entries {
      guard entry is String(text) else {
        abort("Expected string environment value")
      }
      environment[key] = text
    }
  }
  let mut config = @build.BuildConfig::parse("{\"version\":\"2.0\"}")
  let definitions : Array[(@build.BuildConfig, String)] = []
  for file in build_case_strings(value, "configs") {
    let path = "tck/build/" + file
    definitions.push(
      (
        @build.BuildConfig::parse(@fs.read_file_to_string(path), environment~),
        build_case_parent(path),
      ),
    )
  }
  if build_case_field(value, "config") is Some(definition) {
    definitions.push(
      (
        @build.BuildConfig::parse(definition.stringify(), environment~),
        "tck/build",
      ),
    )
  }
  for (definition, base) in definitions {
    let projections = config.projections.copy()
    for projection in definition.projections {
      let projection = {
        ..projection,
        imports: projection.imports.map(p => {
          @build.BuildInput::from_path(base + "/" + p.location().to_string())
        }),
      }
      let mut replaced = false
      for i = 0; i < projections.length(); i = i + 1 {
        if projections[i].name == projection.name {
          projections[i] = projection
          replaced = true
          break
        }
      }
      if !replaced {
        projections.push(projection)
      }
    }
    let plugins = config.plugins.copy()
    for name, settings in definition.plugins {
      plugins[name] = settings
    }
    let sources = config.sources.copy()
    sources.append(
      definition.sources.map(p => {
        @build.BuildInput::from_path(base + "/" + p.location().to_string())
      }),
    )
    let imports = config.imports.copy()
    imports.append(
      definition.imports.map(p => {
        @build.BuildInput::from_path(base + "/" + p.location().to_string())
      }),
    )
    config = { ..definition, sources, imports, projections, plugins, }
  }
  let sources = config.sources.copy()
  sources.append(
    build_case_strings(value, "sources").map(p => {
      @build.BuildInput::from_path("tck/build/" + p)
    }),
  )
  { ..config, sources, }
}

///|
fn build_case_add_input(loader : @smithy.Loader, path : String) -> Unit raise {
  if @fs.is_dir(path) {
    for name in @fs.read_dir(path) {
      build_case_add_input(loader, path + "/" + name)
    }
  } else if path.has_suffix(".jar") {
    for name, text in @build.archive_models(@fs.read_file_to_bytes(path), path) {
      let origin = path + "!/META-INF/smithy/" + name
      if name.has_suffix(".smithy") {
        ignore(loader.add_idl(origin, text))
      } else {
        ignore(loader.add_json(origin, text))
      }
    }
  } else if path.has_suffix(".smithy") {
    ignore(loader.add_idl(path, @fs.read_file_to_string(path)))
  } else if path.has_suffix(".json") {
    ignore(loader.add_json(path, @fs.read_file_to_string(path)))
  }
}

///|
fn build_case_input(path : String) -> @smithy.ModelInput raise {
  let text = @fs.read_file_to_string(path)
  if path.has_suffix(".smithy") {
    @smithy.ModelInput::Idl(name=path, text~)
  } else {
    @smithy.ModelInput::Json(name=path, text~)
  }
}

///|
fn build_case_result(value : Json) -> Json {
  let id = build_case_string(value, "id")
  let artifacts : Map[String, Json] = Map([])
  let failure_events : Map[String, Json] = Map([])
  let failed : Set[String] = Set([])
  let mut stage = "$config"
  try {
    let mode = build_case_string(value, "mode")
    let config = build_case_config(value)
    stage = "$model"
    let loader = @smithy.Loader::new()
    let loaded : Set[String] = Set([])
    let paths = build_case_strings(value, "models").map(p => "tck/build/" + p)
    paths.append(config.sources.map(input => input.location().to_string()))
    paths.append(config.imports.map(input => input.location().to_string()))
    for path in paths {
      if loaded.contains(path) {
        continue
      }
      loaded.add(path)
      build_case_add_input(loader, path)
    }
    if build_case_field(value, "model") is Some(model) {
      ignore(loader.add_json(id + ".json", model.stringify()))
    }
    let result = loader.assemble()
    guard result.model is Some(model) else {
      let events = result
        .validation_events()
        .filter(e => ["ERROR", "DANGER"].contains(e.severity))
        .map(e => {
          e.id +
          "|" +
          e.severity +
          "|" +
          e.shape.map(id => id.to_string()).unwrap_or("-")
        })
      events.sort_by((a, b) => a.lexical_compare(b))
      return Json::object({
        "artifacts": Json::object(Map([])),
        "failureEvents": Json::object({
          "$model": Json::array(events.map(Json::string)),
        }),
        "failedProjections": Json::array([Json::string("$model")]),
      })
    }
    if mode == "transform" {
      stage = "transform"
      let mut projected = model
      let transforms = match build_case_field(value, "transforms") {
        Some(Array(values)) => values
        _ => []
      }
      for transform in transforms {
        projected = @build.apply_transform(projected, {
          name: build_case_string(transform, "name"),
          args: build_case_field(transform, "args").unwrap_or(
            Json::object(Map([])),
          ),
        })
      }
      artifacts["transform/model/model.json"] = @syntax.encode_json_ast(
        projected.to_json_ast(preserve_mixins=true),
      )
    } else {
      stage = "$build"
      let runner = @build.BuildRunner::new(config)
      for input in config.sources {
        let path = input.location().to_string()
        if path.has_suffix(".jar") {
          let filename = path.split("/").to_array().last().unwrap().to_owned()
          let prefix = filename[:filename.length() - 4].to_owned()
          for
            name, text in @build.archive_models(
              @fs.read_file_to_bytes(path),
              path,
            ) {
            ignore(
              runner.add_source(
                prefix + "/" + name,
                text,
                source_file=Some(path + "!/META-INF/smithy/" + name),
              ),
            )
          }
        } else {
          let text = @fs.read_file_to_string(path)
          let name = path.split("/").to_array().last().unwrap().to_owned()
          ignore(runner.add_source(name, text, source_file=Some(path)))
        }
      }
      for projection in config.projections {
        for input in projection.imports {
          let path = input.location().to_string()
          ignore(
            runner.add_projection_import(
              projection.name,
              build_case_input(path),
            ),
          )
        }
      }
      let result = runner.run_result(model)
      for path, text in result.artifacts {
        if path.has_suffix("/model.json") {
          artifacts[path] = @json.parse(text)
        }
        if path.has_suffix("/build-info/smithy-build-info.json") {
          let events : Array[String] = []
          if build_case_field(@json.parse(text), "validationEvents")
            is Some(Array(entries)) {
            for event in entries {
              let severity = build_case_string(event, "severity")
              if ["ERROR", "DANGER"].contains(severity) {
                let shape = match build_case_field(event, "shapeId") {
                  Some(String(id)) => id
                  _ => "-"
                }
                events.push(
                  build_case_string(event, "id") + "|" + severity + "|" + shape,
                )
              }
            }
          }
          if !events.is_empty() {
            events.sort_by((a, b) => a.lexical_compare(b))
            failure_events[path.split("/").to_array()[0].to_owned()] = Json::array(
              events.map(Json::string),
            )
          }
        }
      }
      for error in result.errors {
        if error.has_prefix("Projection `") && error[12:].find("`") is Some(end) {
          failed.add(error[12:12 + end].to_owned())
        } else if error.has_prefix("Model validation failed:") {
          failed.add("$model")
        } else {
          failed.add("$build")
        }
      }
    }
  } catch {
    _ => failed.add(stage)
  }
  let failures = failed.iter().to_array()
  failures.sort_by((a, b) => a.lexical_compare(b))
  Json::object({
    "artifacts": Json::object(artifacts),
    "failureEvents": Json::object(failure_events),
    "failedProjections": Json::array(failures.map(Json::string)),
  })
}

///|
fn build_corpus_files(path : String) -> Array[String] raise {
  let files : Array[String] = []
  for name in @fs.read_dir(path) {
    let file = path + "/" + name
    if @fs.is_dir(file) {
      files.append(build_corpus_files(file))
    } else {
      files.push(file)
    }
  }
  files
}

///|
test "build corpus compares every complete model artifact and failure outcome" {
  let manifest = @json.parse(@fs.read_file_to_string("tck/build-cases.json"))
  let golden = @json.parse(@fs.read_file_to_string("tck/build-models.json"))
  guard build_case_field(manifest, "cases") is Some(Array(cases)) else {
    fail("Missing build cases")
  }
  let ids = cases.map(case => build_case_string(case, "id"))
  ids.sort()
  let golden_ids = match golden {
    Object(entries) => entries.keys().to_array()
    _ => []
  }
  golden_ids.sort()
  assert_eq(
    ids,
    golden_ids,
    msg="Build goldens must cover exactly the manifest cases",
  )
  let failures : Array[String] = []
  let report : Array[Json] = []
  for case in cases {
    let id = build_case_string(case, "id")
    let expected = build_case_field(golden, id).unwrap_or(Json::null())
    let actual = build_case_result(case)
    if actual != expected {
      failures.push(id)
      report.push(
        Json::object({
          "case": Json::string(id),
          "actual": actual,
          "expected": expected,
        }),
      )
    }
  }
  if @fs.path_exists("../.dev/out") {
    @fs.write_string_to_file(
      "../.dev/out/build-projection-parity.json",
      Json::array(report).stringify(indent=2),
    )
  }
  assert_eq(failures, [], msg=failures.join("\n\n"))
}

///|
test "build case manifest classifies every vendored resource" {
  let manifest = @json.parse(@fs.read_file_to_string("tck/build-cases.json"))
  assert_eq(
    @fs.read_file_to_string("tck/build/REFERENCE_SHA").trim().to_owned(),
    build_case_string(manifest, "referenceSha"),
  )
  let covered : Set[String] = Set([])
  let transforms : Set[String] = Set([])
  for file in build_case_strings(manifest, "supportFiles") {
    covered.add(file)
  }
  if build_case_field(manifest, "exclusions") is Some(Array(exclusions)) {
    for exclusion in exclusions {
      assert_false(build_case_string(exclusion, "reason").is_empty())
      covered.add(build_case_string(exclusion, "file"))
    }
  }
  if build_case_field(manifest, "cases") is Some(Array(cases)) {
    let ids : Set[String] = Set([])
    for case in cases {
      let id = build_case_string(case, "id")
      assert_false(ids.contains(id), msg="Duplicate build case " + id)
      ids.add(id)
      if build_case_field(case, "transforms") is Some(Array(entries)) {
        for transform in entries {
          transforms.add(build_case_string(transform, "name"))
        }
      }
      try {
        for projection in build_case_config(case).projections {
          for transform in projection.transforms {
            transforms.add(transform.name)
          }
        }
      } catch {
        _ => ()
      }
      for key in ["models", "configs", "sources"] {
        for file in build_case_strings(case, key) {
          covered.add(file)
        }
      }
      if build_case_field(case, "expectedModel") is Some(String(file)) {
        covered.add(file)
      }
    }
  }
  for name in build_case_strings(manifest, "transforms") {
    assert_true(
      transforms.contains(name),
      msg="No corpus case exercises reference transform " + name,
    )
  }
  for path in build_corpus_files("tck/build") {
    assert_true(
      covered.contains(path[10:].to_owned()),
      msg="Unclassified build fixture " + path,
    )
  }
  for file in covered {
    assert_true(
      @fs.path_exists("tck/build/" + file),
      msg="Missing build fixture " + file,
    )
  }
}

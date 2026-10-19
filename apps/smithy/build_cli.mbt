///|
fn build_path(base : String, child : String) -> String {
  let child_path : @path.Path = child
  if child_path.is_absolute() {
    return child_path.normalize().to_string()
  }
  let base_path : @path.Path = base
  base_path.join(child_path).to_string()
}

///|
fn build_mkdir(path : String) -> Unit raise {
  if @fs.path_exists(path) {
    return
  }
  let current : @path.Path = path
  let parent = current.dirname().to_string()
  if parent != path && parent != "." && !@fs.path_exists(parent) {
    build_mkdir(parent)
  }
  @fs.create_dir(path)
}

///|
fn build_remove_tree(path : String) -> Unit raise {
  if !@fs.path_exists(path) {
    return
  }
  for name in @fs.read_dir(path) {
    let child = build_path(path, name)
    if @fs.is_dir(child) {
      build_remove_tree(child)
    } else {
      @fs.remove_file(child)
    }
  }
  @fs.remove_dir(path)
}

///|
fn build_add_files(
  loader : @smithy.Loader,
  runner : @build.BuildRunner,
  path : String,
  source_root : String?,
) -> Unit raise {
  if @fs.is_dir(path) {
    for name in @fs.read_dir(path) {
      build_add_files(
        loader,
        runner,
        build_path(path, name),
        Some(source_root.unwrap_or(path)),
      )
    }
  } else if path.has_suffix(".smithy") {
    let text = @fs.read_file_to_string(path)
    ignore(loader.add_idl(path, text))
    build_record_source(runner, path, source_root, text)
  } else if path.has_suffix(".json") {
    let text = @fs.read_file_to_string(path)
    ignore(loader.add_json(path, text))
    build_record_source(runner, path, source_root, text)
  }
}

///|
fn build_record_source(
  runner : @build.BuildRunner,
  path : String,
  source_root : String?,
  text : String,
) -> Unit {
  if source_root is Some(root) {
    let current : @path.Path = path
    let root : @path.Path = root
    ignore(runner.add_source(current.relative(base=root).to_string(), text))
  }
}

///|
fn build_setting_string(
  settings : Json,
  key : String,
  default : String,
) -> String raise @build.BuildError {
  guard settings is Object(fields) else {
    raise @build.InvalidBuildConfig(
      "JSON Schema plugin settings must be an object",
    )
  }
  match fields.get(key) {
    None => default
    Some(String(value)) => value
    _ =>
      raise @build.InvalidBuildConfig(
        "JSON Schema setting `" + key + "` must be a string",
      )
  }
}

///|
fn build_setting_bool(
  settings : Json,
  key : String,
) -> Bool raise @build.BuildError {
  guard settings is Object(fields) else {
    raise @build.InvalidBuildConfig(
      "JSON Schema plugin settings must be an object",
    )
  }
  match fields.get(key) {
    None | Some(False) => false
    Some(True) => true
    _ =>
      raise @build.InvalidBuildConfig(
        "JSON Schema setting `" + key + "` must be a boolean",
      )
  }
}

///|
fn json_schema_plugin(
  model : @smithy.Model,
  settings : Json,
) -> Map[String, String] raise @build.BuildError {
  let map_strategy = build_setting_string(
    settings, "mapStrategy", "propertyNames",
  )
  let union_strategy = build_setting_string(settings, "unionStrategy", "oneOf")
  let enum_strategy = build_setting_string(settings, "enumStrategy", "enum")
  if !["propertyNames", "patternProperties"].contains(map_strategy) ||
    !["oneOf", "object", "structure"].contains(union_strategy) ||
    !["enum", "oneOf"].contains(enum_strategy) {
    raise @build.InvalidBuildConfig("Invalid JSON Schema strategy")
  }
  let extensions = match settings {
    Object(fields) =>
      fields.get("schemaDocumentExtensions").unwrap_or(Json::object(Map([])))
    _ => Json::object(Map([]))
  }
  guard extensions is Object(_) else {
    raise @build.InvalidBuildConfig(
      "schemaDocumentExtensions must be an object",
    )
  }
  let schema_version = build_setting_string(
    settings, "jsonSchemaVersion", "draft07",
  )
  if schema_version != "draft07" && schema_version != "draft2020-12" {
    raise @build.InvalidBuildConfig(
      "Unsupported JSON Schema version `" + schema_version + "`",
    )
  }
  let default_pointer = if schema_version == "draft2020-12" {
    "#/$defs"
  } else {
    "#/definitions"
  }
  let config = @jsonschema.Config::new(
    map_strategy~,
    union_strategy~,
    enum_strategy~,
    use_json_name=build_setting_bool(settings, "useJsonName"),
    default_timestamp_format=build_setting_string(
      settings, "defaultTimestampFormat", "date-time",
    ),
    support_non_numeric_floats=build_setting_bool(
      settings, "supportNonNumericFloats",
    ),
    schema_document_extensions=extensions,
    definition_pointer=build_setting_string(
      settings, "definitionPointer", default_pointer,
    ),
    add_reference_descriptions=build_setting_bool(
      settings, "addReferenceDescriptions",
    ),
    disable_default_values=build_setting_bool(settings, "disableDefaultValues"),
    disable_int_enums=build_setting_bool(settings, "disableIntEnums"),
    use_integer_type=build_setting_bool(settings, "useIntegerType"),
  )
  let service = build_setting_string(settings, "service", "")
  let document = @jsonschema.convert(model, service~, config~) catch {
    error =>
      raise @build.InvalidBuildConfig(
        "JSON Schema conversion failed: " + error.to_string(),
      )
  }
  let files : Map[String, String] = Map([])
  files["schema.json"] = document.stringify(indent=4) + "\n"
  files
}

///|
fn run_build(config_path : String, clean : Bool) -> Int32 raise {
  let config = @build.BuildConfig::parse(@fs.read_file_to_string(config_path))
  let config_file : @path.Path = config_path
  let base = config_file.dirname().to_string()
  let output = build_path(base, config.output_directory)
  let normalized : @path.Path = output
  let output = normalized.resolve().to_string()
  let cwd : @path.Path = "."
  let output_path : @path.Path = output
  if output == cwd.resolve().to_string() ||
    output == base ||
    output_path.dirname().to_string() == output {
    raise CliError("build output directory must be a dedicated directory", 2)
  }
  if clean {
    build_remove_tree(output)
    return 0
  }
  let loader = @smithy.Loader::new()
  let runner = @build.BuildRunner::new(config).register_plugin(
    "jsonSchema", json_schema_plugin,
  )
  for name in config.sources {
    let path = build_path(base, name)
    if @fs.is_dir(path) {
      build_add_files(loader, runner, path, Some(path))
    } else {
      let file : @path.Path = path
      build_add_files(loader, runner, path, Some(file.dirname().to_string()))
    }
  }
  for name in config.imports {
    build_add_files(loader, runner, build_path(base, name), None)
  }
  let loaded = loader.assemble()
  for diagnostic in loaded.diagnostics {
    eprintln(diagnostic.message)
  }
  guard loaded.model is Some(model) else { return 1 }
  let artifacts = runner.run(model)
  for relative, content in artifacts {
    let path = build_path(output, relative)
    let file : @path.Path = path
    build_mkdir(file.dirname().to_string())
    @fs.write_string_to_file(path, content)
  }
  0
}

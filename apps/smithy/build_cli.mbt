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
fn build_path_contains(parent : String, child : String) -> Bool {
  let parent : @path.Path = parent
  let child : @path.Path = child
  let relative = child.resolve().relative(base=parent.resolve())
  let text = relative.to_string()
  text == "." ||
  (
    !relative.is_absolute() &&
    text != ".." &&
    !text.has_prefix(".." + @path.sep.to_string())
  )
}

///|
fn build_check_output_owner(output : String, owner : String) -> Unit raise {
  if !@fs.path_exists(output) {
    return
  }
  if !@fs.is_dir(output) {
    raise CliError("build output must be a dedicated directory", 2)
  }
  if @fs.read_dir(output).is_empty() {
    return
  }
  let marker = build_path(output, ".smithy-build-output")
  if !@fs.path_exists(marker) || @fs.read_file_to_string(marker) != owner {
    raise CliError(
      "build output contains files that do not belong to this configuration", 2,
    )
  }
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
  // unlink removes files and symlinks without following their targets.
  let unlinked = try {
    @fs.remove_file(path)
    true
  } catch {
    _ => false
  }
  if unlinked {
    return
  }
  if !@fs.path_exists(path) {
    return
  }
  // On Windows a directory symlink is removed with rmdir. A real nonempty
  // directory fails here and is traversed only after both removal attempts.
  let removed_directory = try {
    @fs.remove_dir(path)
    true
  } catch {
    _ => false
  }
  if removed_directory {
    return
  }
  for name in @fs.read_dir(path) {
    let child = build_path(path, name)
    build_remove_tree(child)
  }
  @fs.remove_dir(path)
}

///|
fn build_add_files(
  loader : @smithy.Loader,
  runner : @build.BuildRunner,
  path : String,
  source_root : String?,
  projection~ : String? = None,
) -> Unit raise {
  build_add_files_impl(loader, runner, path, source_root, projection~) catch {
    @resources.ResourceError(code, origin, message) =>
      raise @build.InvalidBuildConfig(
        "Could not load resource `" + origin + "` [" + code + "]: " + message,
      )
    error => raise error
  }
}

///|
fn build_add_files_impl(
  loader : @smithy.Loader,
  runner : @build.BuildRunner,
  path : String,
  source_root : String?,
  projection~ : String?,
) -> Unit raise {
  let registry = @local_resources.register(@resources.Registry::new()).add_repository({
      id: "input",
      provider: "local",
      location: path,
    },
  )
  let artifact = registry.resolve({ repository: "input", key: ".", })
  let tree = artifact.tree
  if path.has_suffix(".jar") && !@fs.is_dir(path) {
    build_add_archive(loader, runner, tree, path, source_root, projection~)
    return
  }
  let declarations = tree
    .entries()
    .filter_map(entry => {
      if entry.has_suffix(".smithy") || entry.has_suffix(".json") {
        Some(@resources.Declaration::{ name: entry, path: entry, })
      } else {
        None
      }
    })
  let models : Map[String, @resources.Resource] = Map([])
  for resource in @resources.load_resources(tree, declarations) {
    models[resource.path] = resource
  }
  for entry in tree.entries() {
    let origin = tree.entry_origin(entry)
    if entry.has_suffix(".jar") {
      let archive = tree.open_zip(entry)
      build_add_archive(
        loader,
        runner,
        archive,
        origin,
        source_root,
        projection~,
      )
    } else if models.get(entry) is Some(resource) {
      let text = resource.text()
      build_add_model(loader, runner, origin, text, projection~)
      if projection is None {
        build_record_source(runner, origin, source_root, text)
      }
    }
  }
}

///|
fn build_add_model(
  loader : @smithy.Loader,
  runner : @build.BuildRunner,
  origin : String,
  text : String,
  projection~ : String?,
) -> Unit {
  let input = if origin.has_suffix(".smithy") {
    @smithy.ModelInput::Idl(name=origin, text~)
  } else {
    @smithy.ModelInput::Json(name=origin, text~)
  }
  if projection is Some(name) {
    ignore(runner.add_projection_import(name, input))
  } else {
    ignore(loader.add(input))
  }
}

///|
fn build_add_archive(
  loader : @smithy.Loader,
  runner : @build.BuildRunner,
  tree : @resources.EntryTree,
  path : String,
  source_root : String?,
  projection~ : String?,
) -> Unit raise {
  let archive_path : @path.Path = path
  let archive_name = archive_path.basename().to_owned()
  let stem = archive_name[:archive_name.length() - 4].to_owned()
  let prefix = match source_root {
    Some(root) if root != path => {
      let root_path : @path.Path = root
      archive_path
      .relative(base=root_path)
      .to_string()
      .replace_all(old="\\", new="/") +
      "/" +
      stem
    }
    _ => stem
  }
  for resource in @build.declared_models(tree) {
    let text = resource.text()
    build_add_model(loader, runner, resource.origin, text, projection~)
    if projection is None && source_root is Some(_) {
      ignore(
        runner.add_source(
          prefix + "/" + resource.name,
          text,
          source_file=Some(resource.origin),
        ),
      )
    }
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
    let relative = if path == root.to_string() {
      current.basename().to_owned()
    } else {
      current.relative(base=root).to_string().replace_all(old="\\", new="/")
    }
    ignore(runner.add_source(relative, text, source_file=Some(path)))
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
  let environment = @env.get_env_vars()
  let current : @path.Path = "."
  environment["SMITHY_ROOT_DIR"] = current.resolve().to_string()
  let config = @build.BuildConfig::parse(
    @fs.read_file_to_string(config_path),
    environment~,
  )
  let config_file : @path.Path = config_path
  let base = config_file.dirname().to_string()
  let base_path : @path.Path = base
  let base = base_path.resolve().to_string()
  let output = build_path(base, config.output_directory)
  let normalized : @path.Path = output
  let output = normalized.resolve().to_string()
  let cwd : @path.Path = "."
  let output_path : @path.Path = output
  let owner = config_file.resolve().to_string() + "\n" + output + "\n"
  if output == cwd.resolve().to_string() ||
    build_path_contains(output, base) ||
    output_path.dirname().to_string() == output {
    raise CliError("build output directory must be a dedicated directory", 2)
  }
  let protected_paths = config.sources + config.imports
  for projection in config.projections {
    protected_paths.append(projection.imports)
  }
  for path in protected_paths {
    let input = build_path(base, path)
    if build_path_contains(output, input) || build_path_contains(input, output) {
      raise CliError(
        "build output directory must not overlap model sources or imports", 2,
      )
    }
  }
  if clean {
    build_check_output_owner(output, owner)
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
      build_add_files(loader, runner, path, Some(path))
    }
  }
  for name in config.imports {
    build_add_files(loader, runner, build_path(base, name), None)
  }
  for projection in config.projections {
    for name in projection.imports {
      build_add_files(
        loader,
        runner,
        build_path(base, name),
        None,
        projection=Some(projection.name),
      )
    }
  }
  let loaded = loader.assemble()
  for d in loaded.diagnostics {
    eprintln(diagnostic(d, Map([])))
  }
  guard loaded.model is Some(model) else { return 1 }
  let built = runner.run_result(model)
  if built.errors.is_empty() || !built.artifacts.is_empty() {
    build_check_output_owner(output, owner)
    build_remove_tree(output)
  }
  for relative, content in built.artifacts {
    let path = build_path(output, relative)
    let file : @path.Path = path
    build_mkdir(file.dirname().to_string())
    @fs.write_string_to_file(path, content)
  }
  if !built.artifacts.is_empty() {
    @fs.write_string_to_file(build_path(output, ".smithy-build-output"), owner)
  }
  for message in built.errors {
    eprintln(message)
  }
  if built.errors.is_empty() {
    0
  } else {
    1
  }
}

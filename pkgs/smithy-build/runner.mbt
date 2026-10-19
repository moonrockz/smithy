///|
pub struct BuildRunner {
  config : BuildConfig
  plugins : Map[
    String,
    (@smithy.Model, Json) -> Map[String, String] raise BuildError,
  ]
  sources : Map[String, String]
  source_conflicts : Array[String]
  source_origins : Set[String]
  source_metadata : Set[String]
  projection_imports : Map[String, Array[@smithy.ModelInput]]
}

///|
pub fn BuildRunner::new(config : BuildConfig) -> BuildRunner {
  {
    config,
    plugins: Map([]),
    sources: Map([]),
    source_conflicts: [],
    source_origins: Set([]),
    source_metadata: Set([]),
    projection_imports: Map([]),
  }
}

///|
pub fn BuildRunner::add_source(
  self : BuildRunner,
  name : String,
  content : String,
  source_file~ : String? = None,
) -> BuildRunner {
  if self.sources.contains(name) {
    self.source_conflicts.push(
      "Conflicting source filename `" +
      name +
      "` from `" +
      source_file.unwrap_or(name) +
      "`",
    )
    return self
  }
  self.sources[name] = content
  self.source_origins.add(source_file.unwrap_or(name))
  if name.has_suffix(".smithy") {
    if @syntax.parse(@syntax.SourceText::new(content)).ast is Some(file) {
      for metadata in file.metadata {
        self.source_metadata.add(metadata.key.value)
      }
    }
  } else if name.has_suffix(".json") {
    let document = @json.parse(content) catch { _ => Json::null() }
    if document is { "metadata": Object(metadata), .. } {
      for key, _ in metadata {
        self.source_metadata.add(key)
      }
    }
  }
  self
}

///|
fn BuildRunner::projected_sources(
  self : BuildRunner,
  original : @smithy.Model,
  projected : @smithy.Model,
) -> @smithy.Model {
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  for id, shape in projected.shapes {
    let source = match original.shapes.get(id.root()) {
      None => true
      Some(original_shape) =>
        self.source_origins.contains(original_shape.source.file)
    }
    if source {
      shapes[id] = shape
    }
  }
  let metadata : Map[String, @smithy.NodeValue] = Map([])
  for key, value in projected.metadata {
    if !original.metadata.contains(key) || self.source_metadata.contains(key) {
      metadata[key] = value
    }
  }
  { shapes, metadata, }
}

///|
/// Supply local projection imports; the caller owns file access.
pub fn BuildRunner::add_projection_import(
  self : BuildRunner,
  projection : String,
  input : @smithy.ModelInput,
) -> BuildRunner {
  let inputs = self.projection_imports.get(projection).unwrap_or([])
  inputs.push(input)
  self.projection_imports[projection] = inputs
  self
}

///|
fn BuildRunner::merge_projection_imports(
  self : BuildRunner,
  model : @smithy.Model,
  projection : String,
) -> @smithy.Model raise BuildError {
  let inputs = self.projection_imports.get(projection).unwrap_or([])
  if inputs.is_empty() {
    return model
  }
  let document = model.to_json_ast(preserve_mixins=true) catch {
    _ =>
      raise InvalidBuildConfig(
        "Could not serialize model before projection imports",
      )
  }
  let loader = @smithy.Loader::new().add_ast("<projection-base>", document)
  for input in inputs {
    ignore(loader.add(input))
  }
  let result = loader.assemble()
  guard result.model is Some(merged) else {
    raise InvalidBuildConfig(
      "Could not merge imports of projection `" +
      projection +
      "`: " +
      result.diagnostics.map(d => d.message).join("\n"),
    )
  }
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  for id, shape in merged.shapes {
    shapes[id] = match model.shapes.get(id) {
      Some(original) => { ..shape, source: original.source, }
      None => shape
    }
  }
  { shapes, metadata: merged.metadata, }
}

///|
/// Register a plugin that writes relative filenames for a projected model.
pub fn BuildRunner::register_plugin(
  self : BuildRunner,
  name : String,
  execute : (@smithy.Model, Json) -> Map[String, String] raise BuildError,
) -> BuildRunner {
  self.plugins[name] = execute
  self
}

///|
fn transform_trait_id(text : String) -> String {
  if text.contains("#") {
    text
  } else {
    "smithy.api#" + text
  }
}

///|
/// Apply one built-in transform without validating or running plugins.
pub fn apply_transform(
  model : @smithy.Model,
  transform : TransformConfig,
) -> @smithy.Model raise BuildError {
  transform_model(model, transform)
}

///|
fn transform_model(
  model : @smithy.Model,
  transform : TransformConfig,
  original_model~ : @smithy.Model? = None,
  original_events~ : Array[@smithy.ValidationEvent]? = None,
) -> @smithy.Model raise BuildError {
  if transform_misc(model, transform, original_model~, original_events~)
    is Some(projected) {
    return projected
  }
  if transform_rewrite(model, transform) is Some(projected) {
    return projected
  }
  if transform_shape_filter(model, transform) is Some(projected) {
    return projected
  }
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  let metadata : Map[String, @smithy.NodeValue] = Map([])
  for key, value in model.metadata {
    metadata[key] = value
  }
  let trait_names = config_strings(transform.args, "traits")
  let names = trait_names.map(transform_trait_id)
  for id, shape in model.shapes {
    let traits : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
    for trait_id, value in shape.traits {
      let included = names.contains(trait_id.to_string())
      if (transform.name == "excludeTraits" && !included) ||
        (transform.name == "includeTraits" && included) ||
        (transform.name != "excludeTraits" && transform.name != "includeTraits") {
        traits[trait_id] = value
      }
    }
    shapes[id] = { ..shape, traits, }
  }
  match transform.name {
    "excludeTraits" | "includeTraits" => ()
    "includeShapesByTag" | "excludeShapesByTag" => {
      let tags = config_strings(transform.args, "tags")
      let filtered : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
      for id, shape in shapes {
        let tagged = match shape.trait_value("smithy.api#tags") {
          Some(value) =>
            match @json.to_json(value) {
              Array(values) =>
                values
                .iter()
                .any(v => {
                  match v {
                    String(tag) => tags.contains(tag)
                    _ => false
                  }
                })
              _ => false
            }
          None => false
        }
        if id.to_string().has_prefix("smithy.api#") ||
          (transform.name == "includeShapesByTag" && tagged) ||
          (transform.name == "excludeShapesByTag" && !tagged) {
          filtered[id] = shape
        }
      }
      return { shapes: filtered, metadata, }
    }
    "excludeMetadata" | "includeMetadata" => {
      let keys = config_strings(transform.args, "keys")
      let result : Map[String, @smithy.NodeValue] = Map([])
      for key, value in metadata {
        let included = keys.contains(key)
        if (transform.name == "excludeMetadata" && !included) ||
          (transform.name == "includeMetadata" && included) {
          result[key] = value
        }
      }
      return { shapes, metadata: result, }
    }
    _ =>
      raise InvalidBuildConfig(
        "Unknown projection transform `" + transform.name + "`",
      )
  }
  { shapes, metadata, }
}

///|
fn model_json(
  model : @smithy.Model,
  settings : Json,
) -> String raise BuildError {
  let include_prelude = config_bool(settings, "includePreludeShapes")
  let shapes = model.shapes.filter((_, shape) => {
    shape.source.file != "<contracts>"
  })
  let model = { ..model, shapes, }
  let document = model.to_json_ast(include_prelude~, preserve_mixins=true) catch {
    _ => raise InvalidBuildConfig("Could not serialize projected model")
  }
  @syntax.encode_json_ast(document).stringify(indent=4) + "\n"
}

///|
fn build_info(model : @smithy.Model, projection : ProjectionConfig) -> String {
  let metadata : Map[String, Json] = Map([])
  for key, value in model.metadata {
    metadata[key] = @json.to_json(value)
  }
  let trait_names : Array[String] = []
  let trait_defs : Array[String] = []
  let services : Array[String] = []
  let operations : Array[String] = []
  let resources : Array[String] = []
  for id, shape in model.shapes {
    if shape.source.file == "<contracts>" {
      continue
    }
    if shape.trait_value("smithy.api#trait") is Some(_) {
      trait_defs.push(id.to_string())
    }
    for trait_id, _ in shape.traits {
      if !trait_names.contains(trait_id.to_string()) {
        trait_names.push(trait_id.to_string())
      }
    }
    match shape.body {
      @smithy.Service(..) => services.push(id.to_string())
      @smithy.Operation(..) => operations.push(id.to_string())
      @smithy.Resource(..) => resources.push(id.to_string())
      _ => ()
    }
  }
  for ids in [trait_names, trait_defs, services, operations, resources] {
    ids.sort_by((a, b) => a.lexical_compare(b))
  }
  let trait_names = trait_names.filter(name => trait_defs.contains(name))
  let validation_events : Array[Json] = []
  for event in model.validation_events() {
    let encoded : Map[String, Json] = {
      "id": Json::string(event.id),
      "severity": Json::string(event.severity),
      "message": Json::string(event.message),
      "filename": Json::string(event.source.map(s => s.file).unwrap_or("-")),
      "line": Json::number(0.0),
      "column": Json::number(0.0),
    }
    if event.shape is Some(id) {
      encoded["shapeId"] = Json::string(id.to_string())
    }
    if event.suppression_reason is Some(reason) {
      encoded["suppressionReason"] = Json::string(reason)
    }
    validation_events.push(Json::object(encoded))
  }
  let transforms = projection.transforms.map(t => {
    Json::object({ "name": Json::string(t.name), "args": t.args })
  })
  let projection_fields : Map[String, Json] = {
    "abstract": Json::boolean(projection.is_abstract),
    "imports": Json::array(projection.imports.map(Json::string)),
    "transforms": Json::array(transforms),
    "plugins": Json::object(projection.plugins),
  }
  let fields : Map[String, Json] = {
    "version": Json::string("1.0"),
    "projectionName": Json::string(projection.name),
    "projection": Json::object(projection_fields),
    "validationEvents": Json::array(validation_events),
    "traitNames": Json::array(trait_names.map(Json::string)),
    "traitDefNames": Json::array(trait_defs.map(Json::string)),
    "serviceShapeIds": Json::array(services.map(Json::string)),
    "operationShapeIds": Json::array(operations.map(Json::string)),
    "resourceShapeIds": Json::array(resources.map(Json::string)),
    "metadata": Json::object(metadata),
  }
  Json::object(fields).stringify(indent=4) + "\n"
}

///|
fn BuildRunner::apply_transforms(
  self : BuildRunner,
  model : @smithy.Model,
  projection : ProjectionConfig,
  active : Array[String],
  original_model~ : @smithy.Model? = None,
  original_events~ : Array[@smithy.ValidationEvent]? = None,
) -> @smithy.Model raise BuildError {
  if active.contains(projection.name) {
    raise InvalidBuildConfig(
      "Projection apply cycle at `" + projection.name + "`",
    )
  }
  let path = active.copy()
  path.push(projection.name)
  let mut projected = model
  let original_model = original_model.unwrap_or(model)
  let original_events = original_events.unwrap_or_else(() => {
    model.validation_events()
  })
  for transform in projection.transforms {
    if transform.name == "apply" {
      for
        name in config_strings(
          misc_args(transform, "projections"),
          "projections",
        ) {
        let mut found : ProjectionConfig? = None
        for candidate in self.config.projections {
          if candidate.name == name {
            found = Some(candidate)
            break
          }
        }
        guard found is Some(target) else {
          raise InvalidBuildConfig("Unknown applied projection `" + name + "`")
        }
        projected = self.apply_transforms(
          projected,
          target,
          path,
          original_model=Some(original_model),
          original_events=Some(original_events),
        )
      }
    } else {
      projected = transform_model(
        projected,
        transform,
        original_model=Some(original_model),
        original_events=Some(original_events),
      )
    }
  }
  projected
}

///|
fn BuildRunner::validate_config(self : BuildRunner) -> Unit raise BuildError {
  if !self.source_conflicts.is_empty() {
    raise InvalidBuildConfig(self.source_conflicts.join("\n"))
  }
  let transform_names = [
    "apply", "changeStringEnumsToEnumShapes", "changeTypes", "excludeMetadata", "excludeShapesBySelector",
    "excludeShapesByTag", "excludeShapesByTrait", "excludeTags", "excludeTraits",
    "excludeTraitsByTag", "filterSuppressions", "flattenAndRemoveMixins", "flattenClosureNamespaces",
    "flattenNamespaces", "includeClosures", "includeMetadata", "includeNamespaces",
    "includeServices", "includeShapesBySelector", "includeShapesByTag", "includeTags",
    "includeTraits", "includeTraitsByTag", "makeIdempotencyTokensClientOptional",
    "removeDeprecatedShapes", "removeTraitDefinitions", "removeUnusedShapes", "renameShapes",
  ]
  for projection in self.config.projections {
    if !plugin_name_part(projection.name) {
      raise InvalidBuildConfig(
        "Invalid projection name `" + projection.name + "`",
      )
    }
    for transform in projection.transforms {
      if !transform_names.contains(transform.name) {
        raise InvalidBuildConfig(
          "Unknown projection transform `" + transform.name + "`",
        )
      }
    }
  }
  let plugin_sets = [self.config.plugins]
  for projection in self.config.projections {
    if !projection.is_abstract {
      plugin_sets.push(projection.plugins)
    }
  }
  for plugins in plugin_sets {
    for name, _ in plugins {
      let (plugin, _) = plugin_id(name)
      if !self.config.ignore_missing_plugins &&
        !self.plugins.contains(plugin) &&
        !["model", "sources", "build-info"].contains(plugin) {
        raise InvalidBuildConfig("Unknown build plugin `" + name + "`")
      }
    }
  }
}

///|
/// Artifacts from successful plugins and failures reported by the build.
pub(all) struct BuildResult {
  artifacts : Map[String, String]
  errors : Array[String]
} derive(Debug)

///|
/// Produce artifacts, raising if any projection failed.
pub fn BuildRunner::run(
  self : BuildRunner,
  model : @smithy.Model,
) -> Map[String, String] raise BuildError {
  let result = self.run_result(model)
  if !result.errors.is_empty() {
    raise InvalidBuildConfig(result.errors.join("\n"))
  }
  result.artifacts
}

///|
/// Preserve successful projections and build information when another projection fails.
pub fn BuildRunner::run_result(
  self : BuildRunner,
  model : @smithy.Model,
) -> BuildResult {
  let artifacts : Map[String, String] = Map([])
  let errors : Array[String] = []
  self.validate_config() catch {
    InvalidBuildConfig(message) => return { artifacts, errors: [message], }
  }
  for event in model.validation_events() {
    if event.severity == "DANGER" || event.severity == "ERROR" {
      errors.push("Model validation failed: " + event.id + ": " + event.message)
    }
  }
  if !errors.is_empty() {
    return { artifacts, errors, }
  }
  let projections = self.config.projections.copy()
  if !projections.iter().any(p => p.name == "source") {
    projections.push({
      name: "source",
      is_abstract: false,
      imports: [],
      transforms: [],
      plugins: Map([]),
    })
  }
  for projection in projections {
    if projection.is_abstract {
      continue
    }
    try {
      if projection.name == "source" && !projection.transforms.is_empty() {
        raise InvalidBuildConfig(
          "The source projection cannot contain transforms",
        )
      }
      let projection_model = self.merge_projection_imports(
        model,
        projection.name,
      )
      let projected = self.apply_transforms(projection_model, projection, [])
      let findings = projected.validation_events()
      let valid_model = !findings
        .iter()
        .any(event => event.severity == "DANGER" || event.severity == "ERROR")
      for event in findings {
        if event.severity == "DANGER" || event.severity == "ERROR" {
          errors.push(
            "Projection `" +
            projection.name +
            "` validation failed: " +
            event.id +
            ": " +
            event.message,
          )
        }
      }
      self.emit_plugins(
        projected,
        projection_model,
        projection,
        artifacts,
        valid_model~,
      )
    } catch {
      InvalidBuildConfig(message) =>
        errors.push("Projection `" + projection.name + "`: " + message)
    }
  }
  { artifacts, errors, }
}

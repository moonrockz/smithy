///|
pub struct BuildRunner {
  config : BuildConfig
  plugins : Map[
    String,
    (@smithy.Model, Json) -> Map[String, String] raise BuildError,
  ]
  sources : Map[String, String]
}

///|
pub fn BuildRunner::new(config : BuildConfig) -> BuildRunner {
  { config, plugins: Map([]), sources: Map([]), }
}

///|
pub fn BuildRunner::add_source(
  self : BuildRunner,
  name : String,
  content : String,
) -> BuildRunner {
  self.sources[name] = content
  self
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
fn transform_model(
  model : @smithy.Model,
  transform : TransformConfig,
) -> @smithy.Model raise BuildError {
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
  let document = model.to_json_ast(include_prelude~) catch {
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
  let fields : Map[String, Json] = {
    "version": Json::string("1.0"),
    "projectionName": Json::string(projection.name),
    "validationEvents": Json::array([]),
    "traitNames": Json::array([]),
    "traitDefNames": Json::array([]),
    "serviceShapeIds": Json::array([]),
    "operationShapeIds": Json::array([]),
    "resourceShapeIds": Json::array([]),
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
) -> @smithy.Model raise BuildError {
  if active.contains(projection.name) {
    raise InvalidBuildConfig(
      "Projection apply cycle at `" + projection.name + "`",
    )
  }
  let path = active.copy()
  path.push(projection.name)
  let mut projected = model
  for transform in projection.transforms {
    if transform.name == "apply" {
      for name in config_strings(transform.args, "projections") {
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
        projected = self.apply_transforms(projected, target, path)
      }
    } else {
      projected = transform_model(projected, transform)
    }
  }
  projected
}

///|
/// Produce relative artifact paths and contents for each concrete projection.
pub fn BuildRunner::run(
  self : BuildRunner,
  model : @smithy.Model,
) -> Map[String, String] raise BuildError {
  for event in model.validation_events() {
    if event.severity == "DANGER" || event.severity == "ERROR" {
      raise InvalidBuildConfig(
        "Model validation failed: " + event.id + ": " + event.message,
      )
    }
  }
  let artifacts : Map[String, String] = Map([])
  let projections = self.config.projections.copy()
  if !projections.iter().any(p => p.name == "source") {
    projections.push({
      name: "source",
      is_abstract: false,
      transforms: [],
      plugins: Map([]),
    })
  }
  for projection in projections {
    if projection.name == "source" && !projection.transforms.is_empty() {
      raise InvalidBuildConfig(
        "The source projection cannot contain transforms",
      )
    }
    if projection.is_abstract {
      continue
    }
    let projected = self.apply_transforms(model, projection, [])
    for event in projected.validation_events() {
      if event.severity == "DANGER" || event.severity == "ERROR" {
        raise InvalidBuildConfig(
          "Projection `" +
          projection.name +
          "` validation failed: " +
          event.id +
          ": " +
          event.message,
        )
      }
    }
    let model_settings = match projection.plugins.get("model") {
      Some(settings) => settings
      None => self.config.plugins.get("model").unwrap_or(Json::object(Map([])))
    }
    artifacts[projection.name + "/model/model.json"] = model_json(
      projected, model_settings,
    )
    artifacts[projection.name + "/build-info/smithy-build-info.json"] = build_info(
      projected, projection,
    )
    if projection.name == "source" {
      let names = self.sources.keys().to_array()
      names.sort()
      for name in names {
        artifacts[projection.name + "/sources/" + name] = self.sources[name]
      }
      artifacts[projection.name + "/sources/manifest"] = names.join("\n") + "\n"
    } else {
      artifacts[projection.name + "/sources/model.json"] = model_json(
        projected,
        Json::object(Map([])),
      )
      artifacts[projection.name + "/sources/manifest"] = "model.json\n"
    }
    let plugins : Map[String, Json] = Map([])
    for name, settings in self.config.plugins {
      plugins[name] = settings
    }
    for name, settings in projection.plugins {
      plugins[name] = settings
    }
    for name, settings in plugins {
      if name == "model" || name == "build-info" || name == "sources" {
        continue
      }
      guard self.plugins.get(name) is Some(execute) else {
        if self.config.ignore_missing_plugins {
          continue
        }
        raise InvalidBuildConfig("Unknown build plugin `" + name + "`")
      }
      for file, content in execute(projected, settings) {
        artifacts[projection.name + "/" + name + "/" + file] = content
      }
    }
  }
  artifacts
}

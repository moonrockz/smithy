///|
fn plugin_name_part(value : String) -> Bool {
  let chars = value.to_array()
  fn alphanumeric(c : Char) -> Bool {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  }
  !chars.is_empty() &&
  alphanumeric(chars[0]) &&
  chars.iter().all(c => alphanumeric(c) || c == '-' || c == '_' || c == '.')
}

///|
fn plugin_id(name : String) -> (String, String) raise BuildError {
  let parts = name.split("::").to_array()
  if parts.length() > 2 ||
    !parts.iter().all(part => plugin_name_part(part.to_owned())) {
    raise InvalidBuildConfig("Invalid build plugin name `" + name + "`")
  }
  (parts[0].to_owned(), parts[parts.length() - 1].to_owned())
}

///|
fn plugin_relative_file(value : String) -> Bool {
  let normalized = value.replace_all(old="\\", new="/")
  let chars = normalized.to_array()
  if chars.is_empty() ||
    normalized.has_prefix("/") ||
    normalized.has_suffix("/") ||
    normalized.contains("\u{0}") ||
    (chars.length() > 1 && chars[1] == ':') {
    return false
  }
  let parts = normalized.split("/").to_array()
  !parts.iter().any(part => part == "..") && parts[parts.length() - 1] != "."
}

///|
fn BuildRunner::emit_plugin_sources(
  self : BuildRunner,
  model : @smithy.Model,
  original : @smithy.Model,
  projection : ProjectionConfig,
  prefix : String,
  artifacts : Map[String, String],
) -> Unit raise BuildError {
  if projection.name == "source" {
    let names = self.sources.keys().to_array()
    names.sort()
    for name in names {
      artifacts[prefix + name] = self.sources[name]
    }
    artifacts[prefix + "manifest"] = names.join("\n") + "\n"
  } else {
    artifacts[prefix + "model.json"] = model_json(
      self.projected_sources(original, model),
      Json::object(Map([])),
    )
    artifacts[prefix + "manifest"] = "model.json\n"
  }
}

///|
fn BuildRunner::emit_plugins(
  self : BuildRunner,
  model : @smithy.Model,
  original : @smithy.Model,
  projection : ProjectionConfig,
  artifacts : Map[String, String],
  valid_model~ : Bool = true,
) -> Unit raise BuildError {
  let plugins : Map[String, Json] = Map([])
  for name, settings in self.config.plugins {
    plugins[name] = settings
  }
  // SmithyBuildConfig reinstalls the default plugin settings before merging projections.
  for builtin in ["model", "sources", "build-info"] {
    plugins[builtin] = Json::object(Map([]))
  }
  for name, settings in projection.plugins {
    plugins[name] = settings
  }
  let names = plugins.keys().to_array()
  names.sort()
  let artifact_names : Map[String, Bool] = Map([])
  let resolved : Array[(String, String, Json)] = []
  // Resolve the complete set before running any plugin, so invalid aliases cannot
  // partially execute a projection or overwrite another plugin's artifacts.
  for name in names {
    let (plugin, artifact_name) = plugin_id(name)
    if artifact_names.contains(artifact_name) {
      raise InvalidBuildConfig(
        "Multiple plugins use the same artifact name '" +
        artifact_name +
        "' in the '" +
        projection.name +
        "' projection",
      )
    }
    artifact_names[artifact_name] = true
    resolved.push((plugin, artifact_name, plugins[name]))
  }
  let scheduled : Array[(String, String, Json)] = []
  for (plugin, artifact_name, settings) in resolved {
    if self.plugins.contains(plugin) ||
      ["model", "sources", "build-info"].contains(plugin) {
      scheduled.push((plugin, artifact_name, settings))
    } else if !self.config.ignore_missing_plugins {
      let name = if plugin == artifact_name {
        plugin
      } else {
        plugin + "::" + artifact_name
      }
      raise InvalidBuildConfig(
        "Unable to find a plugin for `" +
        name +
        "` in the `" +
        projection.name +
        "` projection. Is this the correct spelling? Are you missing a dependency? Is your classpath configured correctly?",
      )
    }
  }
  let execution_errors : Array[String] = []
  for (plugin, artifact_name, settings) in scheduled {
    try {
      let prefix = projection.name + "/" + artifact_name + "/"
      if self.plugins.get(plugin) is Some(execute) {
        if !valid_model {
          continue
        }
        let files = execute(model, settings)
        for file, _ in files {
          if !plugin_relative_file(file) {
            raise InvalidBuildConfig(
              "Plugin `" +
              plugin +
              "` must write a relative artifact file, but returned `" +
              file +
              "`",
            )
          }
        }
        for file, content in files {
          artifacts[prefix + file] = content
        }
      } else {
        if !valid_model && plugin != "build-info" {
          continue
        }
        match plugin {
          "model" =>
            artifacts[prefix + "model.json"] = model_json(model, settings)
          "sources" =>
            self.emit_plugin_sources(
              model, original, projection, prefix, artifacts,
            )
          "build-info" =>
            artifacts[prefix + "smithy-build-info.json"] = build_info(
              model, projection,
            )
          _ => ()
        }
      }
    } catch {
      InvalidBuildConfig(message) => execution_errors.push(message)
    }
  }
  if !execution_errors.is_empty() {
    raise InvalidBuildConfig(execution_errors.join("\n"))
  }
}

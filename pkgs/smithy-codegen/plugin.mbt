///|
/// What a plugin knows when the build runner calls it: the model, the plugin
/// settings and the service shape that the settings name.
pub struct PluginContext {
  model : @smithy.Model
  settings : Map[String, Json]
  service : @smithy.Shape
}

///|
/// Read the plugin settings. The settings must be an object. The setting
/// `service` must be the shape ID of a service shape in the model.
pub fn PluginContext::from_build(
  model : @smithy.Model,
  settings : Json,
) -> PluginContext raise CodegenError {
  guard settings is Object(fields) else {
    raise InvalidSettings("I expected the plugin settings to be an object.")
  }
  guard fields.get("service") is Some(String(text)) &&
    @smithy.ShapeId::parse(text) is Some(id) else {
    raise InvalidSettings("I expected a service shape ID in setting `service`.")
  }
  guard model.shapes.get(id) is Some(service) else { raise MissingService(id) }
  guard service.body is Service(..) else { raise NotAService(id) }
  { model, settings: fields, service, }
}

///|
/// The shapes that the service reaches, sorted by shape ID text.
pub fn PluginContext::closure(self : PluginContext) -> Array[@smithy.ShapeId] {
  service_closure(self.model, self.service.id)
}

///|
/// Check that every setting name is in the list. The name `service` is always
/// allowed. The error names the first unknown name in sorted order.
pub fn PluginContext::check_settings(
  self : PluginContext,
  allowed : Array[String],
) -> Unit raise CodegenError {
  let keys = self.settings.keys().to_array()
  keys.sort()
  for key in keys {
    if key != "service" && !allowed.contains(key) {
      raise InvalidSettings("I found unknown setting `\{key}`.")
    }
  }
}

///|
/// The text of a setting. The result is `None` when the setting is absent.
pub fn PluginContext::setting_string(
  self : PluginContext,
  name : String,
) -> String? raise CodegenError {
  match self.settings.get(name) {
    None => None
    Some(String(text)) => Some(text)
    Some(_) =>
      raise InvalidSettings("I expected a string for setting `\{name}`.")
  }
}

///|
/// Make the function that the build runner registers as a plugin. The function
/// builds the plugin context and calls `run`. A code generation error becomes
/// an invalid build configuration error with the message of the error.
pub fn build_plugin(
  run : (PluginContext) -> Map[String, String] raise CodegenError,
) -> (@smithy.Model, Json) -> Map[String, String] raise @build.BuildError {
  (model, settings) => {
    run(PluginContext::from_build(model, settings)) catch {
      error => raise @build.InvalidBuildConfig(error.message())
    }
  }
}

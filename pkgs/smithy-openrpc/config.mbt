///|
pub struct Config {
  service : ServiceId
  version : OpenRpcVersion
  protocol_version : @rpc.ProtocolVersion
  member_names : @validation.MemberNames
  timestamp_format : @validation.TimestampFormat
  extensions : ExtensionPolicy
  title : String?
  api_version : String?
}

///|
pub fn Config::new(
  service : ServiceId,
  version~ : OpenRpcVersion = V1_3_2,
  protocol_version~ : @rpc.ProtocolVersion = @rpc.V2_0,
  member_names~ : @validation.MemberNames = @validation.Smithy,
  timestamp_format~ : @validation.TimestampFormat = @validation.EpochSeconds,
  extensions~ : ExtensionPolicy = Preserve,
  title~ : String? = None,
  api_version~ : String? = None,
) -> Config {
  {
    service,
    version,
    protocol_version,
    member_names,
    timestamp_format,
    extensions,
    title,
    api_version,
  }
}

///|
pub fn Config::service(self : Config) -> ServiceId {
  self.service
}

///|
fn settings_string(
  fields : Map[String, Json],
  name : String,
  id : @smithy.ShapeId,
) -> String? raise OpenRpcError {
  match fields.get(name) {
    None => None
    Some(String(value)) => Some(value)
    _ =>
      raise InvalidConfiguration(
        id,
        "I expected a string for setting `" + name + "`.",
      )
  }
}

///|
pub fn Config::from_json(settings : Json) -> Config raise OpenRpcError {
  let subject = @smithy.ShapeId::parse("smithy.rpc#jsonRpc").unwrap()
  guard settings is Object(fields) else {
    raise InvalidConfiguration(
      subject, "I expected OpenRPC settings to be an object.",
    )
  }
  guard settings_string(fields, "service", subject).bind(ServiceId::parse)
    is Some(service) else {
    raise InvalidConfiguration(
      subject, "I expected a root service shape ID in setting `service`.",
    )
  }
  let id = service.shape_id()
  for key, _ in fields {
    if ![
        "service", "version", "protocolVersion", "useJsonName", "timestampFormat",
        "extensions", "title", "apiVersion",
      ].contains(key) {
      raise InvalidConfiguration(
        id,
        "I found unknown OpenRPC setting `" + key + "`.",
      )
    }
  }
  guard OpenRpcVersion::parse(
      settings_string(fields, "version", id).unwrap_or("1.3.2"),
    )
    is Some(version) else {
    raise InvalidConfiguration(id, "I support OpenRPC document version 1.3.2.")
  }
  guard settings_string(fields, "protocolVersion", id).unwrap_or("2.0") == "2.0" else {
    raise InvalidConfiguration(
      id, "I can export only JSON-RPC wire version 2.0 as OpenRPC.",
    )
  }
  let member_names = match fields.get("useJsonName") {
    None | Some(False) => @validation.Smithy
    Some(True) => @validation.JsonName
    _ =>
      raise InvalidConfiguration(
        id, "I expected a boolean useJsonName setting.",
      )
  }
  let timestamp_format = match
    settings_string(fields, "timestampFormat", id).unwrap_or("epoch-seconds") {
    "epoch-seconds" => @validation.EpochSeconds
    "date-time" => @validation.DateTime
    _ =>
      raise InvalidConfiguration(
        id, "I expected epoch-seconds or date-time for timestampFormat.",
      )
  }
  let extensions = match
    settings_string(fields, "extensions", id).unwrap_or("preserve") {
    "preserve" => Preserve
    "omit" => Omit
    "fail" => Fail
    _ =>
      raise InvalidConfiguration(
        id, "I expected preserve, omit or fail for extensions.",
      )
  }
  Config::new(
    service,
    version~,
    member_names~,
    timestamp_format~,
    extensions~,
    title=settings_string(fields, "title", id),
    api_version=settings_string(fields, "apiVersion", id),
  )
}

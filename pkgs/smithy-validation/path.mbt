///|
/// A source position. Occurrences distinguish repeated native object fields.
pub(all) enum InstanceStep {
  Field(String, Int32)
  Index(Int32)
  FieldPosition(Int32)
  FieldNamePosition(Int32)
  MapKey(String, Int32)
} derive(Eq, Debug, Hash)

///|
pub struct InstancePath {
  priv parts : Array[InstanceStep]
} derive(Eq, Debug, Hash)

///|
pub fn InstancePath::root() -> InstancePath {
  { parts: [], }
}

///|
fn InstancePath::child(
  self : InstancePath,
  step : InstanceStep,
) -> InstancePath {
  { parts: self.parts + [step], }
}

///|
pub fn InstancePath::field(
  self : InstancePath,
  name : String,
  occurrence~ : Int32 = 0,
) -> InstancePath raise ConfigurationError {
  guard occurrence >= 0 else {
    raise ConfigurationError("I expected a nonnegative field occurrence.")
  }
  self.child(Field(name, occurrence))
}

///|
pub fn InstancePath::index(
  self : InstancePath,
  index : Int32,
) -> InstancePath raise ConfigurationError {
  guard index >= 0 else {
    raise ConfigurationError("I expected a nonnegative array index.")
  }
  self.child(Index(index))
}

///|
pub fn InstancePath::map_key(
  self : InstancePath,
  name : String,
  occurrence~ : Int32 = 0,
) -> InstancePath raise ConfigurationError {
  guard occurrence >= 0 else {
    raise ConfigurationError("I expected a nonnegative map-key occurrence.")
  }
  self.child(MapKey(name, occurrence))
}

///|
pub fn InstancePath::steps(self : InstancePath) -> Array[InstanceStep] {
  self.parts.copy()
}

///|
pub fn InstancePath::append(
  self : InstancePath,
  relative : InstancePath,
) -> InstancePath {
  { parts: self.parts + relative.parts, }
}

///|
pub fn InstancePath::pointer(self : InstancePath) -> String {
  let out = StringBuilder()
  for part in self.parts {
    out.write_string("/")
    match part {
      Index(i) | FieldPosition(i) | FieldNamePosition(i) =>
        out.write_string(i.to_string())
      Field(name, _) | MapKey(name, _) =>
        out.write_string(
          name.replace_all(old="~", new="~0").replace_all(old="/", new="~1"),
        )
    }
  }
  out.to_string()
}

///|
pub impl @json.ToJson for InstancePath with fn to_json(self) {
  Json::array(
    self.parts.map(step => {
      match step {
        FieldNamePosition(i) =>
          Json::object({
            "kind": Json::string("fieldNamePosition"),
            "index": Json::number(i.to_double()),
          })
        FieldPosition(i) =>
          Json::object({
            "kind": Json::string("fieldPosition"),
            "index": Json::number(i.to_double()),
          })
        Index(i) =>
          Json::object({
            "kind": Json::string("index"),
            "index": Json::number(i.to_double()),
          })
        Field(name, occurrence) | MapKey(name, occurrence) =>
          Json::object({
            "kind": Json::string(
              if step is MapKey(_, _) {
                "mapKey"
              } else {
                "field"
              },
            ),
            "name": Json::string(name),
            "occurrence": Json::number(occurrence.to_double()),
          })
      }
    }),
  )
}

///|
pub fn InstancePath::field_position(
  self : InstancePath,
  index : Int32,
) -> InstancePath raise ConfigurationError {
  guard index >= 0 else {
    raise ConfigurationError(
      "I expected a nonnegative physical field position.",
    )
  }
  self.child(FieldPosition(index))
}

///|
pub fn InstancePath::field_name_position(
  self : InstancePath,
  index : Int32,
) -> InstancePath raise ConfigurationError {
  guard index >= 0 else {
    raise ConfigurationError(
      "I expected a nonnegative physical field-name position.",
    )
  }
  self.child(FieldNamePosition(index))
}

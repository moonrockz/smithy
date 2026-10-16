///|
fn[T : @json.ToJson] put(
  fields : Map[String, Json],
  key : String,
  value : T?,
) -> Unit {
  if value is Some(v) {
    fields[key] = @json.to_json(v)
  }
}

///|
pub impl @json.ToJson for JsonAst with fn to_json(self) {
  let fields : Map[String, Json] = { "smithy": Json::string(self.smithy) }
  put(fields, "metadata", self.metadata)
  put(fields, "shapes", self.shapes)
  Json::object(fields)
}

///|
pub impl @json.ToJson for JsonReference with fn to_json(self) {
  { "target": Json::string(self.target) }
}

///|
pub impl @json.ToJson for JsonMember with fn to_json(self) {
  let fields : Map[String, Json] = { "target": Json::string(self.target) }
  put(fields, "traits", self.traits)
  Json::object(fields)
}

///|
pub impl @json.ToJson for JsonShape with fn to_json(self) {
  let fields : Map[String, Json] = { "type": Json::string(self.kind.keyword()) }
  match self.kind {
    Simple(_) | Apply => ()
    List(m) | Set(m) => put(fields, "member", m)
    Map(key~, value~) => {
      put(fields, "key", key)
      put(fields, "value", value)
    }
    Structure(ms) | Union(ms) | Enum(ms) | IntEnum(ms) =>
      put(fields, "members", ms)
    Operation(op) => {
      put(fields, "input", op.input)
      put(fields, "output", op.output)
      put(fields, "errors", op.errors)
    }
    Service(s) => {
      put(fields, "version", s.version)
      put(fields, "operations", s.operations)
      put(fields, "resources", s.resources)
      put(fields, "errors", s.errors)
      put(fields, "rename", s.rename)
    }
    Resource(r) => {
      put(fields, "identifiers", r.identifiers)
      put(fields, "properties", r.properties)
      put(fields, "create", r.create)
      put(fields, "put", r.put)
      put(fields, "read", r.read)
      put(fields, "update", r.update)
      put(fields, "delete", r.delete)
      put(fields, "list", r.list)
      put(fields, "operations", r.operations)
      put(fields, "collectionOperations", r.collectionOperations)
      put(fields, "resources", r.resources)
    }
  }
  put(fields, "traits", self.traits)
  put(fields, "mixins", self.mixins)
  Json::object(fields)
}

///|
/// Encode a typed document, omitting absent fields and preserving explicit
/// empty objects/arrays. Object order and whitespace are not source fidelity.
pub fn encode(document : JsonAst) -> Json {
  @json.to_json(document)
}

///|
/// Encode as JSON text. Core JSON retains parsed number spellings.
pub fn stringify(document : JsonAst, indent~ : Int32 = 0) -> String {
  encode(document).stringify(indent~)
}

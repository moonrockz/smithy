///|
pub(all) enum ModelInput {
  Idl(name~ : String, text~ : String)
  Json(name~ : String, text~ : String)
  Ast(name~ : String, document~ : @syntax.JsonAst)
} derive(Debug)

///|
/// An in-memory multi-file loader. It never reads files or the network.
/// Repeated assembly creates fresh state and does not mutate its inputs.
pub struct Loader {
  inputs : Array[ModelInput]
}

///|
pub fn Loader::new() -> Loader {
  { inputs: [], }
}

///|
pub fn Loader::add(self : Loader, input : ModelInput) -> Loader {
  self.inputs.push(input)
  self
}

///|
pub fn Loader::add_idl(self : Loader, name : String, text : String) -> Loader {
  self.add(Idl(name~, text~))
}

///|
pub fn Loader::add_json(self : Loader, name : String, text : String) -> Loader {
  self.add(Json(name~, text~))
}

///|
pub fn Loader::add_ast(
  self : Loader,
  name : String,
  document : @syntax.JsonAst,
) -> Loader {
  self.add(Ast(name~, document~))
}

///|
priv struct RawShape {
  id : String
  fields : Map[String, Json]
  source : SourceLocation
}

///|
priv struct Application {
  target : String
  traits : Map[String, Json]
  source : SourceLocation
}

///|
priv struct Assembly {
  raw : Map[String, RawShape]
  duplicates : Array[(RawShape, RawShape)]
  applications : Array[Application]
  metadata : Map[String, NodeValue]
  diagnostics : Array[ModelDiagnostic]
  known : Set[String]
  kinds : Map[String, String]
  public_prelude : Set[String]
  locations : Map[String, SourceLocation]
  bindings : Map[String, String]
  syntactic : Array[(String, SourceLocation)]
}

///|
fn Assembly::new() -> Assembly {
  {
    raw: Map([]),
    duplicates: [],
    applications: [],
    metadata: Map([]),
    diagnostics: [],
    known: Set([]),
    kinds: Map([]),
    public_prelude: Set([]),
    locations: Map([]),
    bindings: Map([]),
    syntactic: [],
  }
}

///|
fn location(
  file : String,
  path~ : String = "",
  span? : @syntax.Span,
) -> SourceLocation {
  { file, path, span, }
}

///|
fn is_builtin_source(name : String) -> Bool {
  name == "<prelude>" || name == "<contracts>"
}

///|
fn pointer(text : String) -> String {
  text.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn Assembly::problem(
  self : Assembly,
  code : String,
  message : String,
  source : SourceLocation,
  shape? : String,
) -> Unit {
  self.diagnostics.push({
    code,
    severity: Error,
    message,
    source,
    shape: shape.bind(ShapeId::parse),
  })
}

///|
fn object(value : Json) -> Map[String, Json] {
  match value {
    Object(fields) => fields
    _ => Map([])
  }
}

///|
fn object_field(fields : Map[String, Json], key : String) -> Map[String, Json] {
  object(fields.get(key).unwrap_or(Json::null()))
}

///|
fn string_field(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn array_field(fields : Map[String, Json], key : String) -> Array[Json] {
  match fields.get(key) {
    Some(Array(values)) => values
    _ => []
  }
}

///|
fn copy(fields : Map[String, Json]) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for key, value in fields {
    out[key] = value
  }
  out
}

///|
fn reference(id : String) -> Json {
  { "target": Json::string(id) }
}

///|
fn Assembly::version(
  self : Assembly,
  version : String,
  source : SourceLocation,
) -> Unit {
  if @syntax.Version::of(version) is None {
    self.problem(
      "SM-MODEL-001",
      "I support Smithy 1.0 and 2.0, but found version \{version}.",
      source,
    )
  }
}

///|
fn Assembly::metadata_value(
  self : Assembly,
  key : String,
  value : Json,
  source : SourceLocation,
) -> Unit {
  let incoming = NodeValue::from_json(value) catch {
    InvalidNode(message) => {
      self.problem("SM-MODEL-001", message, source)
      return
    }
  }
  match (self.metadata.get(key), incoming) {
    (Some(Array(a)), Array(b)) => self.metadata[key] = Array(a + b)
    (Some(old), value) if old != value =>
      self.problem(
        "SM-MODEL-006",
        "I found conflicting metadata values for \{key}.",
        source,
      )
    _ => self.metadata[key] = incoming
  }
}

///|
fn Assembly::merge_traits(
  self : Assembly,
  into : Map[String, Json],
  incoming : Map[String, Json],
  source : SourceLocation,
  shape : String,
) -> Unit {
  for trait_, value in incoming {
    match into.get(trait_) {
      None => into[trait_] = value
      Some(old) => {
        let kind = self.kinds.get(trait_).unwrap_or("")
        match (old, value) {
          (Array(a), Array(b)) if kind == "list" || kind == "set" =>
            into[trait_] = Json::array(a + b)
          _ => {
            let equal = try
              NodeValue::from_json(old) == NodeValue::from_json(value)
            catch {
              _ => false
            }
            if !equal {
              self.problem(
                "SM-MODEL-007",
                "I found conflicting values for trait \{trait_} on \{shape}.",
                source,
                shape~,
              )
            }
          }
        }
      }
    }
  }
}

///|
fn Assembly::add_shape(self : Assembly, raw : RawShape) -> Unit {
  guard ShapeId::parse(raw.id) is Some(id) && id.member is None else {
    self.problem(
      "SM-MODEL-002",
      "I expected an absolute root shape ID, but found \{raw.id}.",
      raw.source,
    )
    return
  }
  if self.raw.get(raw.id) is Some(old) {
    if is_builtin_source(old.source.file) && !is_builtin_source(raw.source.file) {
      // An exported document can include built-in definitions. Compare their
      // assembled contents below without merging user changes into it.
      self.duplicates.push((old, raw))
      return
    }
    if old.source.file == raw.source.file {
      self.problem(
        "SM-MODEL-003",
        "I found more than one definition of \{raw.id} in \{raw.source.file}.",
        raw.source,
        shape=raw.id,
      )
    }
    self.duplicates.push((old, raw))
    let traits = copy(object_field(old.fields, "traits"))
    self.merge_traits(
      traits,
      object_field(raw.fields, "traits"),
      raw.source,
      raw.id,
    )
    if !traits.is_empty() {
      old.fields["traits"] = Json::object(traits)
    }
    for key in ["member", "key", "value"] {
      if old.fields.get(key) is Some(Object(a)) &&
        raw.fields.get(key) is Some(Object(b)) {
        let member_ = copy(a)
        let ts = copy(object_field(a, "traits"))
        self.merge_traits(
          ts,
          object_field(b, "traits"),
          raw.source,
          raw.id + "$" + key,
        )
        if !ts.is_empty() {
          member_["traits"] = Json::object(ts)
        }
        old.fields[key] = Json::object(member_)
      }
    }
    let ms = copy(object_field(old.fields, "members"))
    for name, value in object_field(raw.fields, "members") {
      if ms.get(name) is Some(Object(member_)) {
        let member_ = copy(member_)
        let ts = copy(object_field(member_, "traits"))
        self.merge_traits(
          ts,
          object_field(object(value), "traits"),
          raw.source,
          raw.id + "$" + name,
        )
        if !ts.is_empty() {
          member_["traits"] = Json::object(ts)
        }
        ms[name] = Json::object(member_)
      }
    }
    if !ms.is_empty() {
      old.fields["members"] = Json::object(ms)
    }
  } else {
    if id.namespace == "smithy.api" && raw.source.file != "<prelude>" {
      self.problem(
        "SM-MODEL-014",
        "I cannot define \{raw.id} in the reserved prelude namespace.",
        raw.source,
        shape=raw.id,
      )
    }
    self.raw[raw.id] = raw
    self.locations[raw.id] = raw.source
  }
}

///|
fn Assembly::add_document(
  self : Assembly,
  name : String,
  document : @syntax.JsonAst,
) -> Unit {
  self.version(document.smithy, location(name, path="/smithy"))
  for key, value in document.metadata.unwrap_or(Map([])) {
    self.metadata_value(
      key,
      value,
      location(name, path="/metadata/" + pointer(key)),
    )
  }
  for id, shape in document.shapes.unwrap_or(Map([])) {
    let source = location(name, path="/shapes/" + pointer(id))
    let fields = object(@json.to_json(shape))
    if !document.smithy.has_prefix("2") &&
      (
        shape.mixins is Some(_) ||
        shape.traits.unwrap_or(Map([])).contains("smithy.api#mixin") ||
        shape.kind is Enum(_) ||
        shape.kind is IntEnum(_) ||
        (shape.kind is Resource(r) && r.properties is Some(_))
      ) {
      self.problem(
        "SM-MODEL-008",
        "I found Smithy 2.0-only syntax on \{id} in a \{document.smithy} document.",
        source,
        shape=id,
      )
    }
    if shape.kind is Apply {
      self.applications.push({
        target: id,
        traits: object_field(fields, "traits"),
        source,
      })
    } else {
      if document.smithy.has_prefix("2") && shape.kind is Set(_) {
        self.problem(
          "SM-MODEL-010",
          "I found a set shape \{id} in a Smithy 2.0 document; I expected a list.",
          source,
          shape=id,
        )
      }
      self.add_shape({ id, fields, source, })
    }
  }
}

///|
pub fn Loader::assemble(self : Loader) -> LoadResult {
  let assembly = Assembly::new()
  let idls : Array[(String, @syntax.IdlFile)] = []
  let jsons : Array[(String, @syntax.JsonAst)] = []
  let inputs = [
    ModelInput::Idl(name="<prelude>", text=prelude_text()),
    ModelInput::Idl(name="<contracts>", text=contracts_text()),
  ]
  for input in self.inputs {
    let name = match input {
      Idl(name~, ..) | Json(name~, ..) | Ast(name~, ..) => name
    }
    if is_builtin_source(name) {
      assembly.problem(
        "SM-MODEL-001",
        "I reserve the source name \{name} for built-in definitions.",
        location(name),
      )
    } else {
      inputs.push(input)
    }
  }
  for input in inputs {
    match input {
      Idl(name~, text~) => {
        let parsed = @syntax.parse_idl(text, name~)
        for d in parsed.diagnostics {
          assembly.diagnostics.push({
            code: d.code,
            severity: d.severity,
            message: d.message,
            source: location(name, span=d.span),
            shape: None,
          })
        }
        if !parsed.has_errors() && parsed.ast is Some(file) {
          idls.push((name, file))
          assembly.collect_idl_names(name, file)
        }
      }
      Json(name~, text~) =>
        try {
          let document = @syntax.parse_json_ast(text)
          jsons.push((name, document))
        } catch {
          @json.JsonDecodeError((path, message)) =>
            assembly.problem(
              "SM-MODEL-001",
              message,
              location(name, path=path.to_string()),
            )
          error =>
            assembly.problem(
              "SM-MODEL-001",
              "I could not parse the JSON model: \{error}.",
              location(name),
            )
        }
      Ast(name~, document~) =>
        jsons.push(
          (name, @syntax.decode_json_ast(@syntax.encode_json_ast(document))),
        ) catch {
          @json.JsonDecodeError((path, message)) =>
            assembly.problem(
              "SM-MODEL-001",
              message,
              location(name, path=path.to_string()),
            )
        }
    }
  }
  for (_, document) in jsons {
    for id, shape in document.shapes.unwrap_or(Map([])) {
      if shape.kind is Apply {
        continue
      }
      assembly.known.add(id)
      assembly.kinds[id] = shape.kind.keyword()
    }
  }
  for (name, file) in idls {
    assembly.add_idl(name, file)
  }
  for (name, document) in jsons {
    assembly.add_document(name, document)
  }
  assembly.finish()
}

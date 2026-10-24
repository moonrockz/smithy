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
  builtins : Array[BuiltinIdl]
  defaults : Array[@syntax.JsonAst]
  protocol_tests : Bool
}

///|
pub fn Loader::new(protocol_tests~ : Bool = false) -> Loader {
  { inputs: [], builtins: [], defaults: [], protocol_tests, }
}

///|
/// An IDL source of built-in definitions, added with Loader::add_builtin_idl.
struct BuiltinIdl {
  name : String
  text : String
}

///|
/// Add an IDL source of built-in definitions, such as the trait definitions of
/// a protocol. The model treats it like the prelude: to_json_ast and to_idl
/// omit its shapes unless include_prelude is true, and other sources cannot
/// apply traits to its shapes or define them with different contents. An
/// exported model that holds identical definitions loads without a conflict.
/// The source locations of its shapes have the kind BuiltIn. In this loader,
/// the name is reserved for these definitions: another input with the same
/// name is an error. Other loaders are not affected.
pub fn Loader::add_builtin_idl(
  self : Loader,
  name : String,
  text : String,
) -> Loader {
  self.builtins.push({ name, text, })
  self
}

///|
/// Supply validated provider definitions only where no input defines the root
/// shape. Explicit inputs take precedence regardless of call order. Defaults
/// contribute neither metadata nor apply statements; the first provider wins
/// when several providers define the same shape.
pub fn Loader::add_defaults(self : Loader, model : Model) -> Loader raise {
  self.defaults.push(model.to_json_ast())
  self
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
  builtin_sources : Set[String]
}

///|
fn Assembly::new(builtin_sources~ : Set[String] = Set([])) -> Assembly {
  {
    builtin_sources,
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
  SourceLocation::new(file, path~, span?)
}

///|
/// A location in an input of this assembly. The sources of built-in
/// definitions get the kind BuiltIn.
fn Assembly::location(
  self : Assembly,
  file : String,
  path~ : String = "",
  span? : @syntax.Span,
) -> SourceLocation {
  let kind : SourceKind = if self.builtin_sources.contains(file) {
    BuiltIn
  } else {
    User
  }
  SourceLocation::new(file, path~, span?, kind~)
}

///|
fn is_core_source(name : String) -> Bool {
  name == "<prelude>" || name == "<contracts>" || name == "<protocol-tests>"
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
  event_id~ : String = "Model",
  report~ : DiagnosticReport = Event,
  severity~ : @syntax.Severity = Error,
) -> Unit {
  self.diagnostics.push({
    code,
    event_id,
    severity,
    report,
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
    if old.source.is_builtin() && !raw.source.is_builtin() {
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
  self.version(document.smithy, self.location(name, path="/smithy"))
  for key, value in document.metadata.unwrap_or(Map([])) {
    self.metadata_value(
      key,
      value,
      self.location(name, path="/metadata/" + pointer(key)),
    )
  }
  for id, shape in document.shapes.unwrap_or(Map([])) {
    let source = self.location(name, path="/shapes/" + pointer(id))
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
  let builtin_sources = Set(["<prelude>", "<contracts>", "<protocol-tests>"])
  for builtin in self.builtins {
    builtin_sources.add(builtin.name)
  }
  let assembly = Assembly::new(builtin_sources~)
  let idls : Array[(String, @syntax.IdlFile)] = []
  let jsons : Array[(String, @syntax.JsonAst)] = []
  let input_order : Array[(Bool, Int32)] = []
  let inputs = [
    ModelInput::Idl(name="<prelude>", text=prelude_text()),
    ModelInput::Idl(name="<contracts>", text=contracts_text()),
  ]
  if self.protocol_tests {
    inputs.push(
      ModelInput::Idl(name="<protocol-tests>", text=protocol_test_traits_text()),
    )
  }
  for builtin in self.builtins {
    if is_core_source(builtin.name) {
      assembly.problem(
        "SM-MODEL-001",
        "I reserve the source name \{builtin.name} for built-in definitions.",
        location(builtin.name),
      )
    } else {
      inputs.push(Idl(name=builtin.name, text=builtin.text))
    }
  }
  for input in self.inputs {
    let name = match input {
      Idl(name~, ..) | Json(name~, ..) | Ast(name~, ..) => name
    }
    if builtin_sources.contains(name) {
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
          let (event_id, report) = syntax_event(d.code)
          assembly.diagnostics.push({
            code: d.code,
            event_id,
            severity: d.severity,
            report,
            message: d.message,
            source: assembly.location(name, span=d.span),
            shape: None,
          })
        }
        if !parsed.has_errors() && parsed.ast is Some(file) {
          input_order.push((true, idls.length()))
          idls.push((name, file))
          assembly.collect_idl_names(name, file)
        }
      }
      Json(name~, text~) =>
        try {
          let document = @syntax.parse_json_ast(text)
          input_order.push((false, jsons.length()))
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
        try {
          let document = @syntax.decode_json_ast(
            @syntax.encode_json_ast(document),
          )
          input_order.push((false, jsons.length()))
          jsons.push((name, document))
        } catch {
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
  for document in self.defaults {
    let shapes = document.shapes
      .unwrap_or(Map([]))
      .filter((id, _) => !assembly.known.contains(id))
    for id, shape in shapes {
      assembly.known.add(id)
      assembly.kinds[id] = shape.kind.keyword()
    }
    input_order.push((false, jsons.length()))
    jsons.push(
      ("<defaults>", { ..document, shapes: Some(shapes), metadata: None, }),
    )
  }
  for (is_idl, index) in input_order {
    if is_idl {
      let (name, file) = idls[index]
      assembly.add_idl(name, file)
    } else {
      let (name, document) = jsons[index]
      assembly.add_document(name, document)
    }
  }
  assembly.finish()
}

///|
/// The validation event ID of the IDL syntax diagnostic `code`, and how the
/// validation events report it.
fn syntax_event(code : String) -> (String, DiagnosticReport) {
  match code {
    // Smithy builds this event and then drops it (IdlModelLoader.java:415).
    "SM-PARSE-008" => ("Model.BadDocumentationComment", HintOnly)
    "SM-PARSE-009" => ("Model.BadDocumentationComment", Event)
    // Smithy stops before it reads these comments (IdlModelLoader.java:452).
    "SM-PARSE-016" => ("Model.BadDocumentationComment", HintOnly)
    _ => ("Model", Event)
  }
}

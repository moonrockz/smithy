///|
fn idl_keyword(shape : @syntax.Shape) -> String {
  match shape {
    Simple(kind~, ..) => kind.keyword()
    Enum(kind=Enum, ..) => "enum"
    Enum(kind=IntEnum, ..) => "intEnum"
    Aggregate(kind~, ..) =>
      match kind {
        List => "list"
        Set => "set"
        Map => "map"
        Structure => "structure"
        Union => "union"
      }
    Entity(kind=Service, ..) => "service"
    Entity(kind=Resource, ..) => "resource"
    Operation(..) => "operation"
  }
}

///|
fn suffix(file : @syntax.IdlFile, input : Bool) -> String {
  file
  .control_value(
    if input {
      "operationInputSuffix"
    } else {
      "operationOutputSuffix"
    },
  )
  .bind(v => v.as_string())
  .unwrap_or(if input { "Input" } else { "Output" })
}

///|
fn Assembly::collect_idl_names(
  self : Assembly,
  name : String,
  file : @syntax.IdlFile,
) -> Unit {
  let ns = file.namespace.map(n => n.namespace.value).unwrap_or("")
  for statement in file.shapes() {
    let id = ns + "#" + statement.shape.name().value
    self.known.add(id)
    self.kinds[id] = idl_keyword(statement.shape)
    if name == "<prelude>" &&
      !statement.traits.iter().any(t => t.id.value.name == "private") {
      self.public_prelude.add(id)
    }
    if statement.shape is Operation(properties~, ..) {
      for property in properties {
        match property {
          Input(Inline(_), _) => {
            let inline_id = id + suffix(file, true)
            self.known.add(inline_id)
            self.kinds[inline_id] = "structure"
          }
          Output(Inline(_), _) => {
            let inline_id = id + suffix(file, false)
            self.known.add(inline_id)
            self.kinds[inline_id] = "structure"
          }
          _ => ()
        }
      }
    }
  }
}

///|
fn Assembly::resolve(
  self : Assembly,
  id : @syntax.ShapeId,
  ns : String,
  uses : Map[String, String],
) -> String {
  let ns = if ns.is_empty() { "smithy.api" } else { ns }
  let root = match id.namespace {
    Some(namespace) => namespace + "#" + id.name
    None =>
      match uses.get(id.name) {
        Some(imported) => imported
        None => {
          let local = ns + "#" + id.name
          let builtin = "smithy.api#" + id.name
          if self.known.contains(local) {
            local
          } else if self.public_prelude.contains(builtin) {
            builtin
          } else {
            local
          }
        }
      }
  }
  match id.member {
    Some(member_) => root + "$" + member_
    None => root
  }
}

///|
fn Assembly::node_json(
  self : Assembly,
  node : @syntax.NodeValue,
  ns : String,
  uses : Map[String, String],
  source : SourceLocation,
) -> Json {
  match node {
    Array(values, _) =>
      Json::array(values.map(v => self.node_json(v, ns, uses, source)))
    Object(kvps, _) => {
      let fields : Map[String, Json] = Map([])
      for kvp in kvps {
        if fields.contains(kvp.key.value) {
          self.problem(
            "SM-MODEL-010",
            "I found the duplicate object property \{kvp.key.value}.",
            { ..source, span: Some(kvp.span), },
          )
        }
        fields[kvp.key.value] = self.node_json(kvp.value, ns, uses, source)
      }
      Json::object(fields)
    }
    String(s, _) | TextBlock(s, _) => Json::string(s)
    ShapeId(id, span) => {
      let target = self.resolve(id, ns, uses)
      self.syntactic.push((target, { ..source, span: Some(span), }))
      Json::string(target)
    }
    Number(number, _) => Json::number(number.as_double(), repr=number.text)
    Keyword(True, _) => Json::boolean(true)
    Keyword(False, _) => Json::boolean(false)
    Keyword(Null, _) => Json::null()
  }
}

///|
fn docs_text(docs : ArrayView[@syntax.DocComment]) -> String {
  let lines = docs.map(d => d.text)
  let mut indent = 2147483647
  for line in lines {
    if !line.trim().is_empty() {
      let trimmed = line.trim_start(chars=" \t")
      let count = line.length() - trimmed.length()
      if count < indent {
        indent = count
      }
    }
  }
  lines
  .map(line => {
    if indent < line.length() {
      line.unsafe_substring(start=indent, end=line.length())
    } else {
      ""
    }
  })
  .join("\n")
}

///|
fn Assembly::idl_traits(
  self : Assembly,
  traits : ArrayView[@syntax.Trait],
  docs : ArrayView[@syntax.DocComment],
  ns : String,
  uses : Map[String, String],
  source : SourceLocation,
  target : String,
) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  if !docs.is_empty() {
    out["smithy.api#documentation"] = Json::string(docs_text(docs))
  }
  for trait_ in traits {
    let id = self.resolve(trait_.id.value, ns, uses)
    let value = match trait_.body {
      Some(Node(node)) => self.node_json(node, ns, uses, source)
      Some(Structure(kvps)) if kvps.is_empty() => self.omitted_trait_value(id)
      Some(Structure(kvps)) =>
        self.node_json(
          @syntax.NodeValue::Object(kvps, trait_.span),
          ns,
          uses,
          source,
        )
      None => self.omitted_trait_value(id)
    }
    let incoming : Map[String, Json] = Map([])
    incoming[id] = value
    self.merge_traits(
      out,
      incoming,
      { ..source, span: Some(trait_.span), },
      target,
    )
  }
  out
}

///|
fn Assembly::omitted_trait_value(self : Assembly, id : String) -> Json {
  match self.kinds.get(id) {
    Some("list" | "set") => Json::array([])
    Some("structure" | "map") => Json::empty_object()
    _ => Json::null()
  }
}

///|
fn Assembly::idl_members(
  self : Assembly,
  members : ArrayView[@syntax.Member],
  parent : String,
  ns : String,
  uses : Map[String, String],
  source : SourceLocation,
) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for member_ in members {
    let id = parent + "$" + member_.name.value
    let source = { ..source, span: Some(member_.span), }
    self.locations[id] = source
    let fields : Map[String, Json] = Map([])
    if member_.target is Explicit(target) {
      fields["target"] = Json::string(self.resolve(target.value, ns, uses))
    }
    let traits = self.idl_traits(
      member_.traits,
      member_.docs,
      ns,
      uses,
      source,
      id,
    )
    if member_.default is Some(value) {
      let incoming : Map[String, Json] = {
        "smithy.api#default": self.node_json(value, ns, uses, source),
      }
      self.merge_traits(traits, incoming, source, id)
    }
    if !traits.is_empty() {
      fields["traits"] = Json::object(traits)
    }
    out[member_.name.value] = Json::object(fields)
  }
  out
}

///|
fn Assembly::idl_mixins(
  self : Assembly,
  fields : Map[String, Json],
  mixins : @syntax.Mixins?,
  ns : String,
  uses : Map[String, String],
) -> Unit {
  if mixins is Some(mixins) {
    fields["mixins"] = Json::array(
      mixins.ids.map(id => reference(self.resolve(id.value, ns, uses))),
    )
  }
}

///|
fn Assembly::idl_inline(
  self : Assembly,
  inline_ : @syntax.InlineShape,
  id : String,
  input : Bool,
  ns : String,
  uses : Map[String, String],
  source : SourceLocation,
) -> Unit {
  let fields : Map[String, Json] = {
    "type": "structure",
    "members": Json::object(
      self.idl_members(inline_.members, id, ns, uses, source),
    ),
  }
  let traits = self.idl_traits(
    inline_.traits,
    inline_.docs,
    ns,
    uses,
    source,
    id,
  )
  traits[if input { "smithy.api#input" } else { "smithy.api#output" }] = Json::empty_object()
  fields["traits"] = Json::object(traits)
  self.idl_mixins(fields, inline_.mixins, ns, uses)
  if inline_.for_resource is Some(resource) {
    self.bindings[id] = self.resolve(resource.value, ns, uses)
  }
  self.add_shape({
    id,
    fields,
    source: { ..source, span: Some(inline_.span), },
  })
}

///|
fn Assembly::add_idl(
  self : Assembly,
  name : String,
  file : @syntax.IdlFile,
) -> Unit {
  let ns = file.namespace.map(n => n.namespace.value).unwrap_or("")
  let source = location(name, span=file.span)
  let uses : Map[String, String] = Map([])
  let v2 = file
    .control_value("version")
    .bind(v => v.as_string())
    .unwrap_or("1")
    .has_prefix("2")
  for use_ in file.uses {
    let id = use_.id.value
    if id.namespace is None || id.member is Some(_) {
      self.problem(
        "SM-MODEL-002",
        "I expected an absolute root ID in a use statement, but found \{id}.",
        { ..source, span: Some(use_.span), },
      )
      continue
    }
    let imported = id.to_string()
    if uses.contains(id.name) ||
      (
        self.known.contains(ns + "#" + id.name) &&
        ns + "#" + id.name != imported
      ) {
      self.problem(
        "SM-MODEL-002",
        "I found the conflicting import name \{id.name}.",
        { ..source, span: Some(use_.span), },
      )
    }
    if !self.known.contains(imported) {
      self.problem(
        "SM-MODEL-004",
        "I could not resolve the imported shape \{imported}.",
        { ..source, span: Some(use_.span), },
      )
    }
    uses[id.name] = imported
  }
  for metadata in file.metadata {
    self.metadata_value(
      metadata.key.value,
      self.node_json(metadata.value, ns, uses, source),
      { ..source, span: Some(metadata.span), },
    )
  }
  for statement in file.statements {
    match statement {
      Apply(apply_) => {
        let target = self.resolve(apply_.target.value, ns, uses)
        if !v2 &&
          apply_.traits
          .iter()
          .any(t => self.resolve(t.id.value, ns, uses) == "smithy.api#mixin") {
          self.problem(
            "SM-MODEL-008",
            "I found a mixin trait application in a Smithy 1.0 document.",
            { ..source, span: Some(apply_.span), },
            shape=target,
          )
        }
        self.applications.push({
          target,
          traits: self.idl_traits(apply_.traits, [], ns, uses, source, target),
          source: { ..source, span: Some(apply_.span), },
        })
      }
      Shape(statement) => {
        let shape = statement.shape
        let id = ns + "#" + shape.name().value
        let source = { ..source, span: Some(statement.span), }
        let fields : Map[String, Json] = {
          "type": Json::string(idl_keyword(shape)),
        }
        let traits = self.idl_traits(
          statement.traits,
          statement.docs,
          ns,
          uses,
          source,
          id,
        )
        if !v2 && traits.contains("smithy.api#mixin") {
          self.problem(
            "SM-MODEL-008",
            "I found a mixin trait on \{id} in a Smithy 1.0 document.",
            source,
            shape=id,
          )
        }
        if !traits.is_empty() {
          fields["traits"] = Json::object(traits)
        }
        match shape {
          Simple(mixins~, ..) => self.idl_mixins(fields, mixins, ns, uses)
          Enum(mixins~, members~, ..) => {
            self.idl_mixins(fields, mixins, ns, uses)
            let ms : Map[String, Json] = Map([])
            for member_ in members {
              let mid = id + "$" + member_.name.value
              self.locations[mid] = { ..source, span: Some(member_.span), }
              let ts = self.idl_traits(
                member_.traits,
                member_.docs,
                ns,
                uses,
                source,
                mid,
              )
              if member_.value is Some(value) {
                self.merge_traits(
                  ts,
                  {
                    "smithy.api#enumValue": self.node_json(
                      value, ns, uses, source,
                    ),
                  },
                  source,
                  mid,
                )
              }
              let m : Map[String, Json] = { "target": "smithy.api#Unit" }
              if !ts.is_empty() {
                m["traits"] = Json::object(ts)
              }
              ms[member_.name.value] = Json::object(m)
            }
            fields["members"] = Json::object(ms)
          }
          Aggregate(kind~, for_resource~, mixins~, members~, ..) => {
            self.idl_mixins(fields, mixins, ns, uses)
            if for_resource is Some(resource) {
              self.bindings[id] = self.resolve(resource.value, ns, uses)
            }
            let ms = self.idl_members(members, id, ns, uses, source)
            match kind {
              List | Set | Map =>
                for key, member_ in ms {
                  fields[key] = member_
                }
              _ => fields["members"] = Json::object(ms)
            }
          }
          Entity(kind~, mixins~, body~, ..) => {
            self.idl_mixins(fields, mixins, ns, uses)
            let body = object(self.node_json(body, ns, uses, source))
            for key, value in body {
              let value = if [
                  "operations", "resources", "errors", "collectionOperations",
                ].contains(key) {
                match value {
                  Array(ids) =>
                    Json::array(
                      ids.map(v => {
                        match v {
                          String(id) => reference(id)
                          _ => v
                        }
                      }),
                    )
                  _ => value
                }
              } else if kind == Resource &&
                ["create", "put", "read", "update", "delete", "list"].contains(
                  key,
                ) {
                match value {
                  String(id) => reference(id)
                  _ => value
                }
              } else if kind == Resource &&
                ["identifiers", "properties"].contains(key) {
                let out : Map[String, Json] = Map([])
                match value {
                  Object(values) => {
                    for name, value in values {
                      out[name] = match value {
                        String(id) => reference(id)
                        _ => value
                      }
                    }
                    Json::object(out)
                  }
                  _ => value
                }
              } else {
                value
              }
              fields[key] = value
            }
          }
          Operation(mixins~, properties~, ..) => {
            self.idl_mixins(fields, mixins, ns, uses)
            for property in properties {
              match property {
                Input(target, _) | Output(target, _) => {
                  let input = property is Input(_, _)
                  let key = if input { "input" } else { "output" }
                  let target = match target {
                    Reference(target) => self.resolve(target.value, ns, uses)
                    Inline(inline_) => {
                      let target = id + suffix(file, input)
                      self.idl_inline(inline_, target, input, ns, uses, source)
                      target
                    }
                  }
                  fields[key] = reference(target)
                }
                Errors(errors, _) =>
                  fields["errors"] = Json::array(
                    errors.map(e => reference(self.resolve(e.value, ns, uses))),
                  )
              }
            }
          }
        }
        if idl_keyword(shape) == "set" &&
          file
          .control_value("version")
          .bind(v => v.as_string())
          .unwrap_or("1")
          .has_prefix("2") {
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
}

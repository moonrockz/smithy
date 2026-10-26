///|
priv struct GoContext {
  model : @smithy.Model
  description : @jsonrpc.Description
  selected : @jsonrpc.PeerSelection
  module_name : String
  package_name : String
  provider : @codegen.SymbolProvider
  shapes : Array[@smithy.ShapeId]
  values : Map[@smithy.ShapeId, @validation.StructureContract]
  timestamp_format : @validation.TimestampFormat
}

///|
fn exported(text : String) -> String {
  let out = StringBuilder()
  let mut upper = true
  let all_upper = text.to_array().all(c => !(c >= 'a' && c <= 'z'))
  for c in text.to_array() {
    if c == '_' {
      upper = true
      continue
    }
    if upper && c >= 'a' && c <= 'z' {
      out.write_char((c.to_int() - 32).unsafe_to_char())
    } else if !upper && all_upper && c >= 'A' && c <= 'Z' {
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
    upper = false
  }
  out.to_string()
}

///|
fn symbol(name : String, path~ : String = "") -> @codegen.Symbol {
  @codegen.Symbol::new(
    @codegen.SymbolName::parse(name).unwrap(),
    ns=if path == "" {
      @codegen.Namespace::root()
    } else {
      @codegen.Namespace::parse(path, separator="/").unwrap()
    },
  )
}

///|
fn GoContext::shape(
  self : GoContext,
  id : @smithy.ShapeId,
) -> @smithy.Shape raise @codegen.CodegenError {
  match self.model.shapes.get(id) {
    Some(shape) => shape
    None =>
      raise @codegen.StateError(
        "I could not find shape `\{id}` in the Go generator model.",
      )
  }
}

///|
fn GoContext::target(
  self : GoContext,
  id : @smithy.ShapeId,
) -> @smithy.ShapeId raise @codegen.CodegenError {
  match self.shape(id).body {
    Member(target~) => target
    _ =>
      raise @codegen.StateError(
        "I expected member shape `\{id}` in the Go generator model.",
      )
  }
}

///|
fn GoContext::type_symbol(
  self : GoContext,
  id : @smithy.ShapeId,
) -> @codegen.TemplateValue raise @codegen.CodegenError {
  let shape = self.value_shape(id)
  if shape.body is Simple(Timestamp) {
    let format = self.timestamp_format_for(id)
    if shape.id.namespace() == "smithy.api" ||
      format != self.timestamp_format_for(shape.id) {
      let type_ = primitive_symbol(
        Timestamp,
        self.module_name,
        timestamp_format=format,
      )
      return Call(w => w.write_inline("$T", args=[Sym(type_)]))
    }
  }
  if shape.id.namespace() == "smithy.api" {
    match shape.body {
      Simple(Blob) =>
        return Call(w => w.write_inline("[]$T", args=[Sym(symbol("byte"))]))
      Structure(_) => return Call(w => w.write_inline("struct{}"))
      _ => ()
    }
  }
  let type_ = self.provider.to_symbol(shape)
  Call(w => w.write_inline("$T", args=[Sym(type_)]))
}

///|
/// Resolve one member boundary. Semantic member targets are value shapes.
fn GoContext::value_shape(
  self : GoContext,
  id : @smithy.ShapeId,
) -> @smithy.Shape raise @codegen.CodegenError {
  let shape = self.shape(id)
  match shape.body {
    Member(target~) => self.shape(target)
    _ => shape
  }
}

///|
/// Core value directives use member, target, then prepared default precedence.
fn GoContext::timestamp_format_for(
  self : GoContext,
  id : @smithy.ShapeId,
) -> @validation.TimestampFormat raise @codegen.CodegenError {
  let source = self.shape(id)
  let target = self.value_shape(id)
  let trait_ = match source.trait_value("smithy.api#timestampFormat") {
    Some(value) => Some(value)
    None => target.trait_value("smithy.api#timestampFormat")
  }
  match trait_ {
    None => self.timestamp_format
    Some(String("date-time")) => @validation.DateTime
    Some(String("epoch-seconds")) => @validation.EpochSeconds
    _ =>
      raise @codegen.InvalidSettings(
        "I cannot map the JSON timestamp format of construct `\{id}` to a Go type.",
      )
  }
}

///|
fn GoContext::wire_name(self : GoContext, id : @smithy.ShapeId) -> String {
  for _, value in self.values {
    for member_ in value.members {
      if member_.shape == id {
        return member_.wire_name
      }
    }
  }
  id.member_name().unwrap_or(id.name())
}

///|
fn GoContext::field(
  self : GoContext,
  id : @smithy.ShapeId,
) -> String raise @codegen.CodegenError {
  self.provider.to_member_name(self.shape(id))
}

///|
fn GoContext::writer(
  self : GoContext,
) -> @codegen.CodeWriter raise @codegen.CodegenError {
  let writer = @codegen.CodeWriter::new(
    imports=@codegen.ImportPolicy::by_package(
      qualify=(prefix, sym) => prefix.to_string() + "." + sym.name.to_string(),
      qualifier=ns => {
        @codegen.SymbolName::parse(
          ns.text.split("/").to_array().last().unwrap().to_owned(),
        ).unwrap()
      },
      locals_block_qualifiers=true,
    ),
  )
  for id in self.shapes {
    if self.model.shapes.get(id) is Some(shape) &&
      !(shape.body is Member(..)) &&
      id.namespace() != "smithy.api" {
      let name = self.provider.to_symbol(shape).name.to_string()
      writer.reserve_name(@codegen.SymbolName::parse(name).unwrap())
    }
  }
  writer
}

///|
fn GoContext::render(self : GoContext, writer : @codegen.CodeWriter) -> String {
  let out = StringBuilder()
  out.write_string(
    "// Code generated by go-jsonrpc-codegen. DO NOT EDIT.\n\npackage \{self.package_name}\n",
  )
  let imports = writer.package_imports()
  if !imports.is_empty() {
    out.write_string("\nimport (\n")
    for entry in imports {
      out.write_string(
        "\t\{entry.qualifier.to_string()} \{quote(entry.ns.text)}\n",
      )
    }
    out.write_string(")\n")
  }
  out.write_char('\n')
  out.write_string(writer.to_string())
  out.to_string()
}

///|
fn quote(text : String) -> String {
  Json::string(text).stringify()
}

///|
fn create_context(
  model : @smithy.Model,
  description : @jsonrpc.Description,
  peer : @rpc.PeerName,
  module_name : String,
  package_name : String,
) -> GoContext raise @codegen.CodegenError {
  guard description.peer(peer) is Some(selected) else {
    raise @codegen.InvalidSettings(
      "I could not find peer `\{peer.to_string()}` in the prepared RPC description.",
    )
  }
  let services : Array[@smithy.ShapeId] = []
  let shape_set : Set[@smithy.ShapeId] = Set([])
  let values : Map[@smithy.ShapeId, @validation.StructureContract] = Map([])
  for peer in description.peers {
    if peer.accepts is Some(service) {
      services.push(service.service)
      for id in service.shapes {
        shape_set.add(id)
      }
      for value in service.values {
        if values.get(value.shape) is Some(previous) && previous != value {
          raise @codegen.InvalidSettings(
            "I found different prepared value policies for shape `\{value.shape}` in the Go peer.",
          )
        }
        values[value.shape] = value
      }
    }
  }
  let names = @codegen.ServiceNames::for_services(model, services)
  let timestamp_format = description.peers
    .iter()
    .find_first(p => p.accepts != None)
    .bind(p => p.accepts)
    .map(s => s.value_config.timestamp_format)
    .unwrap_or(@validation.EpochSeconds)
  let provider = @codegen.SymbolProvider::new(
    shape => {
      if shape.id.namespace() == "smithy.api" {
        match shape.body {
          Simple(kind) =>
            return primitive_symbol(kind, module_name, timestamp_format~)
          Structure(_) => return symbol("Unit")
          _ => ()
        }
      }
      let name = exported(names.shape_name(shape.id))
      if !go_identifier(name) {
        raise @codegen.InvalidSettings(
          "I could not use Go name `\{name}` for shape `\{shape.id}`.",
        )
      }
      symbol(name)
    },
    to_member_name=shape => {
      exported(shape.id.member_name().unwrap_or(shape.id.name()))
    },
  ).cached()
  let shapes = shape_set.to_array()
  shapes.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  let used : Map[String, @smithy.ShapeId] = Map([])
  for id in shapes {
    guard model.shapes.get(id) is Some(shape) &&
      !(shape.body is Member(..)) &&
      id.namespace() != "smithy.api" else {
      continue
    }
    let name = provider.to_symbol(shape).name.to_string()
    if ["Peer", "Handlers", "NewPeer", "Contract"].contains(name) ||
      used.contains(name) {
      raise @codegen.InvalidSettings(
        "I found a Go declaration name conflict for shape `\{id}` at `\{name}`.",
      )
    }
    used[name] = id
    let members = match shape.body {
      Structure(ids) | Union(ids) | Enum(ids) | IntEnum(ids) => ids
      _ => []
    }
    let fields : Set[String] = Set([])
    for member_ in members {
      let field = provider.to_member_name(model.shapes[member_])
      if !go_identifier(field) || fields.contains(field) {
        raise @codegen.InvalidSettings(
          "I found a Go member name conflict for member `\{member_}` at `\{field}`.",
        )
      }
      fields.add(field)
    }
  }
  {
    model,
    description,
    selected,
    module_name,
    package_name,
    provider,
    shapes,
    values,
    timestamp_format,
  }
}

///|
fn primitive_symbol(
  kind : @smithy.SimpleType,
  module_name : String,
  timestamp_format~ : @validation.TimestampFormat = @validation.EpochSeconds,
) -> @codegen.Symbol {
  match kind {
    Blob => symbol("byte")
    Boolean => symbol("bool")
    Document => symbol("RawMessage", path="encoding/json")
    String => symbol("string")
    Byte => symbol("int8")
    Short => symbol("int16")
    Integer => symbol("int32")
    Long => symbol("int64")
    Float => symbol("float32")
    Double => symbol("float64")
    BigInteger => symbol("Integer", path=module_name + "/rpc")
    BigDecimal => symbol("Number", path=module_name + "/rpc")
    Timestamp =>
      if timestamp_format == @validation.DateTime {
        symbol("string")
      } else {
        symbol("Number", path=module_name + "/rpc")
      }
  }
}

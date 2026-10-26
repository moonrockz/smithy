///|
/// The error contracts of the peer's services, one for each error shape, in the
/// order of the written error shapes.
fn Gen::error_contracts(self : Gen) -> Map[@smithy.ShapeId, @rpc.ErrorContract] {
  let found : Map[@smithy.ShapeId, @rpc.ErrorContract] = Map([])
  for service in [self.settings.peer.accepts, self.settings.peer.calls] {
    guard service is Some(description) else { continue }
    for method_ in description.methods {
      for error in method_.errors {
        if !found.contains(error.shape) {
          found[error.shape] = error
        }
      }
    }
  }
  found
}

///|
/// How the data of an error maps to its data model.
priv enum DataMapping {
  /// The data model is the data.
  Whole
  /// One member is the data.
  OneMember(Field)
  /// The error has no data.
  NoData
}

///|
fn Gen::data_mapping(
  self : Gen,
  error : @rpc.ErrorContract,
) -> DataMapping raise @codegen.CodegenError {
  let shape = self.shape(error.shape)
  let fields = self.fields(shape)
  match error.data {
    None => {
      if fields.iter().any(field => field.required) {
        raise @codegen.InvalidSettings(
          "I cannot decode error `\{error.shape}`: it has no data, but it has required members.",
        )
      }
      NoData
    }
    Some(target) if target == error.shape => Whole
    Some(target) => {
      let member_name = target.member_name().unwrap_or("")
      guard fields.iter().find_first(field => field.member_name == member_name)
        is Some(field) else {
        raise @codegen.InvalidSettings(
          "I could not find data member `\{target}` of error `\{error.shape}`.",
        )
      }
      if fields
        .iter()
        .any(other => other.required && other.member_name != member_name) {
        raise @codegen.InvalidSettings(
          "I cannot decode error `\{error.shape}`: its data is member `\{member_name}`, but other members are required.",
        )
      }
      OneMember(field)
    }
  }
}

///|
/// Write the data model of each error shape, and an exception class for each
/// modeled error, with its conversion to and from `RpcError`.
fn Gen::write_errors(self : Gen) -> Unit raise @codegen.CodegenError {
  if self.errors.is_empty() {
    return
  }
  let contracts = self.error_contracts()
  for id in self.errors {
    let shape = self.shape(id)
    let data_name = self.data_class_of(id)
    self.claim_name(data_name, id)
    let contract = contracts.get(id)
    let mapping = match contract {
      Some(contract) => Some(self.data_mapping(contract))
      None => None
    }
    let name = self.class_of(id)
    if contract is Some(_) {
      self.claim_name(name, id)
    }
    let all_optional = self.fields(shape).iter().all(field => !field.required)
    self.with_module(errors_module, self.errors_doc(), w => {
      self.write_model(w, data_name, shape, "The data of error `\{id}`.")
      guard contract is Some(contract) && mapping is Some(mapping) else {
        return
      }
      w.reserve_name(@codegen.SymbolName::parse(name).unwrap())
      let base = use_name(w, runtime_module, "ModeledError")
      let rpc_error = use_name(w, runtime_module, "RpcError")
      let json_value = use_name(w, runtime_module, "JsonValue")
      let message = py_string(self.names.shape_name(id))
      w.blank_line()
      w.blank_line()
      w.write("class $L($L):", args=[Text(name), Text(base)])
      w.indent()
      w.write("\"\"\"$L\"\"\"", args=[
        Text(
          doc_text(
            "The modeled error `\{id}`, with code \{contract.code.to_string()}.",
          ),
        ),
      ])
      w.blank_line()
      w.write("code = $L", args=[Text(contract.code.to_string())])
      w.blank_line()
      if all_optional {
        w.write("def __init__(self, data: $L | None = None) -> None:", args=[
          Text(data_name),
        ])
        w.indent()
        w.write("super().__init__($L)", args=[Text(message)])
        w.write("self.data = data if data is not None else $L()", args=[
          Text(data_name),
        ])
      } else {
        w.write("def __init__(self, data: $L) -> None:", args=[Text(data_name)])
        w.indent()
        w.write("super().__init__($L)", args=[Text(message)])
        w.write("self.data = data")
      }
      w.dedent()
      w.blank_line()
      w.write("def to_rpc_error(self) -> $L:", args=[Text(rpc_error)])
      w.indent()
      w.write(
        "\"\"\"Give the JSON-RPC error with the modeled code, message and data.\"\"\"",
      )
      match mapping {
        NoData =>
          w.write("return $L(self.code, str(self))", args=[Text(rpc_error)])
        Whole => {
          let to_wire = use_name(w, runtime_module, "to_wire")
          w.write("return $L(self.code, str(self), $L(self.data))", args=[
            Text(rpc_error),
            Text(to_wire),
          ])
        }
        OneMember(field) => {
          let to_wire = use_name(w, runtime_module, "to_wire")
          w.write("return $L(self.code, str(self), $L(self.data.$L))", args=[
            Text(rpc_error),
            Text(to_wire),
            Text(field.field_name),
          ])
        }
      }
      w.dedent()
      w.blank_line()
      w.write("@staticmethod")
      w.write("def from_data(data: $L | None) -> $L:", args=[
        Text(json_value),
        Text(name),
      ])
      w.indent()
      w.write(
        "\"\"\"Read the error from the data of an error response. Raises `ValueError` for other data.\"\"\"",
      )
      match mapping {
        NoData => {
          w.write("del data")
          w.write("return $L()", args=[Text(name)])
        }
        Whole =>
          w.write("return $L($L.model_validate(data))", args=[
            Text(name),
            Text(data_name),
          ])
        OneMember(field) => {
          let key = py_string(field.wire_name)
          let value = if field.required {
            "{\{key}: data}"
          } else {
            "{} if data is None else {\{key}: data}"
          }
          w.write("return $L($L.model_validate($L))", args=[
            Text(name),
            Text(data_name),
            Text(value),
          ])
        }
      }
      w.dedent()
      w.dedent()
    })
  }
}

///|
/// The handler and client method name of an operation.
fn Gen::method_of(self : Gen, operation : @smithy.ShapeId) -> String {
  method_name(self.names.shape_name(operation))
}

///|
/// The type of the result of a method: the output, the result member, or None.
fn Gen::result_ty(
  self : Gen,
  method_ : @rpc.MethodContract,
) -> Ty? raise @codegen.CodegenError {
  match method_.result {
    OutputStructure(id) if id == unit_id => None
    OutputStructure(id) => Some(self.named(id))
    OutputMember(member_id) => Some(self.member_ty(member_id))
    NullResult => None
  }
}

///|
/// Whether the result of a method is an empty object: an operation with no
/// output and no `nullResult`.
fn empty_result(method_ : @rpc.MethodContract) -> Bool {
  method_.result is OutputStructure(id) && id == unit_id
}

///|
fn has_input(method_ : @rpc.MethodContract) -> Bool {
  method_.input != unit_id
}

///|
/// The wire names of the positional members of a method, as a Python list.
fn Gen::positional_names(self : Gen, method_ : @rpc.MethodContract) -> String {
  let names = []
  let contract = self.values.get(method_.input)
  for member_id in method_.positional {
    let wire = contract
      .bind(c => c.members.iter().find_first(m => m.shape == member_id))
      .map(m => m.wire_name)
      .unwrap_or(member_id.member_name().unwrap_or(""))
    names.push(py_string(wire))
  }
  "[" + names.join(", ") + "]"
}

///|
fn kind_text(kind : @rpc.MethodKind) -> String {
  match kind {
    RequestOnly => "MethodKind.REQUEST_ONLY"
    NotificationOnly => "MethodKind.NOTIFICATION_ONLY"
    RequestOrNotification => "MethodKind.REQUEST_OR_NOTIFICATION"
  }
}

///|
/// Whether the method has a session rule that cancels a call of this peer.
/// The runtime handles such a method, so it has no handler.
fn Gen::cancels(self : Gen, method_ : @rpc.MethodContract) -> Bool {
  guard self.settings.description.session is Some(session) else { return false }
  session.methods
  .iter()
  .any(rule => {
    rule.receiver == self.settings.peer.name &&
    rule.method_name == method_.name &&
    rule.cancels is Some(_)
  })
}

///|
/// Raise when a shape already has the class name of a generated class.
fn Gen::check_generated_name(
  self : Gen,
  name : String,
  construct : String,
) -> Unit raise @codegen.CodegenError {
  if self.type_names.get(name) is Some(shape) {
    raise @codegen.InvalidSettings(
      "I cannot name the \{construct} `\{name}`: shape `\{shape}` has that Python class name.",
    )
  }
}

///|
/// Record a generated method name; raise when another operation has it.
fn claim_method(
  seen : Map[String, @smithy.ShapeId],
  name : String,
  operation : @smithy.ShapeId,
  construct : String,
) -> Unit raise @codegen.CodegenError {
  match seen.get(name) {
    Some(other) if other != operation =>
      raise @codegen.InvalidSettings(
        "I found operations `\{other}` and `\{operation}` with the same \{construct} method name `\{name}`.",
      )
    _ => seen[name] = operation
  }
}

///|
fn Gen::service_class(self : Gen, service : @smithy.ShapeId) -> String {
  class_name(self.names.shape_name(service))
}

///|
/// The expression that reads the params of a method as an object.
fn Gen::params_object(
  self : Gen,
  writer : @codegen.CodeWriter,
  method_ : @rpc.MethodContract,
) -> String {
  match method_.mode {
    Named => "\{use_name(writer, runtime_module, "named_params")}(params)"
    Positional =>
      "\{use_name(writer, runtime_module, "positional_params")}(params, \{self.positional_names(method_)}, either=False)"
    Either =>
      "\{use_name(writer, runtime_module, "positional_params")}(params, \{self.positional_names(method_)}, either=True)"
  }
}

///|
/// Write the handler protocol and the function that registers it on a peer.
fn Gen::write_handler(self : Gen) -> Unit raise @codegen.CodegenError {
  guard self.settings.peer.accepts is Some(description) else { return }
  let service = self.service_class(description.service)
  let protocol_name = service + "Handler"
  let methods = description.methods.filter(m => !self.cancels(m))
  self.check_generated_name(protocol_name, "handler protocol")
  let handler_methods : Map[String, @smithy.ShapeId] = Map([])
  for method_ in methods {
    claim_method(
      handler_methods,
      self.method_of(method_.operation),
      method_.operation,
      "handler",
    )
  }
  let doc = "The handler of service `\{description.service}` for peer `\{self.settings.peer.name.to_string()}`."
  self.with_module(".handler", doc, w => {
    let protocol = use_name(w, "typing", "Protocol")
    let context = use_name(w, runtime_module, "CallContext")
    w.reserve_name(@codegen.SymbolName::parse(protocol_name).unwrap())
    w.blank_line()
    w.blank_line()
    w.write("class $L($L):", args=[Text(protocol_name), Text(protocol)])
    w.indent()
    w.write("\"\"\"The handlers of service `$L`.", args=[
      Text(doc_text(description.service.to_string())),
    ])
    w.blank_line()
    w.write(
      "The generated code decodes the params, calls the handler and encodes the result.",
    )
    w.write("\"\"\"")
    for method_ in methods {
      let input = if has_input(method_) {
        ", input: \{use_ty(w, self.named(method_.input))}"
      } else {
        ""
      }
      let result = if method_.kind is NotificationOnly {
        "None"
      } else {
        match self.result_ty(method_) {
          Some(ty) => use_ty(w, ty)
          None => "None"
        }
      }
      w.blank_line()
      w.write("async def $L(self$L, context: $L) -> $L:", args=[
        Text(self.method_of(method_.operation)),
        Text(input),
        Text(context),
        Text(result),
      ])
      w.indent()
      w.write("\"\"\"Handle method `$L`.\"\"\"", args=[
        Text(doc_text(method_.name.to_string())),
      ])
      w.write("...")
      w.dedent()
    }
    w.dedent()
    let register = "register_" +
      snake_name(self.names.shape_name(description.service))
    let peer = use_name(w, runtime_module, "Peer")
    let json_value = use_name(w, runtime_module, "JsonValue")
    w.blank_line()
    w.blank_line()
    w.write("def $L(peer: $L, handler: $L) -> None:", args=[
      Text(register),
      Text(peer),
      Text(protocol_name),
    ])
    w.indent()
    w.write("\"\"\"Register the handlers of `$L` on a peer.\"\"\"", args=[
      Text(protocol_name),
    ])
    for method_ in description.methods {
      if method_.refers_to_call is Some(reference) {
        let position = match reference.position {
          Some(index) => index.to_string()
          None => "None"
        }
        w.write("peer.call_reference($L, id_member=$L, position=$L)", args=[
          Text(py_string(method_.name.to_string())),
          Text(py_string(reference.wire_name)),
          Text(position),
        ])
      }
    }
    if methods.length() > 0 {
      let _ = use_name(w, runtime_module, "MethodKind")
    }
    for method_ in methods {
      let notification = method_.kind is NotificationOnly
      let name = self.method_of(method_.operation)
      let inner = "_" + name
      let returns = if notification { "None" } else { json_value }
      w.blank_line()
      w.write("async def $L(params: $L | None, context: $L) -> $L:", args=[
        Text(inner),
        Text(json_value),
        Text(context),
        Text(returns),
      ])
      w.indent()
      let mut args = "context"
      if has_input(method_) {
        let input_name = use_ty(w, self.named(method_.input))
        w.write("input = $L.model_validate($L)", args=[
          Text(input_name),
          Text(self.params_object(w, method_)),
        ])
        args = "input, context"
      }
      let result = if notification { None } else { self.result_ty(method_) }
      let call = "await handler.\{name}(\{args})"
      let statement = if result is Some(_) { "result = \{call}" } else { call }
      if method_.errors.is_empty() {
        w.write("$L", args=[Text(statement)])
      } else {
        let modeled = use_name(w, runtime_module, "ModeledError")
        w.write("try:")
        w.indent()
        w.write("$L", args=[Text(statement)])
        w.dedent()
        w.write("except $L as error:", args=[Text(modeled)])
        w.indent()
        w.write("raise error.to_rpc_error() from error")
        w.dedent()
      }
      if !notification {
        if result is Some(_) {
          let to_wire = use_name(w, runtime_module, "to_wire")
          w.write("return $L(result)", args=[Text(to_wire)])
        } else if empty_result(method_) {
          w.write("return {}")
        } else {
          w.write("return None")
        }
      }
      w.dedent()
      w.blank_line()
      let register_fn = if notification {
        "on_notification"
      } else {
        "on_request"
      }
      w.write("peer.$L($L, $L, $L)", args=[
        Text(register_fn),
        Text(py_string(method_.name.to_string())),
        Text(kind_text(method_.kind)),
        Text(inner),
      ])
    }
    w.dedent()
  })
}

///|
/// Write the typed client of the service that the peer calls.
fn Gen::write_client(self : Gen) -> Unit raise @codegen.CodegenError {
  guard self.settings.peer.calls is Some(description) else { return }
  let client = self.service_class(description.service) + "Client"
  self.check_generated_name(client, "client class")
  let client_methods : Map[String, @smithy.ShapeId] = Map([])
  for method_ in description.methods {
    let name = self.method_of(method_.operation)
    if !(method_.kind is RequestOnly) {
      let fn_name = if method_.kind is NotificationOnly {
        name
      } else {
        name + "_notification"
      }
      claim_method(client_methods, fn_name, method_.operation, "client")
    }
    if !(method_.kind is NotificationOnly) {
      claim_method(client_methods, name, method_.operation, "client")
    }
  }
  let doc = "The client of service `\{description.service}` for peer `\{self.settings.peer.name.to_string()}`."
  self.with_module(".client", doc, w => {
    w.reserve_name(@codegen.SymbolName::parse(client).unwrap())
    let peer = use_name(w, runtime_module, "Peer")
    // The type adapters of the result members, before the class.
    let adapters : Map[String, String] = Map([])
    for method_ in description.methods {
      if method_.kind is NotificationOnly {
        continue
      }
      if method_.result is OutputMember(member_id) {
        let ty = self.member_ty(member_id)
        let text = use_ty(w, ty)
        let adapter = use_name(w, "pydantic", "TypeAdapter")
        let constant = "_" +
          self.method_of(method_.operation).to_upper() +
          "_RESULT"
        adapters[method_.name.to_string()] = constant
        w.blank_line()
        w.write("$L: $L[$L] = $L($L)", args=[
          Text(constant),
          Text(adapter),
          Text(text),
          Text(adapter),
          Text(text),
        ])
      }
    }
    w.blank_line()
    w.blank_line()
    w.write("class $L:", args=[Text(client)])
    w.indent()
    w.write("\"\"\"A typed client of service `$L`.", args=[
      Text(doc_text(description.service.to_string())),
    ])
    w.blank_line()
    w.write(
      "With `checked=True`, the peer refuses a call that the session rules do not allow,",
    )
    w.write("and sends nothing.")
    w.write("\"\"\"")
    w.blank_line()
    w.write("def __init__(self, peer: $L) -> None:", args=[Text(peer)])
    w.indent()
    w.write("self.peer = peer")
    w.dedent()
    for method_ in description.methods {
      let name = self.method_of(method_.operation)
      let input_param = if has_input(method_) {
        "input: \{use_ty(w, self.named(method_.input))}, "
      } else {
        ""
      }
      let params = if has_input(method_) {
        match method_.mode {
          Named | Either => "\{use_name(w, runtime_module, "to_wire")}(input)"
          Positional =>
            "\{use_name(w, runtime_module, "to_positional")}(\{use_name(w, runtime_module, "to_wire_object")}(input), \{self.positional_names(method_)})"
        }
      } else {
        "None"
      }
      let wire = py_string(method_.name.to_string())
      if !(method_.kind is RequestOnly) {
        let fn_name = if method_.kind is NotificationOnly {
          name
        } else {
          name + "_notification"
        }
        w.blank_line()
        w.write("async def $L(self, $L*, checked: bool = True) -> None:", args=[
          Text(fn_name),
          Text(input_param),
        ])
        w.indent()
        w.write("\"\"\"Send notification `$L`.\"\"\"", args=[
          Text(doc_text(method_.name.to_string())),
        ])
        w.write("await self.peer.notify($L, $L, checked=checked)", args=[
          Text(wire),
          Text(params),
        ])
        w.dedent()
      }
      if method_.kind is NotificationOnly {
        continue
      }
      let result = self.result_ty(method_)
      let result_text = match result {
        Some(ty) => use_ty(w, ty)
        None => "None"
      }
      w.blank_line()
      w.write("async def $L(self, $L*, checked: bool = True) -> $L:", args=[
        Text(name),
        Text(input_param),
        Text(result_text),
      ])
      w.indent()
      w.write("\"\"\"Call method `$L`.\"\"\"", args=[
        Text(doc_text(method_.name.to_string())),
      ])
      let call = "await self.peer.request(\{wire}, \{params}, checked=checked)"
      let statement = if result is Some(_) { "result = \{call}" } else { call }
      if method_.errors.is_empty() {
        w.write("$L", args=[Text(statement)])
      } else {
        let rpc_error = use_name(w, runtime_module, "RpcError")
        let modeled = use_name(w, runtime_module, "modeled_error")
        let decoders = method_.errors
          .map(error => {
            let exception = use_name(
              w,
              errors_module,
              self.class_of(error.shape),
            )
            "\{error.code.to_string()}: \{exception}.from_data"
          })
          .join(", ")
        w.write("try:")
        w.indent()
        w.write("$L", args=[Text(statement)])
        w.dedent()
        w.write("except $L as error:", args=[Text(rpc_error)])
        w.indent()
        w.write("raise $L(error, {$L}) from None", args=[
          Text(modeled),
          Text(decoders),
        ])
        w.dedent()
      }
      match method_.result {
        NullResult => ()
        OutputStructure(id) if id == unit_id => ()
        OutputStructure(_) =>
          w.write("return $L.model_validate(result)", args=[Text(result_text)])
        OutputMember(_) =>
          w.write("return $L.validate_python(result)", args=[
            Text(adapters.get(method_.name.to_string()).unwrap_or("")),
          ])
      }
      w.dedent()
    }
    w.dedent()
  })
}

///|
/// Write the session rules and the constructor of a peer.
fn Gen::write_session(self : Gen) -> Unit raise @codegen.CodegenError {
  let peer_name = self.settings.peer.name.to_string()
  let remote = self.settings.description.peers
    .iter()
    .find_first(peer => peer.name != self.settings.peer.name)
    .map(peer => peer.name.to_string())
    .unwrap_or("")
  let doc = "The session rules of the protocol, and the constructor of peer `\{peer_name}`."
  self.with_module(".session", doc, w => {
    let rules_type = use_name(w, runtime_module, "SessionRules")
    w.blank_line()
    w.blank_line()
    w.write("def session_rules() -> $L:", args=[Text(rules_type)])
    w.indent()
    w.write(
      "\"\"\"The session rules of the protocol, from the prepared contract.\"\"\"",
    )
    match self.settings.description.session {
      None => w.write("return $L.none()", args=[Text(rules_type)])
      Some(session) => {
        w.write("return $L(", args=[Text(rules_type)])
        w.indent()
        let states = session.states
          .map(state => py_string(state.to_string()))
          .join(", ")
        w.write("states=[$L],", args=[Text(states)])
        if !session.capabilities.is_empty() {
          let source = use_name(w, runtime_module, "CapabilitySource")
          w.write("capabilities=[")
          w.indent()
          for capability in session.capabilities {
            w.write("$L($L, $L, $L),", args=[
              Text(source),
              Text(py_string(capability.name)),
              Text(py_string(capability.method_name.to_string())),
              Text(py_string(capability.pointer.to_string())),
            ])
          }
          w.dedent()
          w.write("],")
        }
        if !session.methods.is_empty() {
          let method_rule = use_name(w, runtime_module, "MethodRule")
          w.write("methods=[")
          w.indent()
          for rule in session.methods {
            let parts = [
              py_string(rule.receiver.to_string()),
              py_string(rule.method_name.to_string()),
            ]
            if rule.allowed is Some(states) {
              let text = states
                .map(state => py_string(state.to_string()))
                .join(", ")
              parts.push("allowed=[\{text}]")
            }
            if rule.on_call is Some(state) {
              parts.push("on_call=\{py_string(state.to_string())}")
            }
            if rule.on_success is Some(state) {
              parts.push("on_success=\{py_string(state.to_string())}")
            }
            if rule.on_error is Some(state) {
              parts.push("on_error=\{py_string(state.to_string())}")
            }
            if !rule.requires.is_empty() {
              parts.push(
                "requires=[\{rule.requires.map(py_string).join(", ")}]",
              )
            }
            if rule.cancels is Some(cancel) {
              let cancel_rule = use_name(w, runtime_module, "CancelRule")
              let position = match cancel.position {
                Some(index) => index.to_string()
                None => "None"
              }
              let code = match cancel.code {
                Some(code) => code.to_string()
                None => "None"
              }
              parts.push(
                "cancels=\{cancel_rule}(\{py_string(cancel.wire_name)}, position=\{position}, code=\{code})",
              )
            }
            w.write("$L(", args=[Text(method_rule)])
            w.indent()
            for part in parts {
              w.write("$L,", args=[Text(part)])
            }
            w.dedent()
            w.write("),")
          }
          w.dedent()
          w.write("],")
        }
        if !session.refusals.is_empty() {
          let refusals = session.refusals
            .map(refusal => {
              "(\{py_string(refusal.state.to_string())}, \{refusal.code.to_string()})"
            })
            .join(", ")
          w.write("refusals=[$L],", args=[Text(refusals)])
        }
        if session.capability_refusal is Some(code) {
          w.write("capability_refusal=$L,", args=[Text(code.to_string())])
        }
        w.dedent()
        w.write(")")
      }
    }
    w.dedent()
    let peer = use_name(w, runtime_module, "Peer")
    let log = use_name(w, runtime_module, "TranscriptLog")
    w.blank_line()
    w.blank_line()
    w.write("def new_peer(log: $L | None = None) -> $L:", args=[
      Text(log),
      Text(peer),
    ])
    w.indent()
    w.write(
      "\"\"\"A peer `$L` that talks to peer `$L`, with the session rules.\"\"\"",
      args=[Text(doc_text(peer_name)), Text(doc_text(remote))],
    )
    w.write(
      "return $L(self_name=$L, remote_name=$L, rules=session_rules(), log=log)",
      args=[Text(peer), Text(py_string(peer_name)), Text(py_string(remote))],
    )
    w.dedent()
  })
}

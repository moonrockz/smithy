///|
/// The name of the error type that holds the modeled errors of the peer.
let service_error_name : String = "ServiceError"

///|
fn Gen::int_code(
  self : Gen,
  code : @rpc.ErrorCode,
  owner : @smithy.ShapeId,
) -> String raise @codegen.CodegenError {
  ignore(self)
  let text = code.to_string()
  if !fits_int(text) {
    raise @codegen.InvalidSettings(
      "I expected the error code \{text} of `\{owner}` to fit in a MoonBit Int.",
    )
  }
  text
}

///|
/// Whether integer text fits in a 32-bit signed integer.
fn fits_int(text : String) -> Bool {
  let digits = if text.has_prefix("-") {
    text.length() - 1
  } else {
    text.length()
  }
  if digits < 1 || digits > 10 {
    return false
  }
  let mut value = 0L
  for c in text {
    if c == '-' {
      continue
    }
    if !c.is_ascii_digit() {
      return false
    }
    value = value * 10L + (c.to_int() - '0'.to_int()).to_int64()
  }
  let limit = if text.has_prefix("-") { 2147483648L } else { 2147483647L }
  value <= limit
}

///|
/// The error contracts of the peer's services, one for each error shape, in the
/// order of the written error shapes.
fn Gen::error_contracts(self : Gen) -> Array[@rpc.ErrorContract] {
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
  self.errors.filter_map(id => found.get(id))
}

///|
/// How the data of an error maps to its structure, for the generated code.
priv enum DataMapping {
  /// The structure is the data.
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
      let field_name = snake_name(member_name)
      guard fields.iter().find_first(field => field.field_name == field_name)
        is Some(field) else {
        raise @codegen.InvalidSettings(
          "I could not find data member `\{target}` of error `\{error.shape}`.",
        )
      }
      if fields
        .iter()
        .any(other => other.required && other.field_name != field_name) {
        raise @codegen.InvalidSettings(
          "I cannot decode error `\{error.shape}`: its data is member `\{member_name}`, but other members are required.",
        )
      }
      OneMember(field)
    }
  }
}

///|
/// The struct literal of an error. Each optional field is `None`, except the
/// data member, which gets its decoded value.
fn Gen::error_literal(
  self : Gen,
  shape : @smithy.ShapeId,
  data : (String, String)?,
) -> String raise @codegen.CodegenError {
  let name = self.type_name_of(shape)
  let fields = self.fields(self.shape(shape))
  if fields.is_empty() {
    return "\{name}::{  }"
  }
  let parts = fields.map(field => {
    match data {
      Some((data_field, value)) if data_field == field.field_name =>
        "\{field.field_name}: \{value}"
      _ => "\{field.field_name}: None"
    }
  })
  "\{name}::{ \{parts.join(", ")} }"
}

///|
/// Write the error type, the conversion to `@rpc.RpcError` and the decoders.
fn Gen::write_errors(self : Gen) -> Unit raise @codegen.CodegenError {
  let contracts = self.error_contracts()
  if contracts.is_empty() {
    return
  }
  let mappings = contracts.map(contract => {
    (contract, self.data_mapping(contract))
  })
  let accepts_errors = match self.settings.peer.accepts {
    Some(description) =>
      description.methods.iter().any(m => !m.errors.is_empty())
    None => false
  }
  let called_errors : Array[@smithy.ShapeId] = []
  if self.settings.peer.calls is Some(description) {
    for method_ in description.methods {
      for error in method_.errors {
        if !called_errors.contains(error.shape) {
          called_errors.push(error.shape)
        }
      }
    }
  }
  let calls_errors = match self.settings.peer.calls {
    Some(description) =>
      description.methods.iter().any(m => !m.errors.is_empty())
    None => false
  }
  let codes = contracts.map(contract => {
    self.int_code(contract.code, contract.shape)
  })
  self.with_file(errors_path(), w => {
    w.write("///|")
    w.write(
      "/// The modeled errors of the services. A handler raises one of them;",
    )
    w.write(
      "/// a client call raises one of them for a modeled error response.",
    )
    w.write("pub(all) suberror $L {", args=[Text(service_error_name)])
    w.indent()
    for contract in contracts {
      let name = self.type_name_of(contract.shape)
      w.write("$L($L)", args=[Text(name), Text(name)])
    }
    w.dedent()
    w.write("}")
    w.blank_line()
    if accepts_errors {
      w.write("///|")
      w.write(
        "/// The response error of a modeled error, with its modeled code and data.",
      )
      w.write("fn to_rpc_error(error : Error) -> Error {")
      w.indent()
      w.write("match error {")
      w.indent()
      for index, entry in mappings {
        let (contract, mapping) = entry
        let name = self.type_name_of(contract.shape)
        let message = mbt_string(self.names.shape_name(contract.shape))
        let (binder, data) = match mapping {
          Whole => ("value", "Some(value.to_json())")
          OneMember(field) => {
            let expr = "value." + field.field_name
            let data = if field.required {
              "Some(\{field.ty.encode(expr)})"
            } else {
              "\{expr}.map(item => \{field.ty.encode("item")})"
            }
            ("value", data)
          }
          NoData => ("_", "None")
        }
        w.write("$L::$L($L) =>", args=[
          Text(service_error_name),
          Text(name),
          Text(binder),
        ])
        w.indent()
        w.write("@rpc.RpcError(code=$L, message=$L, data=$L)", args=[
          Text(codes[index]),
          Text(message),
          Text(data),
        ])
        w.dedent()
      }
      w.write("other => other")
      w.dedent()
      w.write("}")
      w.dedent()
      w.write("}")
      w.blank_line()
    }
    if calls_errors {
      for entry in mappings {
        let (contract, mapping) = entry
        let name = self.type_name_of(contract.shape)
        // An error without data needs no decoder: the client builds it inline.
        // A decoder is only for an error of the service that the peer calls.
        if mapping is NoData || !called_errors.contains(contract.shape) {
          continue
        }
        w.write("///|")
        w.write(
          "fn $L_from_data(data : Json?) -> Error raise @rpc.DecodeError {",
          args=[Text(snake_name(self.names.shape_name(contract.shape)))],
        )
        w.indent()
        let value = match mapping {
          Whole =>
            "\{name}::from_json(data.unwrap_or(Json::null()), path=\"/error/data\")"
          NoData => ""
          OneMember(field) => {
            let decoded = if field.required {
              field.ty.decode("data.unwrap_or(Json::null())", "\"/error/data\"")
            } else {
              "match data { None | Some(Null) => None; Some(item) => Some(\{field.ty.decode("item", "\"/error/data\"")}) }"
            }
            self.error_literal(
              contract.shape,
              Some((field.field_name, decoded)),
            )
          }
        }
        w.write("$L::$L($L)", args=[
          Text(service_error_name),
          Text(name),
          Text(value),
        ])
        w.dedent()
        w.write("}")
        w.blank_line()
      }
      w.write("///|")
      w.write(
        "/// The modeled error of an error response, or the error itself.",
      )
      w.write("fn modeled_error(")
      w.indent()
      w.write("error : Error,")
      w.write(
        "decoders : Array[(Int, (Json?) -> Error raise @rpc.DecodeError)],",
      )
      w.dedent()
      w.write(") -> Error {")
      w.indent()
      w.write(
        "guard error is @rpc.RpcError(code~, data~, ..) else { return error }",
      )
      w.write("for decoder in decoders {")
      w.indent()
      w.write("if decoder.0 == code {")
      w.indent()
      w.write("return (decoder.1)(data) catch { _ => error }")
      w.dedent()
      w.write("}")
      w.dedent()
      w.write("}")
      w.write("error")
      w.dedent()
      w.write("}")
      w.blank_line()
    }
  })
}

///|
/// The handler method name of an operation.
fn Gen::method_name(self : Gen, operation : @smithy.ShapeId) -> String {
  snake_name(self.names.shape_name(operation))
}

///|
/// The type of the result of a method: the output, the result member or Unit.
fn Gen::result_ty(
  self : Gen,
  method_ : @rpc.MethodContract,
) -> Ty raise @codegen.CodegenError {
  match method_.result {
    // An operation without output answers an empty object.
    OutputStructure(id) if id == unit_id => UnitT
    OutputStructure(id) => Named(self.type_name_of(id))
    OutputMember(member_id) => self.member_ty(member_id)
    NullResult => UnitT
  }
}

///|
fn has_input(method_ : @rpc.MethodContract) -> Bool {
  method_.input != unit_id
}

///|
/// The wire names of the positional members of a method, in order.
fn Gen::positional_names(self : Gen, method_ : @rpc.MethodContract) -> String {
  let names = []
  let contract = self.values.get(method_.input)
  for member_id in method_.positional {
    let wire = contract
      .bind(c => c.members.iter().find_first(m => m.shape == member_id))
      .map(m => m.wire_name)
      .unwrap_or(member_id.member_name().unwrap_or(""))
    names.push(mbt_string(wire))
  }
  "[" + names.join(", ") + "]"
}

///|
fn kind_text(kind : @rpc.MethodKind) -> String {
  match kind {
    RequestOnly => "@rpc.RequestOnly"
    NotificationOnly => "@rpc.NotificationOnly"
    RequestOrNotification => "@rpc.RequestOrNotification"
  }
}

///|
/// The session rule of a method that this peer receives, when it cancels.
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
fn Gen::service_type_name(self : Gen, service : @smithy.ShapeId) -> String {
  type_name(self.names.shape_name(service))
}

///|
/// Write the handler trait and the function that registers it on a peer.
fn Gen::write_handler(self : Gen) -> Unit raise @codegen.CodegenError {
  guard self.settings.peer.accepts is Some(description) else { return }
  let service = self.service_type_name(description.service)
  let trait_name = service + "Handler"
  let methods = description.methods.filter(m => !self.cancels(m))
  let with_errors = description.methods.iter().any(m => !m.errors.is_empty())
  let path = @codegen.OutputPath::parse("handler.mbt").unwrap()
  self.with_file(path, w => {
    w.write("///|")
    w.write(
      "/// The handlers of service `$L`. The generated code decodes the",
      args=[Text(description.service.to_string())],
    )
    w.write("/// parameters, calls the handler and encodes the result.")
    w.write("pub(open) trait $L {", args=[Text(trait_name)])
    w.indent()
    let used : Map[String, String] = Map([])
    for method_ in methods {
      let handler_name = self.method_name(method_.operation)
      if used.get(handler_name) is Some(other) {
        raise @codegen.InvalidSettings(
          "I found methods `\{other}` and `\{method_.name.to_string()}` with the same MoonBit handler method name `\{handler_name}`.",
        )
      }
      used[handler_name] = method_.name.to_string()
    }
    for method_ in methods {
      let input = if has_input(method_) {
        ", " + self.type_name_of(method_.input)
      } else {
        ""
      }
      let result = if method_.kind is NotificationOnly {
        "Unit"
      } else {
        self.result_ty(method_).text()
      }
      w.write("async $L(Self$L, @rpc.CallContext) -> $L raise", args=[
        Text(self.method_name(method_.operation)),
        Text(input),
        Text(result),
      ])
    }
    w.dedent()
    w.write("}")
    w.blank_line()
    w.write("///|")
    w.write("/// Register the handlers of `$L` on a peer.", args=[
      Text(trait_name),
    ])
    let register = "register_" +
      snake_name(self.names.shape_name(description.service))
    w.write("pub fn $L(peer : @rpc.Peer, handler : &$L) -> Unit {", args=[
      Text(register),
      Text(trait_name),
    ])
    w.indent()
    for method_ in description.methods {
      if method_.refers_to_call is Some(reference) {
        let position = match reference.position {
          Some(index) => "Some(\{index})"
          None => "None"
        }
        w.write("peer.call_reference($L, id_member=$L, position=$L)", args=[
          Text(mbt_string(method_.name.to_string())),
          Text(mbt_string(reference.wire_name)),
          Text(position),
        ])
      }
    }
    for method_ in methods {
      let notification = method_.kind is NotificationOnly
      let register_fn = if notification {
        "on_notification"
      } else {
        "on_request"
      }
      let params = if has_input(method_) { "params" } else { "_params" }
      w.write("peer.$L($L, $L, async fn($L, context) {", args=[
        Text(register_fn),
        Text(mbt_string(method_.name.to_string())),
        Text(kind_text(method_.kind)),
        Text(params),
      ])
      w.indent()
      let mut args = "context"
      if has_input(method_) {
        let input_name = self.type_name_of(method_.input)
        let params_expr = match method_.mode {
          Named => "@rpc.named_params(params, path=\"/params\")"
          Positional =>
            "@rpc.positional_params(params, \{self.positional_names(method_)}, either=false, path=\"/params\")"
          Either =>
            "@rpc.positional_params(params, \{self.positional_names(method_)}, either=true, path=\"/params\")"
        }
        w.write("let input = $L::from_json($L, path=\"/params\")", args=[
          Text(input_name),
          Text(params_expr),
        ])
        args = "input, context"
      }
      let call = "handler.\{self.method_name(method_.operation)}(\{args})"
      let call = if with_errors && !method_.errors.is_empty() {
        "\{call} catch { error => raise to_rpc_error(error) }"
      } else {
        call
      }
      if notification {
        w.write("$L", args=[Text(call)])
      } else {
        let result = self.result_ty(method_)
        if result is UnitT {
          w.write("$L", args=[Text(call)])
          if method_.result is NullResult {
            w.write("Json::null()")
          } else {
            w.write("Json::empty_object()")
          }
        } else {
          w.write("let result = $L", args=[Text(call)])
          w.write("$L", args=[Text(result.encode("result"))])
        }
      }
      w.dedent()
      w.write("})")
    }
    w.dedent()
    w.write("}")
    w.blank_line()
  })
}

///|
/// Write the typed client of the service that the peer calls.
fn Gen::write_client(self : Gen) -> Unit raise @codegen.CodegenError {
  guard self.settings.peer.calls is Some(description) else { return }
  let client = self.service_type_name(description.service) + "Client"
  let path = @codegen.OutputPath::parse("client.mbt").unwrap()
  self.with_file(path, w => {
    w.write("///|")
    w.write(
      "/// A typed client of service `$L`. With `checked=true`, the peer",
      args=[Text(description.service.to_string())],
    )
    w.write(
      "/// refuses a call that the session rules do not allow, and sends nothing.",
    )
    w.write("pub struct $L {", args=[Text(client)])
    w.indent()
    w.write("peer : @rpc.Peer")
    w.dedent()
    w.write("}")
    w.blank_line()
    w.write("///|")
    w.write("pub fn $L::new(peer : @rpc.Peer) -> $L {", args=[
      Text(client),
      Text(client),
    ])
    w.indent()
    w.write("$L::{ peer, }", args=[Text(client)])
    w.dedent()
    w.write("}")
    w.blank_line()
    // `new` is the constructor of the client; a method named so gets a suffix.
    let used : Map[String, String] = Map([])
    let claim = (fn_name : String, method_ : @rpc.MethodContract) => {
      if used.get(fn_name) is Some(other) {
        raise @codegen.InvalidSettings(
          "I found methods `\{other}` and `\{method_.name.to_string()}` with the same MoonBit client method name `\{fn_name}`.",
        )
      }
      used[fn_name] = method_.name.to_string()
    }
    for method_ in description.methods {
      let name = match self.method_name(method_.operation) {
        "new" => "new_"
        other => other
      }
      if !(method_.kind is NotificationOnly) {
        claim(name, method_)
      }
      if !(method_.kind is RequestOnly) {
        claim(
          if method_.kind is NotificationOnly {
            name
          } else {
            name + "_notification"
          },
          method_,
        )
      }
      let input_param = if has_input(method_) {
        "input : \{self.type_name_of(method_.input)}, "
      } else {
        ""
      }
      let params = if has_input(method_) {
        match method_.mode {
          Named | Either => "Some(input.to_json())"
          Positional =>
            "Some(@rpc.to_positional(input.to_json(), \{self.positional_names(method_)}))"
        }
      } else {
        "None"
      }
      let wire = mbt_string(method_.name.to_string())
      if !(method_.kind is RequestOnly) {
        let fn_name = if method_.kind is NotificationOnly {
          name
        } else {
          name + "_notification"
        }
        w.write("///|")
        w.write(
          "pub async fn $L::$L(self : $L, $Lchecked~ : Bool = true) -> Unit raise {",
          args=[Text(client), Text(fn_name), Text(client), Text(input_param)],
        )
        w.indent()
        w.write("self.peer.notify($L, $L, checked~)", args=[
          Text(wire),
          Text(params),
        ])
        w.dedent()
        w.write("}")
        w.blank_line()
      }
      if method_.kind is NotificationOnly {
        continue
      }
      let result = self.result_ty(method_)
      w.write("///|")
      w.write(
        "pub async fn $L::$L(self : $L, $Lchecked~ : Bool = true) -> $L raise {",
        args=[
          Text(client),
          Text(name),
          Text(client),
          Text(input_param),
          Text(result.text()),
        ],
      )
      w.indent()
      let request = "self.peer.request(\{wire}, \{params}, checked~)"
      let request = if method_.errors.is_empty() {
        request
      } else {
        let decoders = []
        for error in method_.errors {
          let decoder = if error.data is None {
            let name = self.type_name_of(error.shape)
            "_ => \{service_error_name}::\{name}(\{self.error_literal(error.shape, None)})"
          } else {
            "\{snake_name(self.names.shape_name(error.shape))}_from_data"
          }
          decoders.push("(\{error.code.to_string()}, \{decoder})")
        }
        let decoders = decoders.join(", ")
        "\{request} catch { error => raise modeled_error(error, [\{decoders}]) }"
      }
      if result is UnitT {
        w.write("let _ = $L", args=[Text(request)])
      } else {
        w.write("let result = $L", args=[Text(request)])
        w.write("$L", args=[Text(result.decode("result", "\"/result\""))])
      }
      w.dedent()
      w.write("}")
      w.blank_line()
    }
  })
}

///|
fn option_text(value : String?) -> String {
  match value {
    Some(text) => "Some(\{mbt_string(text)})"
    None => "None"
  }
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
  let path = @codegen.OutputPath::parse("session.mbt").unwrap()
  self.with_file(path, w => {
    w.write("///|")
    w.write(
      "/// The session rules of the protocol, from the prepared contract.",
    )
    w.write("pub fn session_rules() -> @rpc.SessionRules {")
    w.indent()
    match self.settings.description.session {
      None => w.write("@rpc.SessionRules::none()")
      Some(session) => {
        w.write("@rpc.SessionRules::new(")
        w.indent()
        let states = session.states
          .map(state => mbt_string(state.to_string()))
          .join(", ")
        w.write("states=[$L],", args=[Text(states)])
        w.write("capabilities=[")
        w.indent()
        for capability in session.capabilities {
          w.write(
            "@rpc.CapabilitySource::new(name=$L, method_name=$L, pointer=$L),",
            args=[
              Text(mbt_string(capability.name)),
              Text(mbt_string(capability.method_name.to_string())),
              Text(mbt_string(capability.pointer.to_string())),
            ],
          )
        }
        w.dedent()
        w.write("],")
        w.write("methods=[")
        w.indent()
        for rule in session.methods {
          let allowed = match rule.allowed {
            Some(states) =>
              "Some([" +
              states.map(state => mbt_string(state.to_string())).join(", ") +
              "])"
            None => "None"
          }
          let requires = rule.requires.map(mbt_string).join(", ")
          let cancels = match rule.cancels {
            Some(cancel) => {
              let position = match cancel.position {
                Some(index) => "Some(\{index})"
                None => "None"
              }
              let code = match cancel.code {
                Some(code) =>
                  "Some(\{self.int_code(code, @smithy.ShapeId::parse("smithy.rpc#jsonRpcCancels").unwrap())})"
                None => "None"
              }
              "Some(@rpc.CancelRule::new(id_member=\{mbt_string(cancel.wire_name)}, position=\{position}, code=\{code}))"
            }
            None => "None"
          }
          w.write("@rpc.MethodRule::new(")
          w.indent()
          w.write("receiver=$L,", args=[
            Text(mbt_string(rule.receiver.to_string())),
          ])
          w.write("method_name=$L,", args=[
            Text(mbt_string(rule.method_name.to_string())),
          ])
          w.write("allowed=$L,", args=[Text(allowed)])
          w.write("on_call=$L,", args=[
            Text(option_text(rule.on_call.map(s => s.to_string()))),
          ])
          w.write("on_success=$L,", args=[
            Text(option_text(rule.on_success.map(s => s.to_string()))),
          ])
          w.write("on_error=$L,", args=[
            Text(option_text(rule.on_error.map(s => s.to_string()))),
          ])
          w.write("requires=[$L],", args=[Text(requires)])
          w.write("cancels=$L,", args=[Text(cancels)])
          w.dedent()
          w.write("),")
        }
        w.dedent()
        w.write("],")
        let refusals = session.refusals
          .map(refusal => {
            "(\{mbt_string(refusal.state.to_string())}, \{self.int_code(refusal.code, @smithy.ShapeId::parse("smithy.rpc#jsonRpcSession").unwrap())})"
          })
          .join(", ")
        w.write("refusals=[$L],", args=[Text(refusals)])
        let capability_refusal = match session.capability_refusal {
          Some(code) =>
            "Some(\{self.int_code(code, @smithy.ShapeId::parse("smithy.rpc#jsonRpcSession").unwrap())})"
          None => "None"
        }
        w.write("capability_refusal=$L,", args=[Text(capability_refusal)])
        w.dedent()
        w.write(")")
      }
    }
    w.dedent()
    w.write("}")
    w.blank_line()
    w.write("///|")
    w.write(
      "/// A peer `$L` that talks to peer `$L`, with the session rules.",
      args=[Text(peer_name), Text(remote)],
    )
    w.write("pub fn new_peer(log? : @rpc.TranscriptLog) -> @rpc.Peer {")
    w.indent()
    w.write(
      "@rpc.Peer::new(self_name=$L, remote_name=$L, rules=session_rules(), log~)",
      args=[Text(mbt_string(peer_name)), Text(mbt_string(remote))],
    )
    w.dedent()
    w.write("}")
    w.blank_line()
  })
}

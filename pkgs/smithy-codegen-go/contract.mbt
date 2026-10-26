///|
fn string_list(values : Array[String], sort~ : Bool = false) -> String {
  let items = values.copy()
  if sort {
    items.sort_by((a, b) => a.lexical_compare(b))
  }
  "[]string{" + items.map(quote).join(", ") + "}"
}

///|
fn write_reference(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  rule : @rpc.CallReferenceContract?,
) -> Unit raise @codegen.CodegenError {
  match rule {
    None => w.write_inline("nil")
    Some(rule) => {
      w.write_inline("&$T{WireName: $S", args=[
        ctx.runtime("CallReference"),
        Text(rule.wire_name),
      ])
      if rule.position is Some(position) {
        w.write_inline(", Position: pointer(int($L))", args=[Int(position)])
      }
      if rule.code is Some(code) {
        w.write_inline(", Code: pointer(int64($L))", args=[
          Text(code_text(code, rule.wire_name)),
        ])
      }
      w.write_inline("}")
    }
  }
}

///|
fn result_shape(method_ : @rpc.MethodContract) -> @smithy.ShapeId? {
  match method_.result {
    NullResult => None
    OutputStructure(id) => Some(id)
    OutputMember(id) => Some(id)
  }
}

///|
fn write_validator(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  id : @smithy.ShapeId,
) -> Unit raise @codegen.CodegenError {
  w.write_inline("func(data $T) error { _, err := ", args=[
    ctx.foreign("RawMessage", "encoding/json"),
  ])
  decode_expression(ctx, w, id, "data")
  w.write_inline("; return err }")
}

///|
fn generate_contract(ctx : GoContext) -> String raise @codegen.CodegenError {
  let w = ctx.writer()
  w.write("func pointer[T any](value T) *T { return &value }\n")
  w.write(
    "// Contract returns a fresh prepared runtime contract.\nfunc Contract() $T {\n\treturn $T{\n\t\tPeers: []$T{",
    args=[
      ctx.runtime("Contract"),
      ctx.runtime("Contract"),
      ctx.runtime("PeerContract"),
    ],
  )
  let peers = ctx.description.peers.copy()
  peers.sort_by((a, b) => a.name.to_string().lexical_compare(b.name.to_string()))
  for peer in peers {
    w.write("\t\t\t{Name: $S, Methods: []$T{", args=[
      Text(peer.name.to_string()),
      ctx.runtime("MethodContract"),
    ])
    if peer.accepts is Some(service) {
      for method_ in service.methods {
        let kind = match method_.kind {
          RequestOnly => "request"
          NotificationOnly => "notification"
          RequestOrNotification => "either"
        }
        let mode = match method_.mode {
          Named => "named"
          Positional => "positional"
          Either => "either"
        }
        w.write(
          "\t\t\t\t{Name: $S, Kind: $S, Params: $S, Positional: $L, NullResult: $L,",
          args=[
            Text(method_.name.to_string()),
            Text(kind),
            Text(mode),
            Text(string_list(method_.positional.map(id => ctx.wire_name(id)))),
            Bool(method_.result == @rpc.NullResult),
          ],
        )
        w.write_inline("\t\t\t\t\tRefersToCall: ")
        write_reference(ctx, w, method_.refers_to_call)
        w.write(",")
        w.write_inline("\t\t\t\t\tValidateParams: ")
        write_validator(ctx, w, method_.input)
        w.write(",")
        if result_shape(method_) is Some(id) {
          w.write_inline("\t\t\t\t\tValidateResult: ")
          write_validator(ctx, w, id)
          w.write(",")
        }
        w.write("\t\t\t\t\tErrors: []$T{", args=[ctx.runtime("ErrorContract")])
        for error in method_.errors {
          w.write_inline(
            "\t\t\t\t\t\t{Code: $L, DataRequired: $L, DataAbsent: $L",
            args=[
              Text(code_text(error.code, error.shape.to_string())),
              Bool(error.data_required),
              Bool(error.data == None),
            ],
          )
          if error.data is Some(data) {
            w.write_inline(", ValidateData: ")
            write_validator(ctx, w, data)
          }
          w.write("},")
        }
        w.write("\t\t\t\t\t},\n\t\t\t\t},")
      }
    }
    w.write("\t\t\t}},")
  }
  w.write("\t\t},")
  if ctx.description.session is Some(session) {
    w.write("\t\tSession: &$T{\n\t\t\tStates: $L,\n\t\t\tCapabilities: []$T{", args=[
      ctx.runtime("SessionContract"),
      Text(string_list(session.states.map(s => s.to_string()))),
      ctx.runtime("CapabilityContract"),
    ])
    for capability in session.capabilities {
      w.write("\t\t\t\t{Name: $S, Method: $S, Pointer: $S},", args=[
        Text(capability.name),
        Text(capability.method_name.to_string()),
        Text(capability.pointer.to_string()),
      ])
    }
    w.write("\t\t\t},\n\t\t\tMethods: []$T{", args=[ctx.runtime("MethodRule")])
    for rule in session.methods {
      w.write_inline("\t\t\t\t{Receiver: $S, Method: $S", args=[
        Text(rule.receiver.to_string()),
        Text(rule.method_name.to_string()),
      ])
      if rule.allowed is Some(states) {
        w.write_inline(", Allowed: $L", args=[
          Text(string_list(states.map(s => s.to_string()), sort=true)),
        ])
      }
      for
        (field, state) in [
          ("OnCall", rule.on_call),
          ("OnSuccess", rule.on_success),
          ("OnError", rule.on_error),
        ] {
        if state is Some(state) {
          w.write_inline(", $L: $S", args=[Text(field), Text(state.to_string())])
        }
      }
      w.write_inline(", Requires: $L, Cancels: ", args=[
        Text(string_list(rule.requires, sort=true)),
      ])
      write_reference(ctx, w, rule.cancels)
      w.write("},")
    }
    w.write("\t\t\t},\n\t\t\tRefusals: []$T{", args=[
      ctx.runtime("StateRefusal"),
    ])
    for refusal in session.refusals {
      w.write("\t\t\t\t{State: $S, Code: $L},", args=[
        Text(refusal.state.to_string()),
        Text(code_text(refusal.code, refusal.state.to_string())),
      ])
    }
    w.write("\t\t\t},")
    if session.capability_refusal is Some(code) {
      w.write("\t\t\tCapabilityRefusal: pointer(int64($L)),", args=[
        Text(code_text(code, "capability refusal")),
      ])
    }
    w.write("\t\t},")
  }
  w.write("\t}\n}\n")
  ctx.render(w)
}

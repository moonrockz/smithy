///|
fn has_input(method_ : @rpc.MethodContract) -> Bool {
  method_.input.to_string() != "smithy.api#Unit"
}

///|
fn signature(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  method_ : @rpc.MethodContract,
  named : Bool,
  notification~ : Bool = false,
) -> Unit raise @codegen.CodegenError {
  w.write_inline("ctx $T", args=[ctx.foreign("Context", "context")])
  if has_input(method_) {
    w.write_inline(", input $C", args=[ctx.type_symbol(method_.input)])
  }
  w.write_inline(") ")
  if !notification &&
    method_.kind != @rpc.NotificationOnly &&
    result_target(ctx, method_) is Some(id) {
    w.write_inline("($C, error)", args=[ctx.type_symbol(id)])
  } else {
    w.write_inline("error")
  }
  let _ = named
}

///|
fn write_params(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  method_ : @rpc.MethodContract,
) -> Unit raise @codegen.CodegenError {
  if method_.mode == @rpc.Positional {
    w.write_inline("\tparams := []any{")
    for id in method_.positional {
      w.write_inline("input.$L,", args=[Text(ctx.field(id))])
    }
    w.write("}")
    // A nil pointer stored in an interface is not a nil interface. Trim the
    // slots by their typed fields, from the last optional member.
    let mut stopped = false
    for id in method_.positional.rev() {
      if stopped {
        continue
      }
      let required = ctx.values
        .get(method_.input)
        .map(v => v.members.iter().any(m => m.shape == id && m.required))
        .unwrap_or(false)
      if required {
        stopped = true
        continue
      }
      let index = method_.positional.search(id).unwrap()
      w.write(
        "\tif len(params) == $L && input.$L == nil { params = params[:$L] }",
        args=[Int(index + 1), Text(ctx.field(id)), Int(index)],
      )
    }
  } else if has_input(method_) {
    w.write("\tparams := input")
  } else {
    w.write("\tparams := struct{}{}")
  }
}

///|
fn generate_call(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  method_ : @rpc.MethodContract,
  notification : Bool,
) -> Unit raise @codegen.CodegenError {
  let name = ctx.name(method_.operation)
  let name = if notification && method_.kind == @rpc.RequestOrNotification {
    "Notify" + name
  } else {
    name
  }
  let output = if notification { None } else { result_target(ctx, method_) }
  w.write_inline("func (peer *Peer) $L(", args=[Text(name)])
  signature(ctx, w, method_, true, notification~)
  w.write(" {")
  write_params(ctx, w, method_)
  if notification {
    w.write("\treturn peer.Peer.Notify(ctx, $S, params)\n}\n", args=[
      Text(method_.name.to_string()),
    ])
    return
  }
  w.write("\tvar raw $T\n\terr := peer.Peer.Call(ctx, $S, params, &raw)", args=[
    ctx.foreign("RawMessage", "encoding/json"),
    Text(method_.name.to_string()),
  ])
  match output {
    None =>
      w.write("\treturn decode$LError(err)\n}\n", args=[
        Text(ctx.name(method_.operation)),
      ])
    Some(id) => {
      w.write(
        "\tif err != nil { var zero $C; return zero, decode$LError(err) }",
        args=[ctx.type_symbol(id), Text(ctx.name(method_.operation))],
      )
      w.write_inline("\treturn ")
      decode_expression(ctx, w, id, "raw")
      w.write("\n}\n")
    }
  }
  generate_error_decoder(ctx, w, method_)
}

///|
fn generate_error_decoder(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  method_ : @rpc.MethodContract,
) -> Unit raise @codegen.CodegenError {
  w.write("func decode$LError(err error) error {", args=[
    Text(ctx.name(method_.operation)),
  ])
  if method_.errors.is_empty() {
    w.write("\treturn err\n}\n")
    return
  }
  w.write(
    "\tvar wire *$T\n\tif !$T(err, &wire) { return err }\n\tswitch wire.Code {",
    args=[ctx.runtime("Error"), ctx.foreign("As", "errors")],
  )
  for error in method_.errors {
    w.write("\tcase $L:\n\t\tvar value $C", args=[
      Text(code_text(error.code, error.shape.to_string())),
      ctx.type_symbol(error.shape),
    ])
    match error.data {
      None => ()
      Some(data) => {
        let is_member = data.member_name() != None
        let target = if is_member { ctx.target(data) } else { data }
        w.write("\t\tif len(wire.Data) != 0 {")
        w.write_inline("\t\t\tdecoded, decodeErr := ")
        decode_expression(ctx, w, target, "wire.Data")
        w.write("\n\t\t\tif decodeErr != nil { return err }")
        if is_member {
          w.write("\t\t\tvalue.$L = $Ldecoded", args=[
            Text(ctx.field(data)),
            Text(if member_required(ctx, data) { "" } else { "&" }),
          ])
        } else {
          w.write("\t\t\tvalue = decoded")
        }
        w.write("\t\t}")
        if error.data_required {
          w.write("\t\tif len(wire.Data) == 0 { return err }")
        }
      }
    }
    w.write("\t\treturn value")
  }
  w.write("\tdefault: return err\n\t}\n}\n")
}

///|
fn member_required(
  ctx : GoContext,
  id : @smithy.ShapeId,
) -> Bool raise @codegen.CodegenError {
  match ctx.values.get(id.root()) {
    Some(policy) =>
      policy.members
      .iter()
      .any(member_ => member_.shape == id && member_.required)
    None => ctx.shape(id).trait_value("smithy.api#required") != None
  }
}

///|
fn generate_peer(ctx : GoContext) -> String raise @codegen.CodegenError {
  let w = ctx.writer()
  w.write(
    "// Peer accepts local handlers and calls the other peer.\ntype Peer struct { *$T }\n\n// Handlers holds the typed functions that this peer accepts.\ntype Handlers struct {",
    args=[ctx.runtime("Peer")],
  )
  if ctx.selected.accepts is Some(service) {
    for method_ in service.methods {
      w.write_inline("\t$L func(", args=[Text(ctx.name(method_.operation))])
      signature(ctx, w, method_, false)
      w.write("")
    }
  }
  w.write(
    "}\n\nfunc NewPeer(handlers Handlers, options $T) (*Peer, error) {\n\truntime, err := $T(Contract(), $S, options)\n\tif err != nil { return nil, err }\n\tpeer := &Peer{Peer: runtime}",
    args=[
      ctx.runtime("Options"),
      ctx.runtime("NewPeer"),
      Text(ctx.selected.name.to_string()),
    ],
  )
  if ctx.selected.accepts is Some(service) {
    for method_ in service.methods {
      let name = ctx.name(method_.operation)
      w.write(
        "\tif handlers.$L != nil {\n\t\terr = runtime.Register($S, func(ctx $T, data $T) (any, error) {",
        args=[
          Text(name),
          Text(method_.name.to_string()),
          ctx.foreign("Context", "context"),
          ctx.foreign("RawMessage", "encoding/json"),
        ],
      )
      if has_input(method_) {
        w.write_inline("\t\t\tinput, err := ")
        decode_expression(ctx, w, method_.input, "data")
        w.write(
          "\n\t\t\tif err != nil { return nil, $T(-32602, err.Error(), nil) }",
          args=[ctx.runtime("NewError")],
        )
      }
      let args_ = if has_input(method_) { "ctx, input" } else { "ctx" }
      if method_.kind == @rpc.NotificationOnly ||
        method_.result == @rpc.NullResult {
        w.write("\t\t\treturn nil, handlers.$L($L)", args=[
          Text(name),
          Text(args_),
        ])
      } else {
        w.write("\t\t\treturn handlers.$L($L)", args=[Text(name), Text(args_)])
      }
      w.write("\t\t})\n\t\tif err != nil { return nil, err }\n\t}")
    }
  }
  w.write("\treturn peer, nil\n}\n")
  if ctx.selected.calls is Some(service) {
    for method_ in service.methods {
      generate_call(ctx, w, method_, method_.kind == @rpc.NotificationOnly)
      if method_.kind == @rpc.RequestOrNotification {
        generate_call(ctx, w, method_, true)
      }
    }
  }
  ctx.render(w)
}

///|
fn generate_errors(ctx : GoContext) -> String raise @codegen.CodegenError {
  let w = ctx.writer()
  let errors : Map[@smithy.ShapeId, @rpc.ErrorContract] = Map([])
  for peer in ctx.description.peers {
    if peer.accepts is Some(service) {
      for method_ in service.methods {
        for error in method_.errors {
          if errors.get(error.shape) is Some(previous) && previous != error {
            raise @codegen.InvalidSettings(
              "I found different prepared error mappings for shape `\{error.shape}`.",
            )
          }
          errors[error.shape] = error
        }
      }
    }
  }
  let ids = errors.keys().to_array()
  ids.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  for id in ids {
    let error = errors[id]
    w.write("func (value $C) Error() string { return $S }", args=[
      ctx.type_symbol(id),
      Text("I received modeled error `" + id.to_string() + "`."),
    ])
    w.write_inline(
      "func (value $C) RPCError() *$T {\n\treturn $T($L, value.Error(), ",
      args=[
        ctx.type_symbol(id),
        ctx.runtime("Error"),
        ctx.runtime("NewError"),
        Text(code_text(error.code, error.shape.to_string())),
      ],
    )
    match error.data {
      None => w.write_inline("nil")
      Some(data) if data.member_name() != None =>
        w.write_inline("value.$L", args=[Text(ctx.field(data))])
      Some(_) => w.write_inline("value")
    }
    w.write(")\n}\n")
  }
  ctx.render(w)
}

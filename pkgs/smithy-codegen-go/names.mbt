///|
/// Check names before rendering. Keep provider names intact on success.
fn check_generated_names(ctx : GoContext) -> Unit raise @codegen.CodegenError {
  let declarations : Array[(String, String)] = [
    ("Peer", "generated peer"),
    ("Handlers", "generated handlers"),
    ("NewPeer", "generated peer constructor"),
    ("Contract", "generated contract"),
    ("decodeValue", "generated value decoder"),
    ("decodeObject", "generated object decoder"),
    ("pointer", "generated pointer helper"),
  ]
  let error_shapes : Set[@smithy.ShapeId] = Set([])
  for peer in ctx.description.peers {
    if peer.accepts is Some(service) {
      for method_ in service.methods {
        for error in method_.errors {
          error_shapes.add(error.shape)
        }
      }
    }
  }
  for id in ctx.shapes {
    if id.namespace() == "smithy.api" {
      continue
    }
    let shape = ctx.shape(id)
    let name = ctx.name(id)
    match shape.body {
      Simple(_)
      | Structure(_)
      | List(_)
      | Map(..)
      | Union(_)
      | Enum(_)
      | IntEnum(_) => declarations.push((name, id.to_string()))
      _ => continue
    }
    match shape.body {
      Union(ids) => {
        declarations.push(("decode" + name, id.to_string()))
        for member_ in ids {
          declarations.push((name + ctx.field(member_), member_.to_string()))
        }
      }
      Enum(ids) | IntEnum(ids) =>
        for member_ in ids {
          declarations.push((name + ctx.field(member_), member_.to_string()))
        }
      Structure(ids) =>
        for member_ in ids {
          let field = ctx.field(member_)
          if field == "UnmarshalJSON" ||
            (error_shapes.contains(id) && ["Error", "RPCError"].contains(field)) {
            raise @codegen.InvalidSettings(
              "I found a Go member name conflict for member `\{member_}` at `\{field}`.",
            )
          }
        }
      _ => ()
    }
  }
  let methods : Array[(String, String)] = [
    "Peer", "Serve", "Ready", "Close", "State", "HasCapability", "Call", "CallWithID",
    "CallUnchecked", "Notify", "Register",
  ].map(name => (name, "runtime peer method"))
  if ctx.selected.calls is Some(service) {
    for method_ in service.methods {
      let name = ctx.name(method_.operation)
      let construct = method_.operation.to_string()
      methods.push((name, construct))
      if method_.kind == @rpc.RequestOrNotification {
        methods.push(("Notify" + name, construct))
      }
      if method_.kind != @rpc.NotificationOnly {
        declarations.push(("decode" + name + "Error", construct))
      }
    }
  }
  check_name_list(declarations, "declaration")
  check_name_list(methods, "method")
}

///|
fn check_name_list(
  names : Array[(String, String)],
  kind : String,
) -> Unit raise @codegen.CodegenError {
  names.sort_by((a, b) => {
    let order = a.0.lexical_compare(b.0)
    if order == 0 {
      a.1.lexical_compare(b.1)
    } else {
      order
    }
  })
  for index = 1; index < names.length(); index = index + 1 {
    if names[index - 1].0 == names[index].0 {
      raise @codegen.InvalidSettings(
        "I found a Go \{kind} name conflict for construct `\{names[index].1}` at `\{names[index].0}` with construct `\{names[index - 1].1}`.",
      )
    }
  }
}

///|
fn GoContext::foreign(
  self : GoContext,
  name : String,
  path : String,
) -> @codegen.TemplateValue {
  let _ = self
  Sym(symbol(name, path~))
}

///|
fn GoContext::runtime(
  self : GoContext,
  name : String,
) -> @codegen.TemplateValue {
  Sym(symbol(name, path=self.module_name + "/rpc"))
}

///|
fn GoContext::name(
  self : GoContext,
  id : @smithy.ShapeId,
) -> String raise @codegen.CodegenError {
  self.provider.to_symbol(self.shape(id)).name.to_string()
}

///|
fn ordered_members(ids : Array[@smithy.ShapeId]) -> Array[@smithy.ShapeId] {
  let out = ids.copy()
  out.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  out
}

///|
fn decode_expression(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  id : @smithy.ShapeId,
  raw : String,
) -> Unit raise @codegen.CodegenError {
  let shape = ctx.value_shape(id)
  if shape.body is Union(_) {
    w.write_inline("decode$L($L)", args=[Text(ctx.name(shape.id)), Text(raw)])
  } else {
    w.write_inline("decodeValue[$C]($L)", args=[ctx.type_symbol(id), Text(raw)])
  }
}

///|
fn generate_structure(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  shape : @smithy.Shape,
  ids : Array[@smithy.ShapeId],
) -> Unit raise @codegen.CodegenError {
  let name = ctx.name(shape.id)
  let members = ordered_members(ids)
  w.write("type $T struct {", args=[Sym(ctx.provider.to_symbol(shape))])
  for id in members {
    let required = member_required(ctx, id)
    let pointer = if required { "" } else { "*" }
    let omit = if required { "" } else { ",omitempty" }
    w.write("\t$L $L$C `json:$L`", args=[
      Text(ctx.field(id)),
      Text(pointer),
      ctx.type_symbol(id),
      Text(quote(ctx.wire_name(id) + omit)),
    ])
  }
  w.write("}\n")
  w.write("func (value *$T) UnmarshalJSON(data []byte) error {", args=[
    Sym(ctx.provider.to_symbol(shape)),
  ])
  w.write(
    "\traw, err := decodeObject(data, $S)\n\tif err != nil { return err }",
    args=[Text(shape.id.to_string())],
  )
  w.write("\tvar decoded $T", args=[Sym(ctx.provider.to_symbol(shape))])
  if members.is_empty() {
    w.write("\t_ = raw")
  }
  for id in members {
    let required = member_required(ctx, id)
    w.write("\tif data, ok := raw[$S]; ok {", args=[Text(ctx.wire_name(id))])
    w.write_inline("\t\tmember, err := ")
    decode_expression(ctx, w, id, "data")
    w.write("\n\t\tif err != nil { return $T($S, err) }", args=[
      ctx.foreign("Errorf", "fmt"),
      Text("I could not read member `" + id.to_string() + "`: %w"),
    ])
    w.write("\t\tdecoded.$L = $Lmember", args=[
      Text(ctx.field(id)),
      Text(if required { "" } else { "&" }),
    ])
    if required {
      w.write("\t} else { return $T($S) }", args=[
        ctx.foreign("Errorf", "fmt"),
        Text("I expected required member `" + id.to_string() + "`."),
      ])
    } else {
      w.write("\t}")
    }
  }
  if ctx.values.get(shape.id) is Some(policy) &&
    policy.unknown_members == @validation.Reject {
    for id in members {
      w.write("\tdelete(raw, $S)", args=[Text(ctx.wire_name(id))])
    }
    w.write(
      "\tif len(raw) != 0 {\n\t\tkeys := make([]string, 0, len(raw))\n\t\tfor key := range raw { keys = append(keys, key) }\n\t\t$T(keys)\n\t\treturn $T($S, keys[0])\n\t}",
      args=[
        ctx.foreign("Strings", "sort"),
        ctx.foreign("Errorf", "fmt"),
        Text(
          "I found unknown member `%s` in structure `" +
          shape.id.to_string() +
          "`.",
        ),
      ],
    )
  }
  w.write("\t*value = decoded\n\treturn nil\n}\n")
  let _ = name
}

///|
fn union_wire(
  ctx : GoContext,
  id : @smithy.ShapeId,
) -> String raise @codegen.CodegenError {
  let json_names = ctx.description.peers
    .iter()
    .any(p => {
      p.accepts is Some(s) &&
      s.value_config.member_names == @validation.JsonName
    })
  if json_names &&
    ctx.shape(id).trait_value("smithy.api#jsonName") is Some(String(text)) {
    text
  } else {
    id.member_name().unwrap()
  }
}

///|
fn generate_union(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  shape : @smithy.Shape,
  ids : Array[@smithy.ShapeId],
) -> Unit raise @codegen.CodegenError {
  let name = ctx.name(shape.id)
  let members = ordered_members(ids)
  w.write("type $T interface { is$L() }\n", args=[
    Sym(ctx.provider.to_symbol(shape)),
    Text(name),
  ])
  for id in members {
    let variant = name + ctx.field(id)
    w.write("type $L struct { Value $C }\nfunc ($L) is$L() {}", args=[
      Text(variant),
      ctx.type_symbol(id),
      Text(variant),
      Text(name),
    ])
    w.write(
      "func (value $L) MarshalJSON() ([]byte, error) {\n\treturn $T(map[string]any{$S: value.Value})\n}\n",
      args=[
        Text(variant),
        ctx.foreign("Marshal", "encoding/json"),
        Text(union_wire(ctx, id)),
      ],
    )
  }
  w.write("func decode$L(data []byte) ($T, error) {", args=[
    Text(name),
    Sym(ctx.provider.to_symbol(shape)),
  ])
  w.write(
    "\traw, err := decodeObject(data, $S)\n\tif err != nil { return nil, err }\n\tif len(raw) != 1 { return nil, $T($S) }\n\tfor tag, data := range raw {\n\t\tswitch tag {",
    args=[
      Text(shape.id.to_string()),
      ctx.foreign("Errorf", "fmt"),
      Text("I expected one member in union `" + shape.id.to_string() + "`."),
    ],
  )
  for id in members {
    w.write("\t\tcase $S:", args=[Text(union_wire(ctx, id))])
    w.write_inline("\t\t\tvalue, err := ")
    decode_expression(ctx, w, id, "data")
    w.write(
      "\n\t\t\tif err != nil { return nil, err }\n\t\t\treturn $L{Value: value}, nil",
      args=[Text(name + ctx.field(id))],
    )
  }
  w.write(
    "\t\tdefault: return nil, $T($S, tag)\n\t\t}\n\t}\n\treturn nil, $T($S)\n}\n",
    args=[
      ctx.foreign("Errorf", "fmt"),
      Text(
        "I found unknown member `%s` in union `" + shape.id.to_string() + "`.",
      ),
      ctx.foreign("Errorf", "fmt"),
      Text("I expected union `" + shape.id.to_string() + "`."),
    ],
  )
}

///|
fn generate_collection(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  shape : @smithy.Shape,
) -> Unit raise @codegen.CodegenError {
  let name = ctx.provider.to_symbol(shape)
  let sparse = shape.trait_value("smithy.api#sparse") != None
  let pointer = if sparse { "*" } else { "" }
  match shape.body {
    List(member_) => {
      w.write("type $T []$L$C\n", args=[
        Sym(name),
        Text(pointer),
        ctx.type_symbol(member_),
      ])
      w.write(
        "func (value *$T) UnmarshalJSON(data []byte) error {\n\tvar raw []$T\n\tif err := $T(data, &raw); err != nil { return err }\n\tif raw == nil { return $T($S) }\n\tdecoded := make($T, len(raw))\n\tfor index, data := range raw {",
        args=[
          Sym(name),
          ctx.foreign("RawMessage", "encoding/json"),
          ctx.foreign("Unmarshal", "encoding/json"),
          ctx.foreign("Errorf", "fmt"),
          Text("I expected list `" + shape.id.to_string() + "`."),
          Sym(name),
        ],
      )
      if sparse {
        write_sparse_null(ctx, w)
      }
      w.write_inline("\t\titem, err := ")
      decode_expression(ctx, w, member_, "data")
      w.write(
        "\n\t\tif err != nil { return err }\n\t\tdecoded[index] = $Litem\n\t}\n\t*value = decoded\n\treturn nil\n}\n",
        args=[Text(if sparse { "&" } else { "" })],
      )
    }
    Map(key~, value~) => {
      let key_target = ctx.target(key)
      let enum_key = ctx.shape(key_target).body is Enum(_)
      let key_expression : @codegen.TemplateValue = Call(writer => {
        if enum_key {
          writer.write_inline("decodedKey")
        } else {
          writer.write_inline("$C(key)", args=[ctx.type_symbol(key_target)])
        }
      })
      w.write("type $T map[$C]$L$C\n", args=[
        Sym(name),
        ctx.type_symbol(key_target),
        Text(pointer),
        ctx.type_symbol(value),
      ])
      w.write(
        "func (value *$T) UnmarshalJSON(data []byte) error {\n\traw, err := decodeObject(data, $S)\n\tif err != nil { return err }\n\tdecoded := make($T, len(raw))",
        args=[Sym(name), Text(shape.id.to_string()), Sym(name)],
      )
      w.write(
        "\tkeys := make([]string, 0, len(raw))\n\tfor key := range raw { keys = append(keys, key) }\n\t$T(keys)\n\tfor _, key := range keys {\n\t\tdata := raw[key]",
        args=[ctx.foreign("Strings", "sort")],
      )
      if enum_key {
        w.write("\t\tkeyData, _ := $T(key)", args=[
          ctx.foreign("Marshal", "encoding/json"),
        ])
        w.write_inline("\t\tdecodedKey, err := ")
        decode_expression(ctx, w, key_target, "keyData")
        w.write("\n\t\tif err != nil { return $T($S, key, err) }", args=[
          ctx.foreign("Errorf", "fmt"),
          Text("I could not read map key `" + key.to_string() + "` at `%s`: %w"),
        ])
      }
      if sparse {
        w.write("\t\tdecoded[$C] = nil", args=[key_expression])
        write_sparse_null(ctx, w)
      }
      w.write_inline("\t\titem, err := ")
      decode_expression(ctx, w, value, "data")
      w.write(
        "\n\t\tif err != nil { return err }\n\t\tdecoded[$C] = $Litem\n\t}\n\t*value = decoded\n\treturn nil\n}\n",
        args=[key_expression, Text(if sparse { "&" } else { "" })],
      )
    }
    _ => ()
  }
}

///|
fn write_sparse_null(
  ctx : GoContext,
  w : @codegen.CodeWriter,
) -> Unit raise @codegen.CodegenError {
  w.write("\t\tif $T($T(data), []byte(\"null\")) { continue }", args=[
    ctx.foreign("Equal", "bytes"),
    ctx.foreign("TrimSpace", "bytes"),
  ])
}

///|
fn generate_enum(
  ctx : GoContext,
  w : @codegen.CodeWriter,
  shape : @smithy.Shape,
  ids : Array[@smithy.ShapeId],
  integer : Bool,
) -> Unit raise @codegen.CodegenError {
  let name = ctx.provider.to_symbol(shape)
  let members = ordered_members(ids)
  w.write("type $T $L\n\nconst (", args=[
    Sym(name),
    Text(if integer { "int32" } else { "string" }),
  ])
  for id in members {
    let raw = ctx.shape(id).trait_value("smithy.api#enumValue")
    let value = match raw {
      Some(String(text)) => quote(text)
      Some(Number(number)) => number.to_string()
      _ => quote(id.member_name().unwrap())
    }
    w.write("\t$L$L $T = $L", args=[
      Text(name.name.to_string()),
      Text(ctx.field(id)),
      Sym(name),
      Text(value),
    ])
  }
  w.write(")\n")
  w.write(
    "func (value *$T) UnmarshalJSON(data []byte) error {\n\traw, err := decodeValue[$L](data)\n\tif err != nil { return err }\n\tswitch $T(raw) {",
    args=[Sym(name), Text(if integer { "int32" } else { "string" }), Sym(name)],
  )
  for id in members {
    w.write("\tcase $L$L: *value = $T(raw); return nil", args=[
      Text(name.name.to_string()),
      Text(ctx.field(id)),
      Sym(name),
    ])
  }
  w.write("\tdefault: return $T($S, raw)\n\t}\n}\n", args=[
    ctx.foreign("Errorf", "fmt"),
    Text("I found value `%v` outside enum `" + shape.id.to_string() + "`."),
  ])
  w.write("func (value $T) MarshalJSON() ([]byte, error) {\n\tswitch value {", args=[
    Sym(name),
  ])
  for id in members {
    w.write("\tcase $L$L: return $T($L(value))", args=[
      Text(name.name.to_string()),
      Text(ctx.field(id)),
      ctx.foreign("Marshal", "encoding/json"),
      Text(if integer { "int32" } else { "string" }),
    ])
  }
  w.write("\tdefault: return nil, $T($S, value)\n\t}\n}\n", args=[
    ctx.foreign("Errorf", "fmt"),
    Text("I found value `%v` outside enum `" + shape.id.to_string() + "`."),
  ])
}

///|
fn generate_types(ctx : GoContext) -> String raise @codegen.CodegenError {
  let w = ctx.writer()
  w.write(
    "func decodeValue[T any](data []byte) (T, error) {\n\tvar value T\n\tif $T($T(data), []byte(\"null\")) {\n\t\tif _, document := any(value).($T); !document { return value, $T(\"I expected a non-null value for construct `%T`.\", value) }\n\t}\n\tif err := $T(data, &value); err != nil { return value, err }\n\treturn value, nil\n}\n",
    args=[
      ctx.foreign("Equal", "bytes"),
      ctx.foreign("TrimSpace", "bytes"),
      ctx.foreign("RawMessage", "encoding/json"),
      ctx.foreign("Errorf", "fmt"),
      ctx.foreign("Unmarshal", "encoding/json"),
    ],
  )
  w.write(
    "func decodeObject(data []byte, construct string) (map[string]$T, error) {\n\tvar raw map[string]$T\n\tif err := $T(data, &raw); err != nil { return nil, err }\n\tif raw == nil { return nil, $T(\"I expected an object for construct `%s`.\", construct) }\n\treturn raw, nil\n}\n",
    args=[
      ctx.foreign("RawMessage", "encoding/json"),
      ctx.foreign("RawMessage", "encoding/json"),
      ctx.foreign("Unmarshal", "encoding/json"),
      ctx.foreign("Errorf", "fmt"),
    ],
  )
  for id in ctx.shapes {
    let shape = ctx.shape(id)
    if id.namespace() == "smithy.api" {
      continue
    }
    match shape.body {
      Structure(ids) => generate_structure(ctx, w, shape, ids)
      Union(ids) => generate_union(ctx, w, shape, ids)
      List(_) | Map(..) => generate_collection(ctx, w, shape)
      Enum(ids) => generate_enum(ctx, w, shape, ids, false)
      IntEnum(ids) => generate_enum(ctx, w, shape, ids, true)
      Simple(Blob) =>
        w.write("type $T = []byte\n", args=[Sym(ctx.provider.to_symbol(shape))])
      Simple(kind) =>
        w.write("type $T = $T\n", args=[
          Sym(ctx.provider.to_symbol(shape)),
          Sym(
            primitive_symbol(
              kind,
              ctx.module_name,
              timestamp_format=ctx.timestamp_format_for(shape.id),
            ),
          ),
        ])
      _ => ()
    }
  }
  ctx.render(w)
}

///|
/// Traits that change the logical value contract. Wire traits such as jsonName are not among them.
let logical_traits : Array[String] = [
  "smithy.api#default", "smithy.api#enum", "smithy.api#enumValue", "smithy.api#length",
  "smithy.api#pattern", "smithy.api#range", "smithy.api#required", "smithy.api#sparse",
  "smithy.api#timestampFormat", "smithy.api#uniqueItems", "smithy.serialization#emptyAsAbsent",
]

///|
fn write_node(out : StringBuilder, value : @smithy.NodeValue) -> Unit {
  // Trait values come from the assembled model, so their depth is already bounded by the loader.
  match value {
    Null => out.write_string("null")
    Boolean(b) => out.write_string(if b { "true" } else { "false" })
    Number(n) => out.write_string(n.to_string())
    String(s) => out.write_string(s.escape())
    Array(items) => {
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_char(',')
        }
        write_node(out, item)
      }
      out.write_char(']')
    }
    Object(fields) => {
      let names = fields.keys().to_array()
      names.sort()
      out.write_char('{')
      for i, name in names {
        if i > 0 {
          out.write_char(',')
        }
        out.write_string(name.escape())
        out.write_char(':')
        write_node(out, fields.get(name).unwrap())
      }
      out.write_char('}')
    }
  }
}

///|
fn write_traits(out : StringBuilder, shape : @smithy.Shape) -> Unit {
  for name in logical_traits {
    if shape.trait_value(name) is Some(value) {
      out.write_string(" @" + name + "=")
      write_node(out, value)
    }
  }
}

///|
/// A stable identity of the logical contract reachable from `root`: shape kinds, members, targets and
/// value constraints, independent of wire rules and of traversal order.
fn fingerprint(
  model : @smithy.Model,
  root : @smithy.ShapeId,
  closure : Array[@smithy.ShapeId],
) -> String {
  let lines : Array[String] = []
  for id in closure {
    let shape = model.shapes.get(id).unwrap()
    let out = StringBuilder()
    out.write_string(id.to_string() + " " + shape.body.keyword())
    write_traits(out, shape)
    let members = match shape.body {
      Structure(ids) | Union(ids) | Enum(ids) | IntEnum(ids) => ids
      List(member_id) => [member_id]
      Map(key~, value~) => [key, value]
      _ => []
    }
    for member_id in members {
      guard model.shapes.get(member_id) is Some(member_shape) else { continue }
      out.write_string(" | " + member_id.member_name().unwrap_or(""))
      if member_shape.body is Member(target~) {
        out.write_string("->" + target.to_string())
      }
      write_traits(out, member_shape)
    }
    lines.push(out.to_string())
  }
  lines.sort()
  let text = root.to_string() + "\n" + lines.join("\n")
  // FNV-1a, 64 bits, over UTF-16 code units.
  let mut hash : UInt64 = 0xcbf29ce484222325UL
  for i in 0..<text.length() {
    hash = hash ^ text.code_unit_at(i).to_int().to_uint64()
    hash = hash * 0x100000001b3UL
  }
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for shift = 60; shift >= 0; shift = shift - 4 {
    out.write_char(
      digits[((hash >> shift) & 0xfUL).to_int()].to_int().unsafe_to_char(),
    )
  }
  out.to_string()
}

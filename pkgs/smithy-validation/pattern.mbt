///|
/// Compile the portable pattern profile. Unknown constructs are never ignored.
fn compile_pattern(
  pattern : String,
  id : @smithy.ShapeId,
) -> @string.Regex raise PreparationError {
  let unsupported = fn() {
    UnsupportedConstraint(
      id, "I could not compile the pattern in the portable regular-expression profile.",
    )
  }
  guard pattern.length() <= 4096 else { raise unsupported() }
  let out = StringBuilder()
  let mut in_class = false
  let mut i = 0
  while i < pattern.length() {
    let c = pattern.code_unit_at(i).to_int()
    if c == 92 {
      i += 1
      guard i < pattern.length() else { raise unsupported() }
      let escape = pattern.code_unit_at(i).to_int()
      let expansion = match escape {
        100 => Some("0-9")
        119 => Some("A-Za-z0-9_")
        115 =>
          Some(
            "\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff",
          )
        _ => None
      }
      if expansion is Some(expansion) {
        out.write_string(
          if in_class {
            expansion
          } else {
            "[" + expansion + "]"
          },
        )
      } else if escape == 68 || escape == 87 || escape == 83 {
        guard !in_class else { raise unsupported() }
        out.write_string(
          match escape {
            68 => "[^0-9]"
            87 => "[^A-Za-z0-9_]"
            _ =>
              "[^\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]"
          },
        )
      } else if escape == 98 && in_class {
        out.write_string("\\u0008")
      } else {
        guard [
          92, 46, 94, 36, 124, 63, 42, 43, 40, 41, 91, 93, 123, 125, 45, 47, 110,
          114, 116, 102, 118, 98, 66, 117,
        ].contains(escape) else {
          raise unsupported()
        }
        out.write_string("\\")
        out.write_string(pattern[i:i + 1].to_owned())
      }
    } else if c == 91 {
      guard !in_class else { raise unsupported() }
      in_class = true
      out.write_string("[")
    } else if c == 93 {
      in_class = false
      out.write_string("]")
    } else if c == 46 && !in_class {
      out.write_string("[^\\n\\r\\u2028\\u2029]")
    } else {
      if c == 40 &&
        !in_class &&
        i + 1 < pattern.length() &&
        pattern.code_unit_at(i + 1) == 63 {
        guard i + 2 < pattern.length() && pattern.code_unit_at(i + 2) == 58 else {
          raise unsupported()
        }
      }
      let end = if c >= 0xd800 && c <= 0xdbff && i + 1 < pattern.length() {
        i + 2
      } else {
        i + 1
      }
      out.write_string(pattern[i:end].to_owned())
      i = end
      continue
    }
    i += 1
  }
  @string.Regex::Regex(out.to_string()) catch {
    _ => raise unsupported()
  }
}

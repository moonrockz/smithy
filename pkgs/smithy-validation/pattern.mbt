///|
priv struct BoundedPattern {
  regex : @string.Regex
  weight : Int32
} derive(Debug)

///|
fn BoundedPattern::execute(self : BoundedPattern, text : String) -> Bool {
  self.regex.execute(text) is Some(_)
}

///|
/// Bound the expanded expression before the core parser/compiler can recurse or
/// copy quantified subexpressions. Counts include every alternative and class.
/// Repetition counts follow core's translate: one instance for `*` and `?`, two
/// for `+`. A positive BMP-only class is one unit.
fn pattern_cost(
  pattern : String,
  id : @smithy.ShapeId,
) -> Int32 raise PreparationError {
  let unsupported = fn() {
    UnsupportedConstraint(
      id, "I expected a pattern with at most 32 nested groups and 1024 expanded expression units.",
    )
  }
  let groups : Array[(Int32, Int32)] = []
  let mut total = 0
  let mut last = 0
  let mut i = 0
  while i < pattern.length() {
    let c = pattern.code_unit_at(i).to_int()
    if c == 40 {
      guard groups.length() < 32 else { raise unsupported() }
      groups.push((total, last))
      total = 0
      last = 0
      i += if i + 2 < pattern.length() &&
        pattern.code_unit_at(i + 1) == 63 &&
        pattern.code_unit_at(i + 2) == 58 {
        3
      } else {
        1
      }
      continue
    }
    if c == 42 || c == 43 || c == 63 || c == 123 {
      guard last > 0 else { raise unsupported() }
      let mut copies = if c == 43 { 2 } else { 1 }
      if c == 123 {
        i += 1
        let start = i
        let mut lower = 0
        while i < pattern.length() &&
              pattern.code_unit_at(i) >= 48 &&
              pattern.code_unit_at(i) <= 57 {
          lower = lower * 10 + pattern.code_unit_at(i).to_int() - 48
          guard lower <= 1024 else { raise unsupported() }
          i += 1
        }
        guard i > start else { raise unsupported() }
        copies = lower
        if i < pattern.length() && pattern.code_unit_at(i) == 44 {
          i += 1
          let upper_start = i
          let mut upper = 0
          while i < pattern.length() &&
                pattern.code_unit_at(i) >= 48 &&
                pattern.code_unit_at(i) <= 57 {
            upper = upper * 10 + pattern.code_unit_at(i).to_int() - 48
            guard upper <= 1024 else { raise unsupported() }
            i += 1
          }
          copies = if i == upper_start { lower + 1 } else { upper }
          guard copies >= lower else { raise unsupported() }
        }
        guard i < pattern.length() && pattern.code_unit_at(i) == 125 else {
          raise unsupported()
        }
      }
      let expanded = last * copies + 2
      total = total - last + expanded
      last = expanded
      guard total <= 1024 else { raise unsupported() }
      i += 1
      if i < pattern.length() && pattern.code_unit_at(i) == 63 {
        i += 1
      }
      continue
    }
    let atom = if c == 41 {
      guard groups.pop() is Some((parent, _)) else { raise unsupported() }
      let size = total + 1
      total = parent
      size
    } else if c == 92 {
      i += 1
      guard i < pattern.length() else { raise unsupported() }
      if pattern.code_unit_at(i) == 117 {
        i += 1
        if i < pattern.length() && pattern.code_unit_at(i) == 123 {
          while i < pattern.length() && pattern.code_unit_at(i) != 125 {
            i += 1
          }
        } else {
          i += 3
        }
        guard i < pattern.length() else { raise unsupported() }
      }
      1
    } else if c == 91 {
      let start = i
      i += 1
      while i < pattern.length() && pattern.code_unit_at(i) != 93 {
        if pattern.code_unit_at(i) == 92 {
          i += 1
        }
        i += 1
      }
      guard i < pattern.length() else { raise unsupported() }
      class_cost(pattern, start, i + 1)
    } else {
      1
    }
    total += atom
    last = if c == 124 { 0 } else { atom }
    guard total <= 1024 else { raise unsupported() }
    i += 1
  }
  guard groups.is_empty() else { raise unsupported() }
  // UTF-16 lowering and Thompson instructions can expand a source atom.
  Int32::max(1, total) * 8
}

///|
/// Cost of the class `pattern[start:end]` (from `[` through `]`). Core maps a
/// positive BMP-only class to one symbol set. A negated class, or one with
/// astral or surrogate members, lowers to surrogate sequences, so it costs its
/// source length.
fn class_cost(pattern : String, start : Int32, end : Int32) -> Int32 {
  let full = end - start
  if pattern.code_unit_at(start + 1) == 94 {
    return full
  }
  let mut j = start + 1
  while j < end {
    let c = pattern.code_unit_at(j).to_int()
    if c >= 0xD800 && c <= 0xDFFF {
      return full
    }
    if c == 92 && j + 1 < end && pattern.code_unit_at(j + 1) == 117 {
      if j + 2 < end && pattern.code_unit_at(j + 2) == 123 {
        return full
      }
      let mut value = 0
      let mut k = j + 2
      while k < j + 6 && k < end {
        let h = pattern.code_unit_at(k).to_int()
        let digit = if h >= 48 && h <= 57 {
          h - 48
        } else if h >= 97 && h <= 102 {
          h - 87
        } else if h >= 65 && h <= 70 {
          h - 55
        } else {
          -1
        }
        if digit < 0 {
          break
        }
        value = value * 16 + digit
        k += 1
      }
      if value >= 0xD800 && value <= 0xDFFF {
        return full
      }
      j += 2
      continue
    }
    if c == 92 {
      j += 1
    }
    j += 1
  }
  1
}

///|
/// Compile the portable pattern profile. Unknown constructs are never ignored.
fn compile_pattern(
  pattern : String,
  id : @smithy.ShapeId,
) -> BoundedPattern raise PreparationError {
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
      if c == 40 &&
        !in_class &&
        !(i + 1 < pattern.length() && pattern.code_unit_at(i + 1) == 63) {
        out.write_string("(?:")
        i += 1
        continue
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
  let translated = out.to_string()
  let weight = pattern_cost(translated, id)
  let regex = @string.Regex::Regex(translated) catch {
    _ => raise unsupported()
  }
  // Core compiles its automaton lazily; do that once, only after the cost guard.
  ignore(regex.execute(""))
  { regex, weight, }
}

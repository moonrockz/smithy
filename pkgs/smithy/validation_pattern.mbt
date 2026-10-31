///|
/// Rewrite a Smithy `@pattern` (ECMA 262) into the syntax of core
/// `@string.Regex`.
///
/// - `\d` and `\w` become their ASCII classes.
/// - A literal dash in a class becomes `\-`. ECMA 262 reads a dash as a
///   literal at the start or end of a class, and after a range or a class
///   escape. Core 0.10.18 rejects these dashes as ambiguous. A literal
///   dash can start a range: `[--/]` is the range from `-` to `/`.
fn core_pattern(pattern : String) -> String {
  let pattern = pattern
    .replace_all(old="\\d", new="[0-9]")
    .replace_all(old="\\w", new="[a-zA-Z0-9_]")
  let out = StringBuilder()
  let length = pattern.length()
  let mut in_class = false
  // True when the last class item is a single character that can start a range.
  let mut range_start = false
  // True after a range dash, until the end character of the range.
  let mut range_end = false
  let mut i = 0
  while i < length {
    let c = pattern.code_unit_at(i)
    if c == '\\' && i + 1 < length {
      let next = pattern.code_unit_at(i + 1)
      out.write_view(pattern.view(start_offset=i, end_offset=i + 2))
      if in_class {
        let class_escape = next == 'd' ||
          next == 'D' ||
          next == 'w' ||
          next == 'W' ||
          next == 's' ||
          next == 'S'
        range_start = !range_end && !class_escape
        range_end = false
      }
      i += 2
      continue
    }
    if !in_class {
      out.write_char(c.unsafe_to_char())
      if c == '[' {
        in_class = true
        range_start = false
        range_end = false
        if i + 1 < length && pattern.code_unit_at(i + 1) == '^' {
          out.write_char('^')
          i += 1
        }
      }
    } else if c == ']' {
      out.write_char(']')
      in_class = false
    } else if c == '-' {
      let at_end = i + 1 >= length || pattern.code_unit_at(i + 1) == ']'
      if range_start && !at_end {
        out.write_char('-')
        range_start = false
        range_end = true
      } else {
        out.write_string("\\-")
        // A literal dash is a class atom, so it can start a range (`[--/]`).
        range_start = true
        range_end = false
      }
    } else {
      out.write_char(c.unsafe_to_char())
      range_start = !range_end
      range_end = false
    }
    i += 1
  }
  out.to_string()
}

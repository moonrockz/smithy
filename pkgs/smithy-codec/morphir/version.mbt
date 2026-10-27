// The Morphir formatVersion scalar (finos/morphir docs/spec/ir/format-version.md).
//
// Accepted: integer N (release N.0.0) or the exact string "N.minor.patch"; components are base-10 without
// leading zeros and at most 4294967295. Integers 1 and 2 are historical spellings; the strings "0.x.y",
// "1.x.y", "2.x.y" and the integer 0 are invalid syntax. The logical value is always the "X.Y.Z" text. The
// writer emits the integer for a baseline release X.0.0 and the exact string otherwise. Support (which
// releases a bundle reads) is decided by the bundle and the root shapes, not here.

///|
let max_component : String = "4294967295"

///|
/// Whether a digit string (no sign, no leading zero) is at most 4294967295.
fn component_in_range(digits : String) -> Bool {
  digits.length() < max_component.length() ||
  (
    digits.length() == max_component.length() &&
    code_unit_compare(digits, max_component) <= 0
  )
}

///|
fn plain_digits(text : String) -> Bool {
  !text.is_empty() &&
  text.iter().all(is_digit) &&
  (text == "0" || text.get_char(0).unwrap() != '0')
}

///|
/// Normalize a formatVersion JSON value to "X.Y.Z", or refuse it with a format-version diagnostic code.
fn format_version_read(value : Json) -> Result[String, String] {
  match value {
    Number(_, repr~) => {
      let token = match (repr, @codec.json_number(value)) {
        (Some(text), _) => text
        (None, Some(n)) => n.to_string()
        (None, None) =>
          return Err(
            "invalid_format_version_type: I expected an exact integer token.",
          )
      }
      // Only a plain unsigned integer token is an integer spelling; 3.0, 3e0 and -1 are not (wire
      // reference section 0 gap, decided here: the lexeme must be an integer token).
      guard plain_digits(token) else {
        return Err(
          "invalid_format_version_type: \{token} is not an unsigned integer token.",
        )
      }
      guard component_in_range(token) else {
        return Err("format_version_out_of_range: \{token} exceeds 4294967295.")
      }
      guard token != "0" else {
        return Err("invalid_format_version_syntax: 0 is not a format family.")
      }
      Ok(token + ".0.0")
    }
    String(text) => {
      let parts = split(text, ".")
      guard parts.length() == 3 && parts.iter().all(plain_digits) else {
        return Err(
          "invalid_format_version_syntax: \{text.escape()} is not an exact release \"N.minor.patch\".",
        )
      }
      guard parts.iter().all(component_in_range) else {
        return Err(
          "format_version_out_of_range: a component of \{text.escape()} exceeds 4294967295.",
        )
      }
      guard !(parts[0] is ("0" | "1" | "2")) else {
        return Err(
          "invalid_format_version_syntax: release strings start at major 3; \{text.escape()} is invalid.",
        )
      }
      Ok(text)
    }
    _ =>
      Err(
        "invalid_format_version_type: I expected an unsigned integer or a release string.",
      )
  }
}

///|
/// The canonical JSON spelling of a normalized release.
fn format_version_json(text : String) -> Result[Json, String] {
  let parts = split(text, ".")
  guard parts.length() == 3 && parts.iter().all(plain_digits) else {
    return Err("I cannot write \{text.escape()} as a formatVersion.")
  }
  if parts[1] == "0" && parts[2] == "0" {
    match @smithy.NodeNumber::parse(parts[0]) {
      Some(n) => Ok(@codec.number_json(n))
      None => Err("I cannot write \{text.escape()} as a formatVersion.")
    }
  } else {
    Ok(Json::string(text))
  }
}

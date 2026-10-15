///|
/// The digits at `from`: the offset after them and whether there was one.
fn digits(text : String, from : @span.Offset) -> (@span.Offset, Bool) {
  let end = skip_while(text, from, is_digit)
  (end, end > from)
}

///|
/// `Number = [Minus] Int [Frac] [Exp]`, with `Int = "0" / DigitOneToNine
/// *DIGIT`. A run that does not fit is one `Error` token covering every
/// digit, sign, dot, `e`, `+`/`-` and glued letter, with `SM-SCAN-007`.
fn scan_number(text : String, at : @span.Offset) -> Step {
  let mut ok = true
  let mut end = at
  if unit_at(text, end) == Some('-') {
    end = end.next()
  }
  // Int
  match unit_at(text, end) {
    Some('0') => {
      end = end.next()
      let (after, more) = digits(text, end)
      if more {
        ok = false
        end = after
      }
    }
    Some(c) if is_digit(c) => end = digits(text, end).0
    _ => ok = false
  }
  // Frac
  if unit_at(text, end) == Some('.') {
    let (after, some) = digits(text, end.next())
    end = after
    if !some {
      ok = false
    }
  }
  // Exp
  if unit_at(text, end) is Some('e' | 'E') {
    end = end.next()
    if unit_at(text, end) is Some('+' | '-') {
      end = end.next()
    }
    let (after, some) = digits(text, end)
    end = after
    if !some {
      ok = false
    }
  }
  // A letter or dot glued to a number is part of the bad run (`1x`, `-a`).
  if unit_at(text, end) is Some(c) && (is_ident_char(c) || c == '.') {
    ok = false
    end = skip_while(text, end, c => is_ident_char(c) || c == '.')
  }
  if ok {
    token_step(Number, text, at, end)
  } else {
    let shown = slice(text, at, end)
    error_step(
      text,
      at,
      end,
      lexical(
        "SM-SCAN-007",
        "INVALID NUMBER",
        "I cannot read `\{shown}` as a number",
        at.to(end),
        notes=[
          "A number is an optional `-`, then `0` or digits with no leading zero, then an optional fraction like `.25` and an optional exponent like `e10` or `E-3`.",
        ],
        hint="Write `0.5` rather than `.5`, `1.0` rather than `1.`, and drop leading zeros.",
      ),
    )
  }
}

///|
/// Whether a `Number` lexeme has no fraction and no exponent.
pub fn is_integer_lexeme(lexeme : String) -> Bool {
  for ch in lexeme {
    if ch == '.' || ch == 'e' || ch == 'E' {
      return false
    }
  }
  true
}

///|
/// An immutable compiled Boolean search program in MoonBit core's regex dialect.
pub struct Regex {
  priv source : String
  priv program : @re.Program
}

///|
pub impl @debug.Debug for Regex with fn to_repr(self) {
  @debug.Repr(self.source)
}

///|
/// Search with a finite allowance. Exhaustion is distinct from a completed non-match.
pub fn Regex::matches(
  self : Regex,
  input : StringView,
  work~ : WorkLimit,
) -> MatchOutcome {
  let (matched, used) = self.program.matches(input, work.units)
  match matched {
    Some(result) => Complete(result, used)
    None => Exhausted(used)
  }
}

///|
/// Compile runtime pattern data under finite structural limits. Group syntax is
/// accepted but captures are erased: this API returns only a Boolean result.
pub fn Regex::compile(
  pattern : StringView,
  limits~ : CompileLimits = {
    source_units: 4096,
    nesting: 32,
    expanded_units: 1024,
  },
) -> Regex raise CompileError {
  guard pattern.length() <= limits.source_units else {
    raise CompilationLimit(SourceLength)
  }
  let parsed = @regex_parser.parse(
    profile=re_profile_unicode,
    mode=String,
    pattern,
    max_depth=limits.nesting,
  ) catch {
    error => {
      let message = error.to_string()
      if message.contains("Groups nested too deeply") {
        raise CompilationLimit(Nesting)
      }
      if message.contains("Unsupported") || message.contains("not supported") {
        raise UnsupportedPattern(message)
      }
      raise InvalidPattern(message)
    }
  }
  // Count before UTF-16 lowering and before the NFA emitter copies repetitions.
  ignore(expanded_size(parsed, limits.expanded_units))
  let lowered = re_lower_to_utf16(erase_captures(parsed))
  {
    source: pattern.to_owned(),
    program: @re.compile(profile=re_profile_utf16, lowered).program(),
  }
}

///|
fn checked_size_add(
  a : Int32,
  b : Int32,
  cap : Int32,
) -> Int32 raise CompileError {
  guard b <= cap - a else { raise CompilationLimit(Expansion) }
  a + b
}

///|
fn expanded_size(
  pattern : @re.Pattern,
  cap : Int32,
) -> Int32 raise CompileError {
  match pattern.desc {
    Char(set) => {
      let mut size = 0
      for (_, hi) in set.intervals() {
        // An astral interval lowers to at most three pairs, their sequences
        // an alternation and an optional BMP part. BMP intervals need one interval.
        size = checked_size_add(size, if hi > 0xffff { 12 } else { 1 }, cap)
      }
      Int32::max(1, size)
    }
    Assertion(_) => 1
    Capture(inner, ..) => expanded_size(inner, cap)
    Sequence(items) | Alternation(items) => {
      let mut size = 1
      for item in items {
        size = checked_size_add(size, expanded_size(item, cap), cap)
      }
      size
    }
    Quantifier(q, inner) => {
      let size = expanded_size(inner, cap)
      let copies = q.max.unwrap_or(Int32::max(1, q.min))
      guard copies <= cap / size else { raise CompilationLimit(Expansion) }
      checked_size_add(size * copies, 2, cap)
    }
  }
}

///|
fn erase_captures(pattern : @re.Pattern) -> @re.Pattern {
  match pattern.desc {
    Capture(inner, ..) => erase_captures(inner)
    Char(_) | Assertion(_) => pattern
    Sequence(items) => @re.seq(items.map(erase_captures))
    Alternation(items) => @re.alt(items.map(erase_captures))
    Quantifier(q, inner) => @re.quantifier(erase_captures(inner), q)
  }
}

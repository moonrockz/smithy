///|
pub(all) suberror ConfigurationError {
  ConfigurationError(String)
} derive(Debug)

///|
pub(all) enum CompileLimit {
  SourceLength
  Nesting
  Expansion
} derive(Eq, Debug)

///|
pub(all) suberror CompileError {
  InvalidPattern(String)
  UnsupportedPattern(String)
  CompilationLimit(CompileLimit)
} derive(Debug)

///|
/// Finite compilation bounds. Construct with `CompileLimits::new`.
pub struct CompileLimits {
  priv source_units : Int32
  priv nesting : Int32
  priv expanded_units : Int32
} derive(Eq, Debug)

///|
pub fn CompileLimits::new(
  source_units~ : Int32 = 4096,
  nesting~ : Int32 = 32,
  expanded_units~ : Int32 = 1024,
) -> CompileLimits raise ConfigurationError {
  guard source_units > 0 &&
    source_units <= 1048576 &&
    nesting > 0 &&
    nesting <= 64 &&
    expanded_units > 0 &&
    expanded_units <= 65536 else {
    raise ConfigurationError(
      "I expected source units 1..1048576, nesting 1..64 and expanded units 1..65536.",
    )
  }
  { source_units, nesting, expanded_units, }
}

///|
/// A finite search allowance. Zero represents an already-spent allowance.
pub struct WorkLimit {
  priv units : Int32
} derive(Eq, Debug)

///|
pub fn WorkLimit::new(units : Int32) -> WorkLimit raise ConfigurationError {
  guard units >= 0 && units <= 10000000 else {
    raise ConfigurationError("I expected a work limit of 0..10000000.")
  }
  { units, }
}

///|
pub fn WorkLimit::units(self : WorkLimit) -> Int32 {
  self.units
}

///|
/// Complete carries the Boolean result and used units. Exhausted carries used units.
pub(all) enum MatchOutcome {
  Complete(Bool, Int32)
  Exhausted(Int32)
} derive(Eq, Debug)

///|
pub fn MatchOutcome::used(self : MatchOutcome) -> Int32 {
  match self {
    Complete(_, used) | Exhausted(used) => used
  }
}

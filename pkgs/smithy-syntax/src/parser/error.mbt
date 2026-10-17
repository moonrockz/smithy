///|
/// A syntax error, carrying its finished diagnostic. Raised inside a
/// statement; `parse` catches it, records it and recovers.
pub(all) suberror ParseError {
  ParseError(@diagnostic.Diagnostic)
} derive(Eq, Debug)

///|
/// The diagnostic the error carries.
pub fn ParseError::diagnostic(self : ParseError) -> @diagnostic.Diagnostic {
  let ParseError(d) = self
  d
}

///|
/// The IDL version a file declares with `$version`.
pub(all) enum Version {
  V1
  V2
} derive(Eq, Debug, Hash)

///|
/// `1`, `1.0`, `2`, `2.0`, else `None`.
pub fn Version::of(text : String) -> Version? {
  match text {
    "1" | "1.0" => Some(V1)
    "2" | "2.0" => Some(V2)
    _ => None
  }
}

///|
/// What `parse` returns. `ast` is the (possibly partial) tree whenever at
/// least one statement parsed, and an empty `IdlFile` (with an empty span)
/// for a file with no tokens (empty or only comments); it is `None` only
/// when the file has tokens and every statement failed. `cst` has every
/// token. `version` is the declared `$version`, `None` when absent.
pub(all) struct ParseResult {
  ast : @ast.IdlFile?
  cst : @cst.IdlCst
  version : Version?
  diagnostics : ArrayView[@diagnostic.Diagnostic]
} derive(Eq, Debug)

///|
/// Whether any diagnostic is an error (not just a warning).
pub fn ParseResult::has_errors(self : ParseResult) -> Bool {
  self.diagnostics.iter().any(d => d.is_error())
}

///|
/// Only the diagnostics that are errors.
pub fn ParseResult::errors(self : ParseResult) -> Array[@diagnostic.Diagnostic] {
  self.diagnostics.iter().filter(d => d.is_error()).collect()
}

///|
/// A nesting count of node values, member blocks and trait bodies.
pub struct Depth(Int32) derive(Eq, Compare, Debug)

///|
/// The shallowest depth: not nested at all.
pub fn Depth::zero() -> Depth {
  Depth(0)
}

///|
/// One level deeper.
pub fn Depth::deeper(self : Depth) -> Depth {
  Depth(self.0 + 1)
}

///|
/// One level shallower; never goes below zero.
pub fn Depth::shallower(self : Depth) -> Depth {
  if self.0 > 0 {
    Depth(self.0 - 1)
  } else {
    self
  }
}

///|
/// Deepest nesting the parser enters; deeper text is `SM-PARSE-010`, never
/// a stack overflow.
pub let max_nesting : Depth = Depth(100)

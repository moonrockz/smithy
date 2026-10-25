///|
/// Compare two texts by code unit, so that `"abc"` is before `"bb"`. The
/// derived `Compare` of `String` orders by length first.
fn lexical(a : String, b : String) -> Int32 {
  a.lexical_compare(b)
}

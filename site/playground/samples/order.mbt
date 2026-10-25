///|
/// Order by UTF-16 code unit, then by length. `String::compare` orders by
/// length first, so an order of names, paths or shape IDs cannot use it. The
/// tour and the playground core share this one order.
pub fn compare_code_units(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

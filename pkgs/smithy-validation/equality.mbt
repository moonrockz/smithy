///|
fn[V] object_values(node : ValueNode[V]) -> Array[(String, V)]? {
  match node {
    Object(fields) => Some(fields)
    LocatedObject(fields) => Some(fields.map(f => (f.name, f.value)))
    _ => None
  }
}

///|
fn[V : ValueView] equivalent(
  left : V,
  right : V,
  budget : Budget,
  path : InstancePath,
  shape : @smithy.ShapeId,
) -> Bool {
  let stack = [(left, right, 0)]
  while stack.pop() is Some((a, b, depth)) {
    if depth > budget.limits.depth {
      budget.stop(path, shape, "depth")
      return false
    }
    if !budget.charge(path, shape) {
      return false
    }
    let a = a.inspect()
    let b = b.inspect()
    match (a, b) {
      (Null, Null) => ()
      (Boolean(a), Boolean(b)) if a == b => ()
      (Number(a), Number(b)) if a == b => ()
      (String(a), String(b)) if a == b => ()
      (Array(a), Array(b)) if a.length() == b.length() => {
        if !budget.room(path, shape, a.length(), pending=stack.length()) {
          return false
        }
        for i = a.length() - 1; i >= 0; i = i - 1 {
          stack.push((a[i], b[i], depth + 1))
        }
      }
      _ => {
        guard object_values(a) is Some(a) &&
          object_values(b) is Some(b) &&
          a.length() == b.length() else {
          return false
        }
        if !budget.room(path, shape, a.length(), pending=stack.length()) ||
          !budget.charge(path, shape, units=a.length()) {
          return false
        }
        let a = a.copy()
        let b = b.copy()
        a.sort_by((a, b) => a.0.lexical_compare(b.0))
        b.sort_by((a, b) => a.0.lexical_compare(b.0))
        for i = a.length() - 1; i >= 0; i = i - 1 {
          if a[i].0 != b[i].0 {
            return false
          }
          stack.push((a[i].1, b[i].1, depth + 1))
        }
      }
    }
  }
  true
}

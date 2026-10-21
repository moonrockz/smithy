///|
fn[V] object_values(node : ValueNode[V]) -> Array[(String, V)]? {
  match node {
    Object(fields) => Some(fields)
    LocatedObject(fields) => Some(fields.map(f => (f.name, f.value)))
    NativeObject(fields) => {
      let result : Array[(String, V)] = []
      for (name, value) in fields {
        guard name is Some(name) else { return None }
        result.push((name, value))
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn[V] object_count(node : ValueNode[V]) -> Int32? {
  match node {
    Object(fields) => Some(fields.length())
    LocatedObject(fields) => Some(fields.length())
    NativeObject(fields) => Some(fields.length())
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
  config : Config,
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
    if !budget.room(path, shape, a.expansion_size(), pending=stack.length()) ||
      !budget.room(path, shape, b.expansion_size(), pending=stack.length()) {
      return false
    }
    let a = a.inspect()
    let b = b.inspect()
    if a is Annotated(annotations, _) &&
      !budget.charge(path, shape, units=annotations.length()) {
      return false
    }
    if b is Annotated(annotations, _) &&
      !budget.charge(path, shape, units=annotations.length()) {
      return false
    }
    if config.profile == NativeProfile {
      if exact_numeric(a) is Some(x) && exact_numeric(b) is Some(y) {
        if x != y {
          return false
        }
        continue
      }
      match (a, b) {
        (Null | Native(TypedNull(_)), Null | Native(TypedNull(_))) => continue
        (Native(Blob(x)), Native(Blob(y))) if x == y => continue
        (Native(Timestamp(x)), Native(Timestamp(y))) if x.full() &&
          y.full() &&
          x == y => continue
        (Native(Float(x)), Native(Float(y))) if config.nonnumeric_floats &&
          ((x != x && y != y) || x == y) => continue
        _ => ()
      }
    }
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
        guard object_count(a) is Some(count) && object_count(b) == Some(count) else {
          return false
        }
        if !budget.room(path, shape, count, pending=stack.length()) ||
          !budget.charge(path, shape, units=count) {
          return false
        }
        guard object_values(a) is Some(a) && object_values(b) is Some(b) else {
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

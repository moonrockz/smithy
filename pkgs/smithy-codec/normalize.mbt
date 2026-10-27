///|
priv enum NBuild {
  NList(Int32)
  NStruct(Array[(String, Bool)])
  NUnion(String)
  NMap(Array[String])
}

///|
priv enum NTask {
  NVisit(LogicalValue, Target, @validation.InstancePath, Int32)
  NAssemble(NBuild)
  /// A null element or value of a sparse list or map.
  NNull
}

///|
fn entries(value : LogicalValue) -> Array[(String, LogicalValue)]? {
  match value {
    Structure(fields) | Map(fields) | Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn logical_kind(value : LogicalValue) -> String {
  match value {
    Null => "null"
    Boolean(_) => "boolean"
    Number(_) => "number"
    String(_) => "string"
    List(_) => "list"
    Structure(_) => "structure"
    Union(_, _) => "union"
    Map(_) => "map"
    Object(_) => "object"
  }
}

///|
/// Rebuild a caller's value in the contract's logical form: members in declaration order, unions as
/// Union values, maps without duplicate keys, empty-as-absent members dropped. It copies every container,
/// so a later change to the caller's arrays cannot change the result.
fn normalize(
  contract : @contract.WireContract,
  request : Request,
  value : LogicalValue,
) -> LogicalValue? {
  let tasks : Array[NTask] = [
    NVisit(
      value,
      { shape: contract.root, adapter: None, },
      @validation.InstancePath::root(),
      0,
    ),
  ]
  let out : Array[LogicalValue] = []
  let take = fn(n : Int32) {
    let items : Array[LogicalValue] = []
    for _ in 0..<n {
      items.push(out.pop().unwrap())
    }
    items.rev_in_place()
    items
  }
  let mut failed = false
  while tasks.pop() is Some(task) {
    if !request.complete {
      return None
    }
    match task {
      NNull => out.push(Null)
      NAssemble(build) =>
        match build {
          NList(n) => out.push(List(take(n)))
          NStruct(names) => {
            let items = take(names.length())
            let fields : Array[(String, LogicalValue)] = []
            for i, entry in names {
              if !(entry.1 && items[i].is_empty()) {
                fields.push((entry.0, items[i]))
              }
            }
            out.push(Structure(fields))
          }
          NUnion(name) => out.push(Union(name, take(1)[0]))
          NMap(keys) => {
            let items = take(keys.length())
            let fields : Array[(String, LogicalValue)] = []
            for i, key in keys {
              fields.push((key, items[i]))
            }
            out.push(Map(fields))
          }
        }
      NVisit(value, target, path, depth) => {
        if !request.charge(path, target.shape) {
          return None
        }
        if depth > request.limits.depth {
          request.stop(path, target.shape, "depth")
          return None
        }
        let shape = contract.shapes.get(target.shape).unwrap()
        let mismatch = fn(what : String) {
          request.emit(
            KindMismatch,
            path,
            shape.id,
            "I expected a \{what} value, but found \{logical_kind(value)}.",
          )
          failed = true
          out.push(Null)
        }
        match shape.layout {
          Scalar(_) =>
            match value {
              Null | Boolean(_) | Number(_) | String(_) => out.push(value)
              _ =>
                if shape.kind == SimpleKind(Document) {
                  out.push(value)
                } else {
                  mismatch("scalar")
                }
            }
          ListShape =>
            match value {
              List(items) => {
                let m = shape.members[0]
                tasks.push(NAssemble(NList(items.length())))
                for i = items.length() - 1; i >= 0; i = i - 1 {
                  if shape.sparse && items[i] is Null {
                    tasks.push(NNull)
                    continue
                  }
                  tasks.push(
                    NVisit(
                      items[i],
                      { shape: m.target, adapter: m.adapter, },
                      index_path(path, i),
                      depth + 1,
                    ),
                  )
                }
              }
              Null => out.push(Null)
              _ => mismatch("list")
            }
          Dictionary(_) =>
            match entries(value) {
              Some(fields) => {
                let m = shape.members[1]
                let keys : Array[String] = []
                let seen : Set[String] = Set([])
                let visits : Array[NTask] = []
                for field in fields {
                  if seen.contains(field.0) {
                    request.emit(
                      DuplicateKey,
                      field_path(path, field.0),
                      shape.id,
                      "I found a second entry for the key \{field.0.escape()}.",
                    )
                    failed = true
                    continue
                  }
                  seen.add(field.0)
                  keys.push(field.0)
                  if shape.sparse && field.1 is Null {
                    visits.push(NNull)
                    continue
                  }
                  visits.push(
                    NVisit(
                      field.1,
                      { shape: m.target, adapter: m.adapter, },
                      field_path(path, field.0),
                      depth + 1,
                    ),
                  )
                }
                tasks.push(NAssemble(NMap(keys)))
                for i = visits.length() - 1; i >= 0; i = i - 1 {
                  tasks.push(visits[i])
                }
              }
              None => mismatch("map")
            }
          ObjectStructure | TupleStructure(_) =>
            match entries(value) {
              Some(fields) => {
                let slots : Array[LogicalValue?] = Array::make(
                  shape.members.length(),
                  None,
                )
                for field in fields {
                  match shape.member_index(field.0) {
                    None => {
                      request.emit(
                        UnknownMember,
                        field_path(path, field.0),
                        shape.id,
                        "I expected a declared member, but found unknown member \{field.0.escape()}.",
                      )
                      failed = true
                    }
                    Some(i) =>
                      if slots[i] is Some(_) {
                        request.emit(
                          MemberCollision,
                          field_path(path, field.0),
                          shape.members[i].member_id,
                          "I found member \{field.0} twice.",
                        )
                        failed = true
                      } else {
                        slots[i] = Some(field.1)
                      }
                  }
                }
                let names : Array[(String, Bool)] = []
                let visits : Array[NTask] = []
                for i, m in shape.members {
                  if slots[i] is Some(v) {
                    names.push((m.name, m.empty_as_absent))
                    visits.push(
                      NVisit(
                        v,
                        { shape: m.target, adapter: m.adapter, },
                        field_path(path, m.name),
                        depth + 1,
                      ),
                    )
                  }
                }
                tasks.push(NAssemble(NStruct(names)))
                for i = visits.length() - 1; i >= 0; i = i - 1 {
                  tasks.push(visits[i])
                }
              }
              None => mismatch("structure")
            }
          UnionShape(_) => {
            let selected = match value {
              Union(name, payload) => Some((name, payload))
              _ =>
                match entries(value) {
                  Some([(name, payload)]) => Some((name, payload))
                  _ => None
                }
            }
            match selected {
              Some((name, payload)) =>
                match shape.member_index(name) {
                  Some(i) => {
                    let m = shape.members[i]
                    tasks.push(NAssemble(NUnion(name)))
                    tasks.push(
                      NVisit(
                        payload,
                        { shape: m.target, adapter: m.adapter, },
                        field_path(path, name),
                        depth + 1,
                      ),
                    )
                  }
                  None => {
                    request.emit(
                      UnknownTag,
                      path,
                      shape.id,
                      "I expected a declared union member, but found \{name.escape()}.",
                    )
                    failed = true
                    out.push(Null)
                  }
                }
              None => mismatch("union")
            }
          }
        }
      }
    }
  }
  if failed || !request.complete {
    return None
  }
  out.pop()
}

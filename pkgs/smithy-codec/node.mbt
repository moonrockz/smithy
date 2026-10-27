///|
/// A projected logical node with its original input location.
priv enum LKind {
  LNull
  LBool(Bool)
  LNumber(@smithy.NodeNumber)
  LString(String)
  LList(Array[LNode])
  LStruct(Array[(String, LNode)])
  LUnion(String, LNode)
  LMap(Array[(String, LNode)])
  LObject(Array[(String, LNode)])
  LInvalid
}

///|
priv struct LNode {
  kind : LKind
  source : @validation.InstancePath
}

///|
impl @validation.ValueView for LNode with fn inspect(self) {
  let located = fn(fields : Array[(String, LNode)]) {
    @validation.ValueNode::LocatedObject(
      fields.map(f => {
        @validation.LocatedField::new(
          f.0,
          f.1,
          @validation.InstancePath::root(),
        )
      }),
    )
  }
  match self.kind {
    LNull | LInvalid => Null
    LBool(b) => Boolean(b)
    LNumber(n) => Number(n)
    LString(s) => String(s)
    LList(items) => Array(items)
    LStruct(fields) | LMap(fields) | LObject(fields) => located(fields)
    LUnion(name, payload) => located([(name, payload)])
  }
}

///|
impl @validation.ValueView for LNode with fn source(self) {
  Some(self.source)
}

///|
impl @validation.ValueView for LogicalValue with fn inspect(self) {
  match self {
    Null => Null
    Boolean(b) => Boolean(b)
    Number(n) => Number(n)
    String(s) => String(s)
    List(items) => Array(items)
    Structure(fields) | Map(fields) | Object(fields) => Object(fields)
    Union(name, payload) => Object([(name, payload)])
  }
}

///|
fn LKind::is_empty(self : LKind) -> Bool {
  match self {
    LList(items) => items.is_empty()
    LStruct(fields) | LMap(fields) | LObject(fields) => fields.is_empty()
    _ => false
  }
}

///|
fn LogicalValue::is_empty(self : LogicalValue) -> Bool {
  match self {
    List(items) => items.is_empty()
    Structure(fields) | Map(fields) | Object(fields) => fields.is_empty()
    _ => false
  }
}

///|
priv enum Strip {
  Enter(LNode)
  Exit(LKind, Int32)
}

///|
/// Drop source locations. Uses an explicit stack.
fn LNode::to_logical(self : LNode) -> LogicalValue {
  let tasks : Array[Strip] = [Enter(self)]
  let out : Array[LogicalValue] = []
  let take = fn(n : Int32) -> Array[LogicalValue] {
    let items : Array[LogicalValue] = []
    for _ in 0..<n {
      items.push(out.pop().unwrap())
    }
    items.rev_in_place()
    items
  }
  while tasks.pop() is Some(task) {
    match task {
      Enter(node) =>
        match node.kind {
          LNull | LInvalid => out.push(Null)
          LBool(b) => out.push(Boolean(b))
          LNumber(n) => out.push(Number(n))
          LString(s) => out.push(String(s))
          LList(items) => {
            tasks.push(Exit(node.kind, items.length()))
            for i = items.length() - 1; i >= 0; i = i - 1 {
              tasks.push(Enter(items[i]))
            }
          }
          LStruct(fields) | LMap(fields) | LObject(fields) => {
            tasks.push(Exit(node.kind, fields.length()))
            for i = fields.length() - 1; i >= 0; i = i - 1 {
              tasks.push(Enter(fields[i].1))
            }
          }
          LUnion(_, payload) => {
            tasks.push(Exit(node.kind, 1))
            tasks.push(Enter(payload))
          }
        }
      Exit(kind, n) => {
        let items = take(n)
        let named = fn(fields : Array[(String, LNode)]) {
          let out : Array[(String, LogicalValue)] = []
          for i, f in fields {
            out.push((f.0, items[i]))
          }
          out
        }
        out.push(
          match kind {
            LList(_) => List(items)
            LStruct(fields) => Structure(named(fields))
            LMap(fields) => Map(named(fields))
            LObject(fields) => Object(named(fields))
            LUnion(name, _) => Union(name, items[0])
            _ => Null
          },
        )
      }
    }
  }
  out.pop().unwrap()
}

///|
fn field_path(
  path : @validation.InstancePath,
  name : String,
) -> @validation.InstancePath {
  path.field(name) catch {
    _ => path
  }
}

///|
fn index_path(
  path : @validation.InstancePath,
  index : Int32,
) -> @validation.InstancePath {
  path.index(index) catch {
    _ => path
  }
}

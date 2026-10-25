///|
fn load_model(text : String) -> @smithy.Model {
  @smithy.Loader::new().add_idl("a.smithy", text).assemble().model.unwrap()
}

///|
fn id_of(text : String) -> @smithy.ShapeId {
  @smithy.ShapeId::parse(text).unwrap()
}

///|
fn index_of(order : Array[@smithy.ShapeId], text : String) -> Int32 {
  let id = id_of(text)
  for i, item in order {
    if item == id {
      return i
    }
  }
  -1
}

///|
fn texts(ids : Array[@smithy.ShapeId]) -> Array[String] {
  ids.map(id => id.to_string())
}

///|
fn without_members(ids : Array[@smithy.ShapeId]) -> Array[@smithy.ShapeId] {
  ids.filter(id => id.member_name() is None)
}

///|
test "closure follows operations, errors and members but not traits" {
  let model = load_model(
    (
      #|$version: "2"
      #|namespace example
      #|
      #|@trait
      #|structure myTrait { ref: Hidden }
      #|
      #|structure Hidden {}
      #|
      #|service S { operations: [Op], errors: [E] }
      #|
      #|operation Op { input: In, output: Out }
      #|
      #|structure In { item: Item }
      #|
      #|@myTrait(ref: {})
      #|structure Item { name: String }
      #|
      #|structure Out {}
      #|
      #|@error("client")
      #|structure E {}
    ),
  )
  let closure = texts(@codegen.service_closure(model, id_of("example#S")))
  for
    name in [
      "example#S", "example#Op", "example#In", "example#Out", "example#E", "example#Item",
      "example#In$item", "smithy.api#String",
    ] {
    assert_true(closure.contains(name), msg="closure lacks \{name}")
  }
  assert_false(closure.contains("example#Hidden"))
  assert_false(closure.contains("example#myTrait"))
  let sorted = closure.copy()
  sorted.sort_by((a, b) => a.lexical_compare(b))
  assert_eq(closure, sorted)
}

///|
test "closure follows resources, lifecycle operations and identifiers" {
  let model = load_model(
    (
      #|$version: "2"
      #|namespace example
      #|
      #|service S { resources: [R] }
      #|
      #|resource R {
      #|  identifiers: { id: Id }
      #|  read: GetR
      #|  list: ListRs
      #|  operations: [Extra]
      #|  collectionOperations: [Bulk]
      #|  resources: [Child]
      #|}
      #|
      #|string Id
      #|
      #|@readonly
      #|operation GetR { input: GetRInput }
      #|
      #|@input
      #|structure GetRInput { @required id: Id }
      #|
      #|@readonly
      #|operation ListRs {}
      #|
      #|operation Extra {}
      #|
      #|operation Bulk {}
      #|
      #|resource Child { identifiers: { childId: ChildId } }
      #|
      #|string ChildId
    ),
  )
  let closure = texts(@codegen.service_closure(model, id_of("example#S")))
  for
    name in [
      "example#R", "example#Id", "example#GetR", "example#ListRs", "example#Extra",
      "example#Bulk", "example#Child", "example#ChildId",
    ] {
    assert_true(closure.contains(name), msg="closure lacks \{name}")
  }
}

///|
test "closure of a missing service is empty" {
  let model = load_model("$version: \"2\"\nnamespace example\nstructure A {}\n")
  assert_eq(@codegen.service_closure(model, id_of("example#Missing")), [])
}

///|
test "dependencies come first" {
  let model = load_model(
    "$version: \"2\"\nnamespace example\nstructure A { b: B }\nstructure B { c: C }\nstructure C {}\n",
  )
  let order = @codegen.topological_order(model, [
    id_of("example#A"),
    id_of("example#B"),
    id_of("example#C"),
  ])
  assert_true(index_of(order, "example#C") < index_of(order, "example#B"))
  assert_true(index_of(order, "example#B") < index_of(order, "example#A"))
  assert_eq(order.length(), 3)
}

///|
test "recursive shapes come last and in name order" {
  let model = load_model(
    "$version: \"2\"\nnamespace example\nstructure Tree { children: TreeList }\nlist TreeList { member: Tree }\nstructure Leaf {}\n",
  )
  let ids = model.shapes
    .keys()
    .filter(id => id.namespace() == "example")
    .collect()
  let order = @codegen.topological_order(model, ids)
  assert_eq(order.length(), ids.length())
  let plain = without_members(order)
  assert_eq(texts(plain), ["example#Leaf", "example#Tree", "example#TreeList"])
  // Every shape of the cycle, members included, follows Leaf.
  assert_true(index_of(order, "example#Leaf") == 0)
}

///|
test "a self reference counts as a cycle" {
  let model = load_model(
    "$version: \"2\"\nnamespace example\nstructure Node { next: Node }\nstructure Alpha {}\nstructure Zed { n: Node }\n",
  )
  let ids = model.shapes
    .keys()
    .filter(id => id.namespace() == "example")
    .collect()
  let order = without_members(@codegen.topological_order(model, ids))
  assert_eq(texts(order), ["example#Alpha", "example#Node", "example#Zed"])
}

///|
test "a shape that is not in the model has no edges" {
  let model = load_model("$version: \"2\"\nnamespace example\nstructure A {}\n")
  let order = @codegen.topological_order(model, [
    id_of("example#Gone"),
    id_of("example#A"),
    id_of("example#A"),
  ])
  assert_eq(texts(order), ["example#A", "example#Gone"])
}

///|
test "the order does not depend on the insertion order" {
  let forward = load_model(
    "$version: \"2\"\nnamespace example\nstructure A { b: B }\nstructure B { c: C }\nstructure C {}\nstructure Tree { kids: Kids }\nlist Kids { member: Tree }\nstructure Z {}\n",
  )
  let backward = load_model(
    "$version: \"2\"\nnamespace example\nstructure Z {}\nlist Kids { member: Tree }\nstructure Tree { kids: Kids }\nstructure C {}\nstructure B { c: C }\nstructure A { b: B }\n",
  )
  let a = @codegen.topological_order(
    forward,
    forward.shapes.keys().filter(id => id.namespace() == "example").collect(),
  )
  let b = @codegen.topological_order(
    backward,
    backward.shapes.keys().filter(id => id.namespace() == "example").collect(),
  )
  assert_eq(a, b)
}

///|
test "a chain of 20000 structures does not overflow the stack" {
  let count = 20000
  let text = StringBuilder()
  text.write_string("$version: \"2\"\nnamespace example\n")
  text.write_string("service Svc { operations: [Op] }\n")
  text.write_string("operation Op { input: S0 }\n")
  for i in 0..<count {
    if i + 1 < count {
      text.write_string("structure S\{i} { next: S\{i + 1} }\n")
    } else {
      text.write_string("structure S\{i} {}\n")
    }
  }
  let model = load_model(text.to_string())
  let closure = @codegen.service_closure(model, id_of("example#Svc"))
  let ours = @codegen.topological_order(model, closure).filter(id => {
    id.namespace() == "example" && id.member_name() is None
  })
  assert_eq(ours.length(), count + 2)
  assert_eq(ours[0], id_of("example#S19999"))
  assert_eq(ours[count - 1], id_of("example#S0"))
  assert_eq(ours[count], id_of("example#Op"))
  assert_eq(ours[count + 1], id_of("example#Svc"))
}

///|
test "a cycle comes after the other shapes that are ready" {
  let model = load_model(
    "$version: \"2\"\nnamespace example\nstructure Aaa { b: Bbb }\nstructure Bbb { a: Aaa }\nstructure Zzz {}\n",
  )
  let order = @codegen.topological_order(model, [
    id_of("example#Aaa"),
    id_of("example#Bbb"),
    id_of("example#Zzz"),
  ])
  assert_eq(texts(order), ["example#Zzz", "example#Aaa", "example#Bbb"])
}

///|
test "a shape that depends on a cycle comes after it, whatever its name" {
  let model = load_model(
    "$version: \"2\"\nnamespace example\nstructure Aaa { m: Mmm }\nstructure Mmm { n: Nnn }\nstructure Nnn { m: Mmm }\nstructure Zzz {}\n",
  )
  let order = @codegen.topological_order(model, [
    id_of("example#Aaa"),
    id_of("example#Mmm"),
    id_of("example#Nnn"),
    id_of("example#Zzz"),
  ])
  assert_eq(texts(order), [
    "example#Zzz", "example#Mmm", "example#Nnn", "example#Aaa",
  ])
}

///|
/// Collects shape names and skips each shape's members.
struct ShapeNames(Array[String])

///|
impl @traversal.Visitor for ShapeNames with fn visit_shape(self, n) {
  if n is Shape(s) {
    self.0.push(s.shape.name().value)
  }
  SkipChildren
}

///|
test "a visitor collects shape names" {
  let names = ShapeNames([])
  @traversal.accept(root_of(three_shapes), names)
  assert_eq(names.0, ["A", "B", "C"])
}

///|
/// Logs every method that is called, by name.
struct Calls(Array[String])

///|
impl @traversal.Visitor for Calls with fn visit_file(self, _) {
  self.0.push("file")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn visit_statement(self, _) {
  self.0.push("statement")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn visit_shape(self, _) {
  self.0.push("shape")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn visit_member(self, _) {
  self.0.push("member")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn visit_trait(self, _) {
  self.0.push("trait")
  Stop
}

///|
impl @traversal.Visitor for Calls with fn visit_value(self, _) {
  self.0.push("value")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn visit_comment(self, _) {
  self.0.push("comment")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn visit_other(self, _) {
  self.0.push("other")
  Continue
}

///|
impl @traversal.Visitor for Calls with fn leave(self, _) {
  self.0.push("leave")
}

///|
test "a visitor stops at the first trait" {
  let calls = Calls([])
  @traversal.accept(root_of(tiny), calls)
  assert_eq(
    calls.0.join(" "),
    "file statement other leave value leave leave statement other leave leave shape trait",
  )
}

///|
/// Implements nothing: every default is used.
struct Nothing {}

///|
impl @traversal.Visitor for Nothing

///|
test "a visitor with only defaults visits everything" {
  let root = root_of(every_form)
  @traversal.accept(root, Nothing::{ })
  let mut n = 0
  @traversal.walk(root, _ => {
    n = n + 1
    Continue
  })
  assert_eq(n, all_nodes(root).length())
}

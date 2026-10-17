///|
/// Records `+tag` and `-tag` and the method each node reaches, steered by a
/// policy.
struct Recorder {
  policy : Policy
  events : Array[String]
  methods : Array[(String, String, String)]
  mut k : Int32
}

///|
fn Recorder::visit(
  self : Recorder,
  method : String,
  n : @traversal.NodeRef,
) -> @traversal.Control {
  self.events.push("+" + tag(n))
  self.methods.push((n.category(), n.kind(), method))
  self.k = self.k + 1
  decide(self.policy, self.k - 1)
}

///|
impl @traversal.Visitor for Recorder with fn visit_file(self, n) {
  self.visit("file", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_statement(self, n) {
  self.visit("statement", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_shape(self, n) {
  self.visit("shape", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_member(self, n) {
  self.visit("member", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_trait(self, n) {
  self.visit("trait", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_value(self, n) {
  self.visit("value", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_comment(self, n) {
  self.visit("comment", n)
}

///|
impl @traversal.Visitor for Recorder with fn visit_other(self, n) {
  self.visit("other", n)
}

///|
impl @traversal.Visitor for Recorder with fn leave(self, n) {
  self.events.push("-" + tag(n))
}

///|
/// The method each category must reach.
fn method_of(category : String) -> String {
  match category {
    "file" => "file"
    "control" | "metadata" | "namespace" | "use" => "statement"
    "shape" => "shape"
    "member" => "member"
    "trait" => "trait"
    "value" | "entry" => "value"
    "doc" | "comment" => "comment"
    _ => "other"
  }
}

///|
fn accept_agrees(text : String, p : Policy) -> Bool {
  guard maybe_root(text) is Some(root) else { return true }
  let p = policy_for(root, p)
  let r = { policy: p, events: [], methods: [], k: 0, }
  @traversal.accept(root, r)
  r.events == walk_events(root, p) &&
  r.methods.iter().all(m => m.2 == method_of(m.0))
}

///|
test "law: accept agrees with walk and calls the method of each category" {
  @quickcheck.check(
    (input : (@lawkit.EditedModel, Policy)) => {
      accept_agrees(input.0.text(), input.1)
    },
    count=200,
    max_size=16,
    seed=8081,
  )
  @quickcheck.check(
    (input : (@lawkit.SmithyText, Policy)) => {
      accept_agrees(input.0.text(), input.1)
    },
    count=300,
    max_size=16,
    seed=8082,
  )
}

///|
test "every kind table row reaches its visitor method" {
  let seen : Map[String, String] = Map([])
  for root in kind_roots() {
    let r = { policy: Policy([Continue], None), events: [], methods: [], k: 0, }
    @traversal.accept(root, r)
    for (category, kind, method) in r.methods {
      assert_eq(method, method_of(category), msg="\{category}/\{kind}")
      seen["\{category}/\{kind}"] = method
    }
  }
  for row in @traversal.kind_table() {
    assert_eq(
      seen.get("\{row.0}/\{row.1}"),
      Some(method_of(row.0)),
      msg="\{row.0}/\{row.1}",
    )
  }
}

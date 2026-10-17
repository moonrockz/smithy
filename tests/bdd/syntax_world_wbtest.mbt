///|
/// Scenario state shared by the three features.
struct SyntaxWorld {
  mut source : @syntax.SourceText
  mut result : @syntax.ParseResult?
}

///|
/// Start a scenario before parsing any source.
fn SyntaxWorld::new() -> SyntaxWorld {
  { source: @syntax.SourceText::new(""), result: None, }
}

///|
/// Require the result produced by the parse step.
fn SyntaxWorld::parsed(self : SyntaxWorld) -> @syntax.ParseResult raise {
  guard self.result is Some(r) else { fail("the model was not parsed yet") }
  r
}

///|
/// Require an AST from the scenario result.
fn SyntaxWorld::file(self : SyntaxWorld) -> @syntax.IdlFile raise {
  guard self.parsed().ast is Some(f) else { fail("no AST") }
  f
}

///|
/// Find a declared shape by its source name.
fn SyntaxWorld::shape(
  self : SyntaxWorld,
  name : String,
) -> @syntax.ShapeStatement raise {
  for s in self.file().shapes() {
    if s.shape.name().value == name {
      return s
    }
  }
  fail("no shape named \{name}")
}

///|
/// `Shape$member`.
fn SyntaxWorld::member_of(
  self : SyntaxWorld,
  id : String,
) -> @syntax.Member raise {
  guard id.find("$") is Some(i) else { fail("member id needs a $: \{id}") }
  let shape = self.shape(id.unsafe_substring(start=0, end=i))
  let member_name = id.unsafe_substring(start=i + 1, end=id.length())
  guard shape.shape is Aggregate(members~, ..) else {
    fail("\{id}: not an aggregate shape")
  }
  for m in members {
    if m.name.value == member_name {
      return m
    }
  }
  fail("no member \{id}")
}

///|
/// Require the first diagnostic from the scenario result.
fn SyntaxWorld::first(self : SyntaxWorld) -> @syntax.Diagnostic raise {
  let result = self.parsed()
  guard result.diagnostics.length() > 0 else { fail("no diagnostics") }
  result.diagnostics[0]
}

///|
/// The unqualified trait name used by acceptance assertions.
fn trait_name(t : @syntax.Trait) -> String {
  t.id.value.name
}

///|
impl @moonspec.World for SyntaxWorld with fn configure(self, setup) {
  setup.given1("the Smithy model:", fn(doc : @moonspec.DocString) {
    self.source = @syntax.SourceText::new(doc.content)
  })
  setup.given2("the Smithy model {string}:", fn(
    name : String,
    doc : @moonspec.DocString,
  ) {
    self.source = @syntax.SourceText::new(doc.content, name~)
  })
  setup.when0("I parse the model", fn() {
    self.result = Some(@syntax.parse(self.source))
  })
  setup.then0("there are no diagnostics", fn() raise {
    @expect.expect(self.parsed().diagnostics.map(d => d.code)).to_equal([])
  })
  setup.then0("there are no errors", fn() raise {
    @expect.expect(self.parsed().has_errors()).to_be_false()
  })
  setup.then1("there is {int} error", fn(n : Int32) raise {
    @expect.expect(self.parsed().errors().length()).to_equal(n)
  })
  setup.then1("the diagnostics are {string}", fn(codes : String) raise {
    let expected = codes.split(", ").map(s => s.to_owned()).collect()
    @expect.expect(self.parsed().diagnostics.map(d => d.code)).to_equal(
      expected,
    )
  })
  setup.then1("the version is {string}", fn(v : String) raise {
    let expected = if v == "none" {
      None
    } else {
      guard @syntax.Version::of(v) is Some(version) else {
        fail("unknown expected version \{v}")
      }
      Some(version)
    }
    @expect.expect(self.parsed().version).to_equal(expected)
  })
  setup.then1("the namespace is {string}", fn(ns : String) raise {
    @expect.expect(self.file().namespace.map(n => n.namespace.value)).to_equal(
      Some(ns),
    )
  })
  setup.then1("the shapes are {string}", fn(names : String) raise {
    let expected = names.split(", ").map(s => s.to_owned()).collect()
    @expect.expect(self.file().shapes().map(s => s.shape.name().value)).to_equal(
      expected,
    )
  })
  setup.then1("the shapes include {string}", fn(name : String) raise {
    @expect.expect(
      self.file().shapes().map(s => s.shape.name().value).contains(name),
    ).to_be_true()
  })
  setup.then2("the shape {string} has docs {string}", fn(
    name : String,
    docs : String,
  ) raise {
    @expect.expect(self.shape(name).docs.map(d => d.text).join("\n")).to_equal(
      docs,
    )
  })
  setup.then2("the shape {string} has the traits {string}", fn(
    name : String,
    traits : String,
  ) raise {
    let expected = traits.split(", ").map(s => s.to_owned()).collect()
    @expect.expect(self.shape(name).traits.map(trait_name)).to_equal(expected)
  })
  setup.then2("the member {string} targets {string}", fn(
    id : String,
    target : String,
  ) raise {
    guard self.member_of(id).target is Explicit(t) else {
      fail("\{id} is elided")
    }
    @expect.expect(t.value.to_string()).to_equal(target)
  })
  setup.then3("the member {string} targets {string} with default {string}", fn(
    id : String,
    target : String,
    default : String,
  ) raise {
    let m = self.member_of(id)
    guard m.target is Explicit(t) else { fail("\{id} is elided") }
    @expect.expect(t.value.to_string()).to_equal(target)
    @expect.expect(m.default.bind(v => v.as_string())).to_equal(Some(default))
  })
  setup.then1("the member {string} is elided", fn(id : String) raise {
    @expect.expect(self.member_of(id).target is Elided).to_be_true()
  })
  setup.then3("the trait {string} on {string} has the string value:", fn(
    trait_ : String,
    shape : String,
    doc : @moonspec.DocString,
  ) raise {
    for t in self.shape(shape).traits {
      if trait_name(t) == trait_ {
        guard t.body is Some(Node(v)) else {
          fail("trait \{trait_} has no node value")
        }
        @expect.expect(v.as_string()).to_equal(Some(doc.content))
        return
      }
    }
    fail("no trait \{trait_} on \{shape}")
  })
  setup.then0("the CST prints the model back unchanged", fn() raise {
    @expect.expect(self.parsed().cst.to_source()).to_equal(self.source.text())
  })
  setup.then1("the CST has {int} skipped statement", fn(n : Int32) raise {
    @expect.expect(self.parsed().cst.skipped().length()).to_equal(n)
  })
  setup.then1("the first message is {string}", fn(m : String) raise {
    @expect.expect(self.first().message).to_equal(m)
  })
  setup.then1("the first title is {string}", fn(m : String) raise {
    @expect.expect(self.first().title).to_equal(m)
  })
  setup.then1("the first hint is {string}", fn(m : String) raise {
    @expect.expect(self.first().hint).to_equal(Some(m))
  })
  setup.then1("the first diagnostic renders as:", fn(
    doc : @moonspec.DocString,
  ) raise {
    @expect.expect(@syntax.render_plain(self.first(), self.source)).to_equal(
      doc.content,
    )
  })
  setup.then1("the short form is {string}", fn(line : String) raise {
    @expect.expect(@syntax.render_short(self.first(), self.source)).to_equal(
      line,
    )
  })
}

///|
async test "parsing feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/parsing.feature"),
    ]),
  )
  |> ignore
}

///|
async test "diagnostics feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/diagnostics.feature"),
    ]),
  )
  |> ignore
}

///|
async test "recovery feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/recovery.feature"),
    ]),
  )
  |> ignore
}

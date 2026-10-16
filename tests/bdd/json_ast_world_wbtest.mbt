///|
struct JsonAstWorld {
  mut text : String
  mut document : @syntax.JsonAst?
  mut error_path : String?
  mut reference_count : Int32
}

///|
fn JsonAstWorld::new() -> JsonAstWorld {
  { text: "", document: None, error_path: None, reference_count: 0, }
}

///|
fn JsonAstWorld::decoded(self : JsonAstWorld) -> @syntax.JsonAst raise {
  guard self.document is Some(document) else {
    fail("the JSON AST was not decoded")
  }
  document
}

///|
impl @moonspec.World for JsonAstWorld with fn configure(self, setup) {
  setup.given1("the JSON AST document:", fn(doc : @moonspec.DocString) {
    self.text = doc.content
  })
  setup.when0("I decode the JSON AST", fn() raise {
    try {
      self.document = Some(@syntax.parse_json_ast(self.text))
    } catch {
      @json.JsonDecodeError((path, _)) =>
        self.error_path = Some(path.to_string())
      other => raise other
    }
  })
  setup.then2("the JSON shape {string} has type {string}", fn(
    id : String,
    type_ : String,
  ) raise {
    let shape = self.decoded().shapes.unwrap().get(id).unwrap()
    assert_eq(shape.kind.keyword(), type_)
  })
  setup.then0("the JSON AST round trips", fn() raise {
    let encoded = @syntax.encode_json_ast(self.decoded())
    assert_eq(encoded, @json.parse(self.text))
    assert_eq(@syntax.decode_json_ast(encoded), self.decoded())
  })
  setup.then1("the encoded JSON AST contains {string}", fn(
    text : String,
  ) raise {
    assert_true(
      @syntax.encode_json_ast(self.decoded()).stringify().contains(text),
    )
  })
  setup.then1("the JSON AST error path is {string}", fn(path : String) raise {
    assert_eq(self.error_path, Some(path))
  })
  setup.given0("the vendored JSON AST reference corpus", fn() raise {
    assert_true(@tck.json_cases().length() > 0)
  })
  setup.when0("I round trip every JSON AST reference case", fn() raise {
    for case in @tck.json_cases() {
      let document = @syntax.parse_json_ast(case.text)
      if @syntax.encode_json_ast(document) != @json.parse(case.text) {
        fail("encoding changed \{case.path}")
      }
      self.reference_count += 1
    }
  })
  setup.then0("every JSON AST reference case preserves its fields", fn() raise {
    assert_eq(self.reference_count, @tck.json_cases().length())
  })
}

///|
async test "JSON AST feature" {
  @moonspec.run_or_fail(
    JsonAstWorld::new,
    @moonspec.RunOptions::new([
      @moonspec.FeatureSource::File("features/json-ast.feature"),
    ]),
  )
  |> ignore
}

///|
/// The text of a repository file; the tests run in `site/`.
fn repository_file(path : String) -> String raise {
  @fs.read_file_to_string("../" + path)
}

///|
fn validate_sample(path : String) -> (Array[@core.Diagnostic], Int32) raise {
  let session = @core.Session::new()
  match @core.handle(session, Validate(seq=1, model=repository_file(path))) {
    Diagnostics(items~, shapes~, ..) => (items, shapes)
    other => fail(@json.to_json(other).stringify())
  }
}

///|
test "samples: the picker opens the model with a mistake" {
  let source = @samples.manifest[@samples.default_index]
  assert_eq(source.title, "JSON-RPC chat protocol (with a mistake)")
  assert_eq(source.path, "site/playground/samples/chat-error.smithy")
}

///|
test "samples: every model of the picker exists, and only the mistake has errors" {
  for source in @samples.manifest {
    let (items, shapes) = validate_sample(source.path)
    let errors = items.filter(d => {
      d.severity == "ERROR" || d.severity == "DANGER"
    })
    if source.path == "site/playground/samples/chat-error.smithy" {
      assert_eq(errors.length(), 1)
    } else {
      assert_eq(errors, [])
      assert_true(shapes > 0)
    }
  }
}

///|
test "samples: the mistake is peers.smithy with Intger for Integer" {
  let peers = repository_file("examples/json-rpc/peers.smithy")
  let mistake = repository_file("site/playground/samples/chat-error.smithy")
  assert_eq(
    mistake,
    peers.replace(
      old="structure PostMessageOutput { count: Integer }",
      new="structure PostMessageOutput { count: Intger }",
    ),
  )
  assert_true(mistake != peers)
  let (items, _) = validate_sample("site/playground/samples/chat-error.smithy")
  assert_eq(items.length(), 1)
  assert_eq(items[0].code, "Target.UnresolvedShape")
  assert_eq(
    items[0].message,
    "I could not resolve shape example.peers#Intger, referenced by example.peers#PostMessageOutput$count.",
  )
}

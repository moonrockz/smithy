///|
/// The compared events of a one-file model in namespace `example`, as the tour
/// keys them: `id|SEVERITY|shape`, sorted.
fn reference_keys(body : String) -> Array[String] {
  let result = @smithy.Loader::new()
    .add_idl(
      "model.smithy",
      "$version: \"2\"\nnamespace example\n" + body + "\n",
    )
    .assemble()
  let keys = result
    .validation_events()
    .filter(e => {
      e.severity == "ERROR" || e.severity == "DANGER" || e.severity == "WARNING"
    })
    .map(e => {
      e.id +
      "|" +
      e.severity +
      "|" +
      e.shape.map(s => s.to_string()).unwrap_or("-")
    })
  keys.sort()
  keys
}

///|
test "an unknown trait is Model.UnresolvedTrait, as in Smithy" {
  assert_eq(reference_keys("@tag([\"geo\"])\nstructure City {}"), [
    "Model.UnresolvedTrait|ERROR|example#City",
  ])
}

///|
test "a shape without @trait used as a trait is reported on that shape once per use, as in Smithy" {
  assert_eq(
    reference_keys(
      "structure event {}\n@event\nstructure A {}\n@event\nstructure B {}",
    ),
    ["Model|ERROR|example#event", "Model|ERROR|example#event"],
  )
}

///|
test "a with target without @mixin is a Target error, as in Smithy" {
  assert_eq(
    reference_keys("structure Audited {}\nstructure City with [Audited] {}"),
    ["Target|ERROR|example#City"],
  )
}

///|
test "a mixin of another shape type stays a Model error, as in Smithy" {
  assert_eq(
    reference_keys("@mixin\nstring Name\nstructure City with [Name] {}"),
    ["Model|ERROR|example#City"],
  )
}

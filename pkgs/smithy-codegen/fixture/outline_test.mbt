///|
/// The service renames `example.legacy#Item`, because a service closure must
/// have unique shape names. The fixture generator ignores the rename and
/// writes the shape ID name, so the golden file shows the full-name rule.
let orders_idl : Array[String] = [
  (
    #|service Orders {
    #|    version: "2026-01-01"
    #|    operations: [GetOrder, ListOrders]
    #|    errors: [Throttled]
    #|    rename: { "example.legacy#Item": "LegacyItem" }
    #|}
  ),
  (
    #|operation GetOrder {
    #|    input: GetOrderInput
    #|    output: GetOrderOutput
    #|    errors: [Throttled]
    #|}
  ),
  "operation ListOrders {}",
  (
    #|structure GetOrderInput {
    #|    id: String
    #|}
  ),
  (
    #|structure GetOrderOutput {
    #|    order: Order
    #|    payment: Payment
    #|    categories: CategoryList
    #|}
  ),
  (
    #|@error("client")
    #|structure Throttled {
    #|    message: String
    #|}
  ),
  (
    #|structure Order {
    #|    id: String
    #|    type: OrderType
    #|    items: ItemList
    #|    tags: TagMap
    #|    primary: example.items#Item
    #|    legacy: example.legacy#Item
    #|}
  ),
  (
    #|structure Category {
    #|    children: CategoryList
    #|}
  ),
  (
    #|list CategoryList {
    #|    member: Category
    #|}
  ),
  (
    #|list ItemList {
    #|    member: example.items#Item
    #|}
  ),
  (
    #|map TagMap {
    #|    key: String
    #|    value: String
    #|}
  ),
  (
    #|union Payment {
    #|    card: String
    #|    cash: Currency
    #|}
  ),
  (
    #|enum Currency {
    #|    USD
    #|    EUR
    #|}
  ),
  (
    #|intEnum OrderType {
    #|    STANDARD = 1
    #|    EXPRESS = 2
    #|}
  ),
]

///|
let items_idl : Array[String] = ["structure Item {\n    sku: String\n}"]

///|
let legacy_idl : Array[String] = ["structure Item {\n    code: String\n}"]

///|
fn idl_file(namespace : String, blocks : Array[String]) -> String {
  "$version: \"2\"\nnamespace \{namespace}\n\n" + blocks.join("\n\n") + "\n"
}

///|
fn load_fixture(reverse : Bool) -> @smithy.Model {
  let files = [
    ("orders.smithy", "example.orders", orders_idl),
    ("items.smithy", "example.items", items_idl),
    ("legacy.smithy", "example.legacy", legacy_idl),
  ]
  let loader = @smithy.Loader::new()
  let ordered = if reverse { files.rev() } else { files }
  for file in ordered {
    let (name, namespace, blocks) = file
    loader.add_idl(
      name,
      idl_file(namespace, if reverse { blocks.rev() } else { blocks }),
    )
    |> ignore
  }
  loader.assemble().model.unwrap()
}

///|
fn fixture_model() -> @smithy.Model {
  load_fixture(false)
}

///|
const SETTINGS : String = "{\"service\":\"example.orders#Orders\",\"header\":\"generated\"}"

///|
fn sorted(keys : Iter[String]) -> Array[String] {
  let result = keys.collect()
  result.sort_by((a, b) => a.lexical_compare(b))
  result
}

///|
test "fixture outline golden files" (t : @test.Test) {
  let files = @fixture.plugin(fixture_model(), @json.parse(SETTINGS))
  for path in sorted(files.keys()) {
    t.write("== " + path + " ==\n" + files[path])
  }
  t.snapshot(filename="fixture_outline.txt")
}

///|
test "the outline is the same for any shape insertion order" {
  let settings = @json.parse(SETTINGS)
  let first = @fixture.plugin(load_fixture(false), settings)
  let second = @fixture.plugin(load_fixture(true), settings)
  assert_eq(sorted(first.keys()), sorted(second.keys()))
  for path in first.keys() {
    assert_eq(first[path], second[path])
  }
}

///|
test "the build runs the plugin on a projection, twice the same, and fails a missing service" {
  let config = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"public\":{\"plugins\":{\"codegenFixture\":{\"service\":\"example.orders#Orders\"}}}}}",
  )
  let runner = @build.BuildRunner::new(config).register_plugin(
    "codegenFixture", @fixture.plugin,
  )
  let first = runner.run(fixture_model())
  let second = runner.run(fixture_model())
  assert_true(
    first.contains("public/codegenFixture/example/orders/Order.outline"),
  )
  assert_true(first.contains("public/codegenFixture/dependencies.txt"))
  assert_eq(first, second)
  let missing = @build.BuildConfig::parse(
    "{\"version\":\"1.0\",\"projections\":{\"public\":{\"plugins\":{\"codegenFixture\":{\"service\":\"example.orders#Missing\"}}}}}",
  )
  let failed = @build.BuildRunner::new(missing)
    .register_plugin("codegenFixture", @fixture.plugin)
    .run_result(fixture_model())
  assert_true(
    failed.errors[0].contains(
      "I could not find service shape `example.orders#Missing`",
    ),
  )
}

///|
test "header is absent without the setting" {
  let files = @fixture.plugin(
    fixture_model(),
    @json.parse("{\"service\":\"example.orders#Orders\"}"),
  )
  let order = files["example/orders/Order.outline"]
  assert_eq(
    order.split("\n").next().unwrap().to_owned(),
    "use example.items.Item",
  )
  assert_false(order.contains("// generated"))
  for _, text in files {
    assert_false(text.contains("// generated"))
  }
}

///|
fn build_error_message(
  action : () -> Unit raise @build.BuildError,
) -> String raise {
  try action() catch {
    @build.InvalidBuildConfig(message) => message
  } noraise {
    _ => fail("expected an InvalidBuildConfig error")
  }
}

///|
test "unknown settings fail" {
  let unknown = @json.parse(
    "{\"service\":\"example.orders#Orders\",\"bogus\":true}",
  )
  let message = build_error_message(() => {
    let _ = @fixture.plugin(fixture_model(), unknown)
  })
  assert_true(message.contains("I found unknown setting `bogus`"))
  let number = @json.parse(
    "{\"service\":\"example.orders#Orders\",\"header\":1}",
  )
  let wrong = build_error_message(() => {
    let _ = @fixture.plugin(fixture_model(), number)
  })
  assert_true(wrong.contains("I expected a string for setting `header`"))
}

///|
fn integration_names(
  items : Array[@codegen.Integration[Unit]],
) -> Array[String] {
  items.map(item => item.name)
}

///|
test "integrations sort by constraints, then priority, then name" {
  let items : Array[@codegen.Integration[Unit]] = [
    @codegen.Integration::new("a"),
    @codegen.Integration::new("b", priority=10),
    @codegen.Integration::new("c", run_before=["a"]),
    @codegen.Integration::new("d", run_after=["b"]),
    @codegen.Integration::new("e", run_before=["unknown"]),
  ]
  assert_eq(integration_names(@codegen.sort_integrations(items)), [
    "b", "c", "a", "d", "e",
  ])
}

///|
test "duplicate names and cycles are rejected" {
  let twins : Array[@codegen.Integration[Unit]] = [
    @codegen.Integration::new("a"),
    @codegen.Integration::new("a"),
  ]
  let duplicate = try @codegen.sort_integrations(twins) catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(duplicate, "I found two integrations with the name `a`.")
  let loop_items : Array[@codegen.Integration[Unit]] = [
    @codegen.Integration::new("z", run_before=["y"]),
    @codegen.Integration::new("y", run_before=["z"]),
    @codegen.Integration::new("free"),
  ]
  let cycle = try @codegen.sort_integrations(loop_items) catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  assert_eq(cycle, "I found a cycle in the order of integrations: y, z.")
}

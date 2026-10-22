///|
test "every known code name is accepted and unique within its group" {
  let groups = [rpc_code_names(), value_code_names(), transcript_code_names()]
  assert_eq(groups.map(g => g.length()), [20, 16, 14])
  for group in groups {
    for i, name in group {
      assert_true(ExpectedFinding::new(name) is Some(_))
      for j in 0..<i {
        assert_true(group[j] != name)
      }
    }
  }
  assert_eq(known_code_names().length(), 50)
}

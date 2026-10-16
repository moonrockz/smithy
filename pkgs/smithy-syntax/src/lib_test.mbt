///|
test "the module reports its version" {
  inspect(@syntax.version(), content="0.1.0")
}

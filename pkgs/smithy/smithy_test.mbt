///|
test "library reports a version" {
  inspect(@smithy.version(), content="0.1.1")
  inspect(@smithy.SMITHY_VERSION, content="2.0")
}

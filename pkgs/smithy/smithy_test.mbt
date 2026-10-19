///|
test "library reports a version" {
  inspect(@smithy.version(), content="0.3.0")
  inspect(@smithy.SMITHY_VERSION, content="2.0")
}

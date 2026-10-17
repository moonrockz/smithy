///|
test "the generator produces text and shrinks toward fewer pieces" {
  let t = @lawkit.SmithyText(["a", "bcd"])
  inspect(t.text(), content="abcd")
  let shrunk : Array[@lawkit.SmithyText] = @quickcheck.Shrink::shrink(t).collect()
  inspect(shrunk.length(), content="3")
}

///|
test "the small model is non-empty and ends with a line break" {
  let m = @lawkit.small_model()
  inspect(m.length() > 100, content="true")
  inspect(
    m.has_suffix(
      (
        #|
        #|
      ),
    ),
    content="true",
  )
}

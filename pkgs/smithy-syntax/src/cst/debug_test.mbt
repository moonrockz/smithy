///|
test "debug tokens" {
  let text =
    #|namespace a.b
    #|
    #|string Foo // c
    #|
  let s = @scanner.tokenize_text(text)
  println("Tokens: \{s.tokens.length()}")
  for t in s.tokens {
    println("  \{t.lexeme} -> to_source=\{t.to_source()}")
  }
}

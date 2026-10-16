///|
test "unescape decodes the known escapes and keeps unknown ones" {
  @expect.expect_all(e => {
    e.expect(@scanner.unescape("\"\"")).to_equal("")
    e
    .expect(@scanner.unescape("\"a\\nb\""))
    .to_equal(
      (
        #|a
        #|b
      ),
    )
    e
    .expect(@scanner.unescape("\"\\t\\r\\b\\f\\/\\\\\\\"\""))
    .to_equal("\t\r\u{8}\u{c}/\\\"")
    e.expect(@scanner.unescape("\"\\u00e9\"")).to_equal("é")
    e.expect(@scanner.unescape("\"\\uD83D\\uDE00\"")).to_equal("\u{1F600}")
    e.expect(@scanner.unescape("\"a\\qb\"")).to_equal("a\\qb")
    e.expect(@scanner.unescape("\"\\u12\"")).to_equal("\\u12")
  })
}

///|
test "text_block_value removes incidental whitespace" {
  let block =
    #|"""
    #|    hello
    #|      world
    #|    """
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|hello
      #|  world
      #|
    ),
  )
}

///|
test "the closing quotes on the content's last line keep that line" {
  let block =
    #|"""
    #|  a
    #|  b"""
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|a
      #|b
    ),
  )
}

///|
test "the closing quotes' own line counts toward the common prefix" {
  let block =
    #|"""
    #|      deep
    #|  """
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|    deep
      #|
    ),
  )
}

///|
test "a closing delimiter at the margin keeps all indentation" {
  let block =
    #|"""
    #|    kept
    #|"""
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|    kept
      #|
    ),
  )
}

///|
test "trailing spaces are removed and escapes run after stripping" {
  let block = "\"\"\"\n  a   \n  b\\tc\n  \"\"\""
  inspect(@scanner.text_block_value(block), content="a\nb\tc\n")
}

///|
test "an escaped line break joins lines" {
  let block =
    #|"""
    #|  a\
    #|  b
    #|  """
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|ab
      #|
    ),
  )
}

///|
test "CRLF inside a text block is a line break" {
  let block = "\"\"\"\r\n  a\r\n  b\r\n  \"\"\""
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|a
      #|b
      #|
    ),
  )
}

///|
test "quotes inside a text block" {
  let block =
    #|"""
    #|  say "hi" or ""hey""
    #|  """
  inspect(
    @scanner.text_block_value(block),
    content=(
      #|say "hi" or ""hey""
      #|
    ),
  )
}

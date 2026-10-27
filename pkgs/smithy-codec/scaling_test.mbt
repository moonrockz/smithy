///|
/// The smallest work allowance with which `check` completes.
fn minimal_work(
  prepare : (@codec.CodecLimits) -> @codec.PreparedCodec raise,
  text : String,
) -> Int32 raise {
  let mut low = 1
  let mut high = 10000000
  while low < high {
    let middle = low + (high - low) / 2
    let result = prepare(@codec.CodecLimits::new(work=middle, depth=1024)).check(
      text,
    )
    if result.complete {
      high = middle
    } else {
      low = middle + 1
    }
  }
  low
}

///|
fn wide(n : Int32) -> String {
  let items = Array::make(n, "[\"Num\",1]")
  // A left-leaning chain of Add nodes over n leaves, one array level per node.
  let mut text = items[0]
  for i in 1..<n {
    text = "[\"Add\"," + text + "," + items[i] + "]"
  }
  text
}

///|
test "work grows linearly with input size and depth" {
  let model = load(expr_model)
  let prepare = (limits : @codec.CodecLimits) => {
    @codec.PreparedCodec::prepare(
      model,
      id("example#Expr"),
      profile=Some(profile("array")),
      limits~,
    )
  }
  let w30 = minimal_work(prepare, wide(30))
  let w60 = minimal_work(prepare, wide(60))
  let w120 = minimal_work(prepare, wide(120))
  // Each doubling roughly doubles the work: no repeated expansion of the recursive closure.
  assert_true(w60 * 10 >= w30 * 19 && w60 * 10 <= w30 * 21)
  assert_true(w120 * 10 >= w60 * 19 && w120 * 10 <= w60 * 21)
  // An exhausted budget never reports success or a value.
  let limited = prepare(@codec.CodecLimits::new(work=w120 - 1, depth=1024))
  assert_false(limited.check(wide(120)).complete)
  assert_false(failure(() => ignore(limited.canonicalize(wide(120)))).complete)
}

///|
test "unrelated model content does not change the work of a value" {
  let unrelated = StringBuilder()
  for i in 0..<300 {
    unrelated.write_string(
      "structure Unrelated\{i} { a: Add, b: Expr, c: String }\n",
    )
  }
  let small = load(expr_model)
  let large = load(expr_model + "\n" + unrelated.to_string())
  let text = wide(40)
  let work = fn(model : @smithy.Model) raise {
    minimal_work(
      limits => {
        @codec.PreparedCodec::prepare(
          model,
          id("example#Expr"),
          profile=Some(profile("array")),
          limits~,
        )
      },
      text,
    )
  }
  assert_eq(work(small), work(large))
}

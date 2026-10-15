///|
test "law: deeper then shallower is the identity, and shallower never goes below zero" {
  @quickcheck.check(
    (n : Int32) => {
      let d = {
        let mut d = @parser.Depth::zero()
        for _ in 0..<(if n < 0 { 0 } else { n % 200 }) {
          d = d.deeper()
        }
        d
      }
      d.deeper().shallower() == d &&
      @parser.Depth::zero().shallower() == @parser.Depth::zero() &&
      d.deeper() > d &&
      (d > @parser.max_nesting) == (d.0 > 100)
    },
    count=300,
    seed=1011,
  )
}

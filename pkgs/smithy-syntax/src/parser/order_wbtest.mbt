///|
test "diagnostics at one offset retain scanner then parser emission order" {
  let span = @span.Offset::zero().to(@span.Offset::zero())
  let ds = Array::makei(64, i => {
    @diagnostic.Diagnostic::new(
      code="SM-PARSE-001",
      severity=Error,
      title="order",
      message=i.to_string(),
      span~,
    )
  })
  let ordered = order_diagnostics(ds[:32], ds[32:])
  assert_eq(ordered.map(d => d.message), ds.map(d => d.message))
}

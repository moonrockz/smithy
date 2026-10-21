///|
test "wide Ion containers fail preflight before allocating child views or kind entries" {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "value.smithy", "$version: \"2\"\nnamespace example\ndocument Value",
    )
    .assemble()
  let prepared = PreparedValidator::prepare(
    loaded.model.unwrap(),
    @smithy.ShapeId::parse("example#Value").unwrap(),
    config=@validation.Config::new(limits=@validation.Limits::new(work=1)),
  )
  for
    value in [
      @ion.Ion::list(Array::make(1000, @ion.Ion::int(1))),
      @ion.Ion::sexp(Array::make(1000, @ion.Ion::int(1))),
      @ion.Ion::from_fields(
        Array::make(1000, @ion.Field("same", @ion.Ion::int(1))),
      ),
      @ion.Ion::int(1).with_annotations(
        Array::make(1000, @ion.SymbolToken("tag")),
      ),
    ] {
    let kinds : Map[@validation.InstancePath, @ion.IonType] = Map([])
    let view = IonView::new(value, @validation.InstancePath::root(), kinds)
    let result = prepared.core.validate(view)
    assert_false(result.complete)
    assert_eq(result.findings[0].code, @validation.LimitExceeded)
    assert_eq(kinds.length(), 1)
  }
}

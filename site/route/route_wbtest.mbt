///|
test "parse: landing and docs index" {
  assert_eq(Route::parse(""), Landing)
  assert_eq(Route::parse("/"), Landing)
  assert_eq(Route::parse("index.html"), Landing)
  assert_eq(Route::parse("docs"), DocsIndex)
  assert_eq(Route::parse("docs/"), DocsIndex)
}

///|
test "parse: equivalent path shapes give the same route" {
  assert_eq(Route::parse("docs/smithy-syntax"), Doc("smithy-syntax"))
  assert_eq(Route::parse("/docs/smithy-syntax/"), Doc("smithy-syntax"))
  assert_eq(Route::parse("docs//smithy-syntax"), Doc("smithy-syntax"))
  assert_eq(Route::parse("docs/smithy-syntax/index.html"), Doc("smithy-syntax"))
}

///|
test "parse: anything else is not found" {
  assert_eq(Route::parse("docs/a/b"), NotFound("docs/a/b"))
  assert_eq(Route::parse("blog"), NotFound("blog"))
  assert_eq(Route::parse("migrations/v0.5.0"), NotFound("migrations/v0.5.0"))
}

///|
test "to_path and href" {
  assert_eq(Landing.to_path(), "")
  assert_eq(Doc("smithy-syntax").to_path(), "docs/smithy-syntax")
  assert_eq(DocsIndex.to_path(), "docs")
  assert_eq(href("/smithy/", Landing), "/smithy/")
  assert_eq(
    href("/smithy/next/", Doc("smithy-syntax")),
    "/smithy/next/docs/smithy-syntax/",
  )
  assert_eq(href("/smithy/", DocsIndex), "/smithy/docs/")
}

///|
test "strip_base: paths inside and outside the base" {
  assert_eq(strip_base("/smithy/", "/smithy/docs/x"), Some("docs/x"))
  assert_eq(strip_base("/smithy/", "smithy/docs/x"), Some("docs/x"))
  assert_eq(strip_base("/smithy/next/", "/smithy/next"), Some(""))
  assert_eq(strip_base("/smithy/next/", "/smithy/next/"), Some(""))
  assert_eq(strip_base("/smithy/next/", "/smithy/docs/x"), None)
  assert_eq(strip_base("/smithy/", "/other/docs/x"), None)
  assert_eq(strip_base("/", "/docs/x"), Some("docs/x"))
  assert_eq(strip_base("/smithy/", "/smithy/docs/x/"), Some("docs/x/"))
  assert_eq(Route::parse("docs/x/"), Doc("x"))
}

///|
test "routes round-trip through JSON" {
  for r in [Landing, Doc("smithy-syntax"), DocsIndex, NotFound("x")] {
    let back : Route = @json.from_json(r.to_json())
    assert_eq(back, r)
  }
}

///|
test "strip_base: a sibling prefix is not under the base" {
  assert_eq(strip_base("/smithy/", "/smithyx/docs/x"), None)
}

///|
test "NotFound path round-trips through parse" {
  assert_eq(Route::parse(NotFound("docs/a/b").to_path()), NotFound("docs/a/b"))
}

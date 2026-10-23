///|
test "parse: landing and docs index" {
  assert_eq(Route::parse(""), Landing)
  assert_eq(Route::parse("/"), Landing)
  assert_eq(Route::parse("index.html"), Landing)
  assert_eq(Route::parse("docs"), Doc(default_doc_slug))
  assert_eq(Route::parse("docs/"), Doc(default_doc_slug))
}

///|
test "parse: equivalent path shapes give the same route" {
  assert_eq(Route::parse("docs/configuration"), Doc("configuration"))
  assert_eq(Route::parse("/docs/configuration/"), Doc("configuration"))
  assert_eq(Route::parse("docs//configuration"), Doc("configuration"))
  assert_eq(Route::parse("docs/configuration/index.html"), Doc("configuration"))
  assert_eq(Route::parse("migrations/v0.11.0"), Migration("v0.11.0"))
}

///|
test "parse: anything else is not found" {
  assert_eq(Route::parse("docs/a/b"), NotFound("docs/a/b"))
  assert_eq(Route::parse("blog"), NotFound("blog"))
  assert_eq(Route::parse("migrations"), NotFound("migrations"))
}

///|
test "to_path and href" {
  assert_eq(Landing.to_path(), "")
  assert_eq(Doc("configuration").to_path(), "docs/configuration")
  assert_eq(Migration("v0.11.0").to_path(), "migrations/v0.11.0")
  assert_eq(href("/smithy/", Landing), "/smithy/")
  assert_eq(
    href("/smithy/next/", Doc("configuration")),
    "/smithy/next/docs/configuration/",
  )
  assert_eq(
    href("/smithy/", Migration("v0.11.0")),
    "/smithy/migrations/v0.11.0/",
  )
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
  for r in [Landing, Doc("configuration"), Migration("v0.11.0"), NotFound("x")] {
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

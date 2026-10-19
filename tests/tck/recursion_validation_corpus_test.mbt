///|
test "invalid shape recursion matches the reference" {
  check_validation_events("shape-recursion")
  check_validation_events("shape-recursion-required-trait")
  check_validation_events("shape-recursion-union")
}

///|
test "enum trait validation matches the reference" {
  check_validation_events("enums/enum-trait-validation")
}

///|
test "media type and XML namespace validation match the reference" {
  check_validation_events("mediatype-trait")
  check_validation_events("xml-namespace")
}

///|
test "legacy sets match the reference" {
  check_validation_events("sets/valid-sets")
}

///|
test "enum traits validate names and omitted names without critical errors" {
  let result = @smithy.Loader::new()
    .add_idl(
      "enums.smithy", "$version: \"1.0\"\nnamespace example\n@enum([{value: \"one\", name: \"lower\"}, {value: \"two\"}])\nstring Mixed\n@enum([{value: \"one\"}])\nstring Unnamed\n",
    )
    .assemble()
  let events = result
    .validation_events()
    .filter(event => event.id.has_prefix("Enum"))
  assert_true(
    events
    .iter()
    .any(event => event.id == "EnumTrait.lower" && event.severity == "WARNING"),
  )
  assert_true(
    events
    .iter()
    .any(event => event.id == "EnumTrait" && event.severity == "ERROR"),
  )
  assert_true(
    events
    .iter()
    .any(event => event.id == "EnumNamesPresent" && event.severity == "WARNING"),
  )
}

///|
test "XML namespace URIs distinguish paths queries fragments and authorities" {
  let result = @smithy.Loader::new()
    .add_idl(
      "namespaces.smithy", "$version: \"2.0\"\nnamespace example\n@xmlNamespace(uri: \"path?query:part\")\nstructure ValidQuery {}\n@xmlNamespace(uri: \"http://[::1]/path\")\nstructure ValidIPv6 {}\n@xmlNamespace(uri: \"path[part]\")\nstructure InvalidPath {}\n@xmlNamespace(uri: \"path#one#two\")\nstructure InvalidFragment {}\n@xmlNamespace(uri: \"http://\")\nstructure InvalidAuthority {}\n",
    )
    .assemble()
  let invalid = result
    .validation_events()
    .filter(event => event.id == "XmlNamespaceTrait")
    .map(event => event.shape.unwrap().to_string())
  invalid.sort()
  let expected = [
    "example#InvalidAuthority", "example#InvalidFragment", "example#InvalidPath",
  ]
  expected.sort()
  assert_eq(invalid, expected)
}

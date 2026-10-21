///|
fn fixture(name : String) -> String raise {
  @fs.read_file_to_string("../../tests/tck/openapi/" + name)
}

///|
fn load_fixture(name : String) -> @smithy.Model raise {
  load_fixture_path("upstream/" + name)
}

///|
fn load_fixture_path(name : String) -> @smithy.Model raise {
  let loader = @smithy.Loader::new()
  for input in @openapi.protocol_definitions() {
    ignore(loader.add(input))
  }
  if name.has_suffix(".smithy") {
    ignore(loader.add_idl(name, fixture(name)))
  } else {
    ignore(loader.add_json(name, fixture(name)))
  }
  let result = loader.assemble()
  guard result.model is Some(model) else {
    fail(result.diagnostics.map(d => d.code + ": " + d.message).join("\n"))
  }
  model
}

///|
fn check_reference(
  source : String,
  expected : String,
  service : String,
  version : @openapi.OpenApiVersion,
) -> Unit raise {
  let config = @openapi.Config::new(
    @openapi.ServiceId::parse(service).unwrap(),
    version~,
  )
  let actual = @openapi.convert(load_fixture(source), config)
  assert_eq(actual, @json.parse(fixture("upstream/" + expected)), msg=expected)
}

///|
test "reference service and member documentation" {
  check_reference(
    "documentation-test.smithy",
    "documentation-test.openapi.json",
    "smithy.example#MyDocs",
    @openapi.V3_0_2,
  )
}

///|
test "reference OpenAPI 3.0.2 schema adaptations" {
  check_reference(
    "nullability-and-format.smithy",
    "openapi-3-0-2.openapi.json",
    "example#Example",
    @openapi.V3_0_2,
  )
}

///|
test "reference OpenAPI 3.1.0 JSON Schema 2020-12 adaptations" {
  check_reference(
    "nullability-and-format.smithy",
    "openapi-3-1-0.openapi.json",
    "example#Example",
    @openapi.V3_1_0,
  )
}

///|
test "reference JSON document bodies" {
  check_reference(
    "protocols/adds-json-document-bodies.json",
    "protocols/adds-json-document-bodies.openapi.json",
    "smithy.example#Service",
    @openapi.V3_0_2,
  )
}

///|
fn error_kind(error : @openapi.OpenApiError) -> String {
  match error {
    @openapi.InvalidConfiguration(_) => "configuration"
    @openapi.MissingService(_) => "missing-service"
    @openapi.InvalidService(_) => "invalid-service"
    @openapi.ProtocolResolution(_, _) => "protocol-resolution"
    @openapi.UnsupportedProtocol(_) => "unsupported-protocol"
    @openapi.UnsupportedTrait(_, _) => "unsupported-trait"
    @openapi.PrefixHeaders(_) => "prefix-headers"
    @openapi.GreedyLabel(_) => "greedy-label"
    @openapi.SchemaConversion(_) => "schema"
  }
}

///|
fn pointer_component(text : String) -> String {
  text.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn first_difference(actual : Json, expected : Json) -> String? {
  let pending = [("", actual, expected)]
  while pending.pop() is Some((path, actual, expected)) {
    if actual == expected {
      continue
    }
    match (actual, expected) {
      (Object(actual), Object(expected)) => {
        for key, value in expected {
          guard actual.get(key) is Some(found) else {
            return Some(
              path + "/" + pointer_component(key) + ": missing property",
            )
          }
          pending.push((path + "/" + pointer_component(key), found, value))
        }
        for key, _ in actual {
          if !expected.contains(key) {
            return Some(
              path + "/" + pointer_component(key) + ": unexpected property",
            )
          }
        }
      }
      (Array(actual), Array(expected)) => {
        if actual.length() != expected.length() {
          return Some(
            path +
            ": array length " +
            actual.length().to_string() +
            ", expected " +
            expected.length().to_string(),
          )
        }
        for i = 0; i < actual.length(); i = i + 1 {
          pending.push((path + "/" + i.to_string(), actual[i], expected[i]))
        }
      }
      _ =>
        return Some(
          path +
          ": expected " +
          expected.stringify() +
          ", found " +
          actual.stringify(),
        )
    }
  }
  None
}

///|
fn check_case(test_case : Json) -> Unit raise {
  guard test_case
    is { "id": String(id), "model": String(source), "settings": settings, .. } else {
    fail("Malformed OpenAPI case")
  }
  let model = load_fixture_path(source)
  let result : Result[@openapi.Conversion, @openapi.OpenApiError] = Ok(
    @openapi.convert_result(model, @openapi.Config::from_json(settings)),
  ) catch {
    error => Err(error)
  }
  if test_case is { "error": String(expected), .. } {
    match result {
      Err(error) => assert_eq(error_kind(error), expected, msg=id)
      Ok(_) => fail(id + ": expected conversion failure " + expected)
    }
  } else {
    guard result is Ok(result) else {
      let kind = match result {
        Err(@openapi.SchemaConversion(message)) => "schema: " + message
        Err(error) => error_kind(error)
        _ => "unknown"
      }
      fail(id + ": unexpected " + kind + " conversion failure")
    }
    guard test_case is { "expected": String(expected), .. } else {
      fail(id + ": missing expected document")
    }
    if first_difference(result.document, @json.parse(fixture(expected)))
      is Some(difference) {
      fail(id + ": " + difference)
    }
    if test_case is { "warnings": Number(count, ..), .. } {
      assert_eq(
        result.warnings.length(),
        count.to_int(),
        msg=id + " warning count",
      )
    }
  }
}

///|
test "OpenAPI conversion matches every scoped reference document and failure policy" {
  let manifest = @json.parse(fixture("cases.json"))
  guard manifest is { "cases": Array(cases), .. } else {
    fail("OpenAPI case manifest is missing")
  }
  let failures : Array[String] = []
  for test_case in cases {
    check_case(test_case) catch {
      error => failures.push(error.to_string())
    }
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
}

///|
test "every upstream OpenAPI golden is assigned or explicitly outside story scope" {
  guard @json.parse(fixture("inventory.json")) is { "files": Array(files), .. } &&
    @json.parse(fixture("cases.json"))
    is { "cases": Array(cases), "excludedUpstreamOutputs": Array(excluded), .. } else {
    fail("Missing OpenAPI corpus manifests")
  }
  let covered : Set[String] = Set([])
  let omitted : Set[String] = Set([])
  let ids : Set[String] = Set([])
  for test_case in cases {
    guard test_case is { "id": String(id), .. } else { fail("Case has no ID") }
    assert_false(ids.contains(id), msg="Duplicate case " + id)
    ids.add(id)
    if test_case is { "expected": String(path), .. } {
      covered.add(path)
    }
    if test_case is { "upstreamExpected": String(path), .. } {
      covered.add(path)
    }
  }
  for entry in excluded {
    guard entry is { "path": String(path), "reason": String(reason), .. } &&
      !reason.is_empty() else {
      fail("Unexplained corpus exclusion")
    }
    assert_false(
      covered.contains(path),
      msg="Exclusion overlaps a covered golden: " + path,
    )
    omitted.add(path)
  }
  for file in files {
    guard file is { "path": String(path), .. } else {
      fail("Malformed inventory")
    }
    if path.has_suffix(".openapi.json") {
      assert_true(
        covered.contains(path) || omitted.contains(path),
        msg="Unassigned upstream golden " + path,
      )
    }
  }
}

///|
test "vendored OpenAPI corpus retains the complete pinned upstream inventory" {
  let inventory = @json.parse(fixture("inventory.json"))
  guard inventory
    is {
      "referenceSha": String("30bdab593f0c2cdf96036782cc3ce15c43a711ef"),
      "files": Array(files),
      ..
    } else {
    fail("OpenAPI corpus provenance changed")
  }
  assert_eq(files.length(), 100)
  for file in files {
    guard file is { "path": String(path), "gitBlob": String(blob), .. } else {
      fail("Malformed OpenAPI corpus inventory entry")
    }
    assert_eq(blob.length(), 40)
    assert_false(fixture(path).is_empty(), msg=path)
  }
}

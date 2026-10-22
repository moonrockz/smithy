///|
fn library_document(source : String) -> @rpcdoc.Document {
  @rpcdoc.read(source).document().unwrap()
}

///|
test "library validation errors fail conversion and name the method's operation" {
  let service = @smithy.ShapeId::parse("demo#Api").unwrap()
  let operations = [
    @smithy.ShapeId::parse("demo#First").unwrap(),
    @smithy.ShapeId::parse("demo#Second").unwrap(),
  ]
  let document = library_document(
    "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"a\",\"params\":[]},{\"name\":\"b\",\"params\":[{\"name\":\"p\",\"schema\":{\"$ref\":\"#/components/schemas/Missing\"}}]}]}",
  )
  let mut rejected = false
  ignore(validated_json(document, service, operations)) catch {
    SchemaConversion(subject, message) => {
      rejected = true
      assert_eq(subject.to_string(), "demo#Second")
      assert_true(message.contains("/methods/1/params/0/schema"), msg=message)
    }
    error => fail("Expected a schema conversion failure: " + error.message())
  }
  assert_true(rejected)
}

///|
test "library normative errors fail conversion as unsupported mappings" {
  let service = @smithy.ShapeId::parse("demo#Api").unwrap()
  let document = library_document(
    "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"a\",\"params\":[]},{\"name\":\"a\",\"params\":[]}]}",
  )
  let mut rejected = false
  ignore(validated_json(document, service, [service, service])) catch {
    UnsupportedMapping(_, message) => {
      rejected = true
      assert_true(message.contains("fails validation"), msg=message)
    }
    error => fail("Expected an unsupported mapping: " + error.message())
  }
  assert_true(rejected)
}

///|
test "optional parameters before required ones stay in order and convert" {
  let service = @smithy.ShapeId::parse("demo#Api").unwrap()
  let document = library_document(
    "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"a\",\"params\":[{\"name\":\"o\",\"required\":false,\"schema\":true},{\"name\":\"r\",\"required\":true,\"schema\":true}]}]}",
  )
  let json = validated_json(document, service, [service])
  guard json is { "methods": [{ "params": [first, second], .. }], .. } else {
    fail("Expected two parameters")
  }
  assert_true(first is { "name": String("o"), "required": False, .. })
  assert_true(second is { "name": String("r"), "required": True, .. })
}

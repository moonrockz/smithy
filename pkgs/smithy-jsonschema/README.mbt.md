# Smithy JSON Schema

Converts an assembled Smithy model into a JSON Schema document.

## Library

```mbt check
///|
test {
  let loaded = @smithy.Loader::new()
    .add_idl(
      "example.smithy", "$version: \"2\"\nnamespace example\nstructure Value { name: String }",
    )
    .assemble()
  let document = @jsonschema.convert(loaded.model.unwrap())
  assert_true(document is { "definitions": { "Value": _, .. }, .. })
}
```

Pass `service="example#Api"` to keep the service's connected value shapes.
Services, operations, resources and prelude definitions are omitted. Mixins
are flattened before conversion. Simple shapes and lists are inlined where
the reference converter inlines them; shared aggregate shapes use `$ref`.
Conflicting exported names and invalid configuration raise `JsonSchemaError`.

Protocol converters can prepare `SchemaIndex::new(model, service~, config~)`
once, then use `document()`, `shape(id)`, `schema_for_member(id)` and
`structure(id, selected_members)` with the same contextual references.
Filtering a structure happens before required properties are computed.
`definition(name)` resolves component names within the selected service closure.

## Build plugin

The Smithy CLI registers the `jsonSchema` plugin. Put this in
`smithy-build.json`, then run `smithy build`:

```json
{
  "version": "1.0",
  "sources": ["model"],
  "projections": {
    "schema": {
      "plugins": {
        "jsonSchema": {
          "service": "example#Api",
          "useJsonName": true
        }
      }
    }
  }
}
```

The document is written to `build/smithy/schema/jsonSchema/schema.json`.

| Plugin setting | Library `Config::new` argument | Default |
|---|---|---|
| `useJsonName` | `use_json_name` | `false` |
| `unionStrategy` | `union_strategy` | `oneOf`; also `object`, `structure` |
| `enumStrategy` | `enum_strategy` | `enum`; also `oneOf` |
| `mapStrategy` | `map_strategy` | `propertyNames`; also `patternProperties` |
| `defaultTimestampFormat` | `default_timestamp_format` | `date-time`; also `http-date`, `epoch-seconds` |
| `supportNonNumericFloats` | `support_non_numeric_floats` | `false` |
| `definitionPointer` | `definition_pointer` | `#/definitions` |
| `schemaDocumentExtensions` | `schema_document_extensions` | `{}` |
| `addReferenceDescriptions` | `add_reference_descriptions` | `false` |
| `disableDefaultValues` | `disable_default_values` | `false` |
| `disableIntEnums` | `disable_int_enums` | `false` |
| `useIntegerType` | `use_integer_type` | `false` |

`definitionPointer` starts with `#/` and supports nested paths such as
`#/components/schemas`. As in the reference, pointer escaping is unsupported.
The plugin's `jsonSchemaVersion` accepts `draft07` or `draft2020-12`; the latter
defaults the definition pointer to `#/$defs`.

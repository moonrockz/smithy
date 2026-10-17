///|
/// Reviewed declarations in the vendored IDL sources, in source order.
/// Inline operation shapes are not top-level declarations. Keep this table
/// independent of our parser and review it when the reference corpus changes.
let valid_expectations : Array[(String, @syntax.Version?, Array[String])] = [
  ("valid/apply/apply-block-empty.smithy", Some(@syntax.Version::V2), ["Foo"]),
  ("valid/apply/apply-statements.smithy", Some(@syntax.Version::V2), ["Foo"]),
  (
    "valid/apply/block-apply-statement.smithy",
    Some(@syntax.Version::V2),
    ["Foo"],
  ),
  (
    "valid/defaults/members-can-be-default-and-required.smithy",
    Some(@syntax.Version::V2),
    ["Foo"],
  ),
  (
    "valid/defaults/valid-defaults.smithy",
    Some(@syntax.Version::V2),
    ["Foo", "StringList", "StringMap"],
  ),
  (
    "valid/doc-comments/doc-comments-ignored-after-shape.smithy",
    Some(@syntax.Version::V2),
    ["Features", "Foo"],
  ),
  (
    "valid/doc-comments/doc-comments.smithy",
    Some(@syntax.Version::V2),
    ["NotDocumented", "MyString", "MyStructure", "MyTrait", "MyOperation"],
  ),
  (
    "valid/elided-members.smithy",
    Some(@syntax.Version::V2),
    [
      "MyResource", "MyResourceIdentifiers", "MyResourceIdentifiersWithTraits", "MixinStructure",
      "MixedStructure", "MixedStructureWithTraits", "MixedResourceStructure", "MixedResourceWithPropertiesStructure",
      "MixedResourceStructureWithTraits", "MixinThatDefinesIdentifier", "MixedStructureWhereMixinDefinesIdentifier",
      "MixinUnion", "MixedUnion", "MixedUnionWithTraits", "ResourceUnion", "MixedResourceUnion",
      "MixedResourceUnionWithTraits", "MixinList", "MixedList", "MixedListWithTraits",
      "ResourceList", "MixedResourceList", "MixedResourceListWithTrait", "MixinMap",
      "MixedMap", "MixedMapWithTraits", "ResourceMap", "MixedResourceMap", "MixedResourceMapWithTraits",
      "ThrowAway",
    ],
  ),
  ("valid/empty.smithy", None, []),
  ("valid/enums/enum-docs.smithy", Some(@syntax.Version::V2), ["Foo"]),
  (
    "valid/enums/enums.smithy",
    Some(@syntax.Version::V2),
    ["EnumWithoutValueTraits", "EnumWithValueTraits", "IntEnum"],
  ),
  (
    "valid/enums/short-form-enum.smithy",
    Some(@syntax.Version::V2),
    ["A", "B", "C", "D"],
  ),
  ("valid/expects-br.smithy", Some(@syntax.Version::V2), ["Foo", "Bar"]),
  (
    "valid/forward-reference-resolver.smithy",
    Some(@syntax.Version::V2),
    ["Foo", "Integer", "MyList", "MyString", "MyResource", "AnotherString"],
  ),
  (
    "valid/inline-io/custom-suffix.smithy",
    Some(@syntax.Version::V2),
    ["Operation"],
  ),
  (
    "valid/inline-io/inline-io.smithy",
    Some(@syntax.Version::V2),
    [
      "DerivedNames", "UsesTraits", "NameBearer", "UsesMixins", "UsesTraitsAndMixins",
      "EmptyShapes", "HasDocComments", "DuplicateTrait",
    ],
  ),
  (
    "valid/list-and-sets.smithy",
    None,
    [
      "String", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
      "N",
    ],
  ),
  (
    "valid/main-test.smithy",
    None,
    [
      "Weather", "City", "Forecast", "CityId", "GetCurrentTime", "GetCurrentTimeOutput",
      "GetForecast", "GetForecastInput", "GetForecastOutput", "GetCity", "GetCityInput",
      "GetCityOutput", "ListCities", "ListCitiesInput", "ListCitiesOutput", "CityCoordinates",
      "NoSuchResource", "CitySummaries", "CitySummary",
    ],
  ),
  (
    "valid/maps-2.0.smithy",
    Some(@syntax.Version::V2),
    ["A", "B", "C", "D", "E", "F", "G", "String", "H", "I", "J"],
  ),
  ("valid/maps.smithy", None, ["A", "B", "C", "D", "E", "F", "G", "String"]),
  ("valid/metadata.smithy", None, []),
  (
    "valid/mixins/enum-mixins.flattened.smithy",
    Some(@syntax.Version::V2),
    ["MixedEnum", "MixedIntEnum"],
  ),
  (
    "valid/mixins/enum-mixins.smithy",
    Some(@syntax.Version::V2),
    ["BaseEnum", "MixedEnum", "BaseIntEnum", "MixedIntEnum"],
  ),
  (
    "valid/mixins/idl-mixins-redefine-member.flattened.smithy",
    Some(@syntax.Version::V2),
    ["MixedStructure"],
  ),
  (
    "valid/mixins/idl-mixins-redefine-member.smithy",
    Some(@syntax.Version::V2),
    ["MixinStructure", "MixedStructure"],
  ),
  (
    "valid/mixins/loads-mixins-with-whitespace.smithy",
    Some(@syntax.Version::V2),
    ["A", "B", "C"],
  ),
  (
    "valid/mixins/loads-mixins.flattened.smithy",
    Some(@syntax.Version::V2),
    [
      "B", "F", "MixedBlob", "MixedBoolean", "MixedString", "MixedByte", "MixedShort",
      "MixedInteger", "MixedLong", "MixedFloat", "MixedDouble", "MixedBigInt", "MixedBigDecimal",
      "MixedTimestamp", "MixedDocument", "MixedList", "MixedMap", "MixedMapRedefineValue",
      "MixedService", "MixedResource", "MixedOperation",
    ],
  ),
  (
    "valid/mixins/loads-mixins.smithy",
    Some(@syntax.Version::V2),
    [
      "A", "B", "C", "D", "E", "F", "MixinBlob", "MixedBlob", "MixinBoolean", "MixedBoolean",
      "MixinString", "MixedString", "MixinByte", "MixedByte", "MixinShort", "MixedShort",
      "MixinInteger", "MixedInteger", "MixinLong", "MixedLong", "MixinFloat", "MixedFloat",
      "MixinDouble", "MixedDouble", "MixinBigInt", "MixedBigInt", "MixinBigDecimal",
      "MixedBigDecimal", "MixinTimestamp", "MixedTimestamp", "MixinDocument", "MixedDocument",
      "MixinList", "MixedList", "MixinMap", "MixedMap", "MixedMapRedefineValue",
      "MixinService", "MixedService", "MixinResource", "MixedResource", "MixinOperation",
      "MixedOperation",
    ],
  ),
  (
    "valid/mixins/mixin-names.smithy",
    Some(@syntax.Version::V2),
    ["integerPrefixed", "NotPrefixed", "iiiiiii", "MixedInt", "SafeInt"],
  ),
  (
    "valid/mixins/mixins-on-operation.smithy",
    Some(@syntax.Version::V2),
    ["ListFoos", "MyMixin"],
  ),
  (
    "valid/mixins/mixins-with-member-override-1.flattened.smithy",
    Some(@syntax.Version::V2),
    ["Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-1.smithy",
    Some(@syntax.Version::V2),
    ["A1", "A2", "Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-2.flattened.smithy",
    Some(@syntax.Version::V2),
    ["Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-2.smithy",
    Some(@syntax.Version::V2),
    ["A1", "A2", "Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-3.flattened.smithy",
    Some(@syntax.Version::V2),
    ["Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-3.smithy",
    Some(@syntax.Version::V2),
    ["A1", "A2", "Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-4.flattened.smithy",
    Some(@syntax.Version::V2),
    ["Valid"],
  ),
  (
    "valid/mixins/mixins-with-member-override-4.smithy",
    Some(@syntax.Version::V2),
    ["A1", "A2", "Valid"],
  ),
  (
    "valid/mixins/mixins-with-members-and-traits.flattened.smithy",
    Some(@syntax.Version::V2),
    ["F"],
  ),
  (
    "valid/mixins/mixins-with-members-and-traits.smithy",
    Some(@syntax.Version::V2),
    ["A", "B", "C", "D", "E", "F"],
  ),
  (
    "valid/mixins/mixins-with-members.flattened.smithy",
    Some(@syntax.Version::V2),
    ["F"],
  ),
  (
    "valid/mixins/mixins-with-members.smithy",
    Some(@syntax.Version::V2),
    ["A", "B", "C", "D", "E", "F"],
  ),
  (
    "valid/mixins/mixins-with-mixin-local-traits.flattened.smithy",
    Some(@syntax.Version::V2),
    ["PublicShape"],
  ),
  (
    "valid/mixins/mixins-with-mixin-local-traits.smithy",
    Some(@syntax.Version::V2),
    ["PrivateMixin", "PublicShape"],
  ),
  (
    "valid/mixins/no-empty-apply-types.smithy",
    Some(@syntax.Version::V2),
    ["MixinStruct", "MixedStruct"],
  ),
  (
    "valid/mixins/operations.flattened.smithy",
    Some(@syntax.Version::V2),
    ["ConcreteError", "MixinError", "ConcreteOperation"],
  ),
  (
    "valid/mixins/operations.smithy",
    Some(@syntax.Version::V2),
    ["ConcreteError", "MixinError", "InternalMixin", "ConcreteOperation"],
  ),
  (
    "valid/mixins/resources.flattened.smithy",
    Some(@syntax.Version::V2),
    ["MixedResource"],
  ),
  (
    "valid/mixins/resources.smithy",
    Some(@syntax.Version::V2),
    ["MixinResource", "MixedResource"],
  ),
  (
    "valid/mixins/services.flattened.smithy",
    Some(@syntax.Version::V2),
    [
      "ShapeToRename", "MixinError", "MixinOperation", "MixinResource", "MixedService",
    ],
  ),
  (
    "valid/mixins/services.smithy",
    Some(@syntax.Version::V2),
    [
      "ShapeToRename", "MixinError", "MixinOperation", "MixinResource", "MixinService",
      "MixedService",
    ],
  ),
  (
    "valid/multiple-traits-same-name.smithy",
    None,
    [
      "DeprecatedString1", "DeprecatedString2", "deprecated", "DeprecatedString3",
    ],
  ),
  (
    "valid/operations/errors-before-input.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooInput"],
  ),
  (
    "valid/operations/operation-no-newline-after-properties.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooInput", "GetFooOutput"],
  ),
  (
    "valid/operations/operation-with-all.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooInput", "GetFooOutput"],
  ),
  (
    "valid/operations/operation-with-errors.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo"],
  ),
  (
    "valid/operations/operation-with-inline-input.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo"],
  ),
  (
    "valid/operations/operation-with-input-and-output.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooInput", "GetFooOutput"],
  ),
  (
    "valid/operations/operation-with-input.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooInput"],
  ),
  (
    "valid/operations/operation-with-no-properties.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo"],
  ),
  (
    "valid/operations/operation-with-output.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooOutput"],
  ),
  (
    "valid/operations/output-before-input.smithy",
    Some(@syntax.Version::V2),
    ["GetFoo", "GetFooInput", "GetFooOutput"],
  ),
  (
    "valid/optional-commas.smithy",
    Some(@syntax.Version::V2),
    [
      "Weather", "City", "Forecast", "CityId", "GetCity", "GetCityInput", "GetCityOutput",
      "CityCoordinates", "NoSuchResource", "ListCities", "ListCitiesInput", "ListCitiesOutput",
      "CitySummaries", "CitySummary", "GetCurrentTime", "GetCurrentTimeOutput", "GetForecast",
      "GetForecastInput", "GetForecastOutput",
    ],
  ),
  ("valid/service-version-not-required.smithy", None, ["MyService"]),
  (
    "valid/service-with-errors.smithy",
    Some(@syntax.Version::V1),
    ["EmptyService", "Common1", "Common2"],
  ),
  (
    "valid/service-with-nonconflicting-unit.smithy",
    Some(@syntax.Version::V1),
    ["TestService", "Example", "ExampleOutput", "Unit"],
  ),
  (
    "valid/service-with-rename.smithy",
    None,
    ["MyService", "GetSomething", "GetSomethingOutput", "Widget"],
  ),
  (
    "valid/simple-shapes.smithy",
    None,
    [
      "MyBoolean1", "MyByte1", "MyShort1", "MyInteger1", "MyLong1", "MyFloat1", "MyDouble1",
      "MyBigInteger1", "MyBigDecimal1", "MyString1", "MyBlob1", "MyTimestamp1", "MyBoolean2",
      "MyByte2", "MyShort2", "MyInteger2", "MyLong2", "MyFloat2", "MyDouble2", "MyBigInteger2",
      "MyBigDecimal2", "MyString2", "MyBlob2", "MyTimestamp2",
    ],
  ),
  (
    "valid/structures.smithy",
    None,
    ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"],
  ),
  (
    "valid/text-blocks.smithy",
    None,
    [
      "EmptyString", "NewlineString", "TrailingNewlineString", "NoTrailingNewlineString",
      "EscapedNewlineString", "WithUnicode", "DiscardLastLineOffset", "EmptyLinesAreIncidentalWs",
      "SingleCharacterTextBlock", "EmbeddedQuotesTextBlock",
    ],
  ),
  (
    "valid/trait-definitions.smithy",
    None,
    [
      "customTrait", "documentation", "numeric", "MyString1", "MyString2", "MyString3",
      "MyString4",
    ],
  ),
  (
    "valid/trait-locations.smithy",
    Some(@syntax.Version::V1),
    [
      "numberTrait", "boolTrait", "documentTrait", "stringTrait", "annotationTrait",
      "TraitBearer",
    ],
  ),
  (
    "valid/traits/reference-shape-from-trait.smithy",
    Some(@syntax.Version::V2),
    ["link", "StructA", "StructB", "StructC", "StructD"],
  ),
  (
    "valid/traits.smithy",
    None,
    [
      "A", "B", "C", "D", "E", "F", "H", "I", "Foo", "J", "K", "L", "M", "N", "O",
      "P", "Q", "numeric", "R", "S", "T", "U", "V", "bDecimal", "W", "X", "Y", "Z",
      "bInteger", "ZA",
    ],
  ),
  (
    "valid/unions.smithy",
    None,
    ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"],
  ),
  ("valid/unknown-control-statement.smithy", None, []),
  (
    "valid/use/use-shapes.smithy",
    Some(@syntax.Version::V2),
    ["MyList", "Widgets", "Struct"],
  ),
  ("valid/use/use-traits.smithy", Some(@syntax.Version::V1), ["Struct"]),
  ("valid/version-full.smithy", Some(@syntax.Version::V1), []),
  ("valid/version-simple.smithy", Some(@syntax.Version::V1), []),
]

///|
test "every valid reference case preserves its declared version and shape names" {
  let cases = @tck.cases().filter(c => c.kind is Valid)
  assert_eq(cases.length(), valid_expectations.length())
  for c in cases {
    let expected = valid_expectations.iter().find_first(e => e.0 == c.path)
    guard expected is Some((_, version, names)) else {
      fail("no expectations for \{c.path}")
    }
    let result = @syntax.parse_idl(c.text)
    assert_eq(result.version, version, msg=c.path)
    guard result.ast is Some(file) else { fail("no AST for \{c.path}") }
    @expect.expect(file.shapes().map(s => s.shape.name().value))
    .because(c.path)
    .to_equal(names)
  }
}

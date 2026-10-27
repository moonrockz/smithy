Feature: Profile-aware JSON codecs
  Check, decode and write application JSON with representations that the model declares. A profile
  selects declared rules; findings name the original JSON location.

  Background:
    Given the codec model:
      """smithy
      $version: "2"
      namespace example
      use smithy.serialization#jsonProfiles
      use smithy.serialization#jsonEncoding
      use smithy.serialization#jsonBundle

      @jsonProfiles([
        {id: "external"}
        {id: "internal", defaults: {union: {style: "internal", tag: "kind"}}}
        {id: "adjacent", defaults: {union: {style: "adjacent", tag: "kind", content: "value"}}}
        {id: "array", defaults: {union: {style: "tagArray"}}}
        {id: "mixed", defaults: {union: {style: "external"}}}
        {id: "bad", defaults: {union: {style: "spliced"}}}
      ])
      structure Doc {
        @required
        op: Op
        id: Id
        table: Table
      }

      @jsonEncoding(profiles: {mixed: {union: {style: "adjacent", tag: "t", content: "c"}}})
      union Op {
        Add: Pair
        Stop: Unit
      }

      @jsonEncoding(profiles: {array: {tuple: {members: ["left", "right"]}}})
      structure Pair {
        @required
        left: Small
        @required
        right: Small
      }

      @range(max: 9)
      integer Small

      @jsonEncoding(base: {union: {style: "untagged"}}, profiles: {
        internal: {union: {style: "untagged"}}
        adjacent: {union: {style: "untagged"}}
        array: {union: {style: "untagged"}}
        mixed: {union: {style: "untagged"}}
      })
      union Id {
        number: BigInteger
        text: String
      }

      @jsonEncoding(profiles: {array: {dictionary: {layout: "entries"}}})
      map Table {
        key: String
        value: BigDecimal
      }

      @jsonBundle(
        id: "doc"
        version: {field: "formatVersion", adapter: "test.version"}
        releases: [
          {since: "1.0.0", until: "2.0.0", root: V1, profiles: ["external"]}
          {since: "2.0.0", until: "2.1.0", root: V2, profiles: ["array"]}
        ]
      )
      structure Documents {}

      structure V1 {
        @required
        @jsonEncoding(base: {adapter: "test.version"})
        formatVersion: String
        @required
        doc: Doc
      }

      structure V2 {
        @required
        @jsonEncoding(base: {adapter: "test.version"})
        formatVersion: String
        @required
        doc: Doc
      }
      """

  Scenario: Each object representation decodes to the same member
    When I prepare the codec of "example#Doc" with profile "external"
    And I check the JSON "{\"op\":{\"Add\":{\"left\":1,\"right\":2}}}"
    Then the JSON is valid
    When I prepare the codec of "example#Doc" with profile "internal"
    And I check the JSON "{\"op\":{\"kind\":\"Add\",\"left\":1,\"right\":2}}"
    Then the JSON is valid
    When I prepare the codec of "example#Doc" with profile "adjacent"
    And I check the JSON "{\"op\":{\"kind\":\"Add\",\"value\":{\"left\":1,\"right\":2}}}"
    Then the JSON is valid
    And the decoded values are equal

  Scenario: A shape-specific rule overrides a profile default
    When I prepare the codec of "example#Doc" with profile "mixed"
    And I canonicalize the JSON "{\"op\":{\"t\":\"Stop\"}}"
    Then the canonical JSON is "{\"op\":{\"t\":\"Stop\"}}"

  Scenario: Tagged arrays validate their positions at the source index
    When I prepare the codec of "example#Doc" with profile "array"
    And I check the JSON "{\"op\":[\"Add\",1,2]}"
    Then the JSON is valid
    When I check the JSON "{\"op\":[\"Add\",1,10]}"
    Then the codec finding is "Range" at "/op/2"
    When I check the JSON "{\"op\":[\"Add\",1]}"
    Then the codec finding is "MissingMember" at "/op/2"
    When I check the JSON "{\"op\":[\"Add\",1,2,3]}"
    Then the codec finding is "Arity" at "/op/3"
    When I check the JSON "{\"op\":[\"Mul\",1,2]}"
    Then the codec finding is "UnknownTag" at "/op/0"

  Scenario: An untagged scalar union selects its member by JSON kind
    When I prepare the codec of "example#Doc" with profile "external"
    And I check the JSON "{\"op\":{\"Stop\":{}},\"id\":123456789012345678901234567890}"
    Then the JSON is valid
    When I check the JSON "{\"op\":{\"Stop\":{}},\"id\":\"a\"}"
    Then the JSON is valid
    When I check the JSON "{\"op\":{\"Stop\":{}},\"id\":true}"
    Then the codec finding is "KindMismatch" at "/id"

  Scenario: Entry-array dictionaries keep each key with its value
    When I prepare the codec of "example#Doc" with profile "array"
    And I canonicalize the JSON "{\"op\":[\"Stop\"],\"table\":[[\"b\",2.50],[\"a\",1]]}"
    Then the canonical JSON is "{\"op\":[\"Stop\"],\"table\":[[\"a\",1],[\"b\",2.50]]}"
    When I check the JSON "{\"op\":[\"Stop\"],\"table\":[[\"a\",1],[\"a\",2]]}"
    Then the codec finding is "DuplicateKey" at "/table/1/0"

  Scenario: Exact numbers and escaped duplicate names
    When I prepare the codec of "example#Doc" with profile "external"
    And I canonicalize the JSON "{\"op\":{\"Stop\":{}},\"table\":{\"x\":0.1000000000000000000000000001}}"
    Then the canonical JSON is "{\"op\":{\"Stop\":{}},\"table\":{\"x\":0.1000000000000000000000000001}}"
    When I check JSON that spells the member "op" a second time as "\\u006fp"
    Then the codec finding is "DuplicateName" at ""

  Scenario: Unknown and unsupported profiles are refused
    When I prepare the codec of "example#Doc" with profile "tree"
    Then preparation is refused with "UnknownProfile"
    When I prepare the codec of "example#Doc" with profile "bad"
    Then preparation is refused with "UnsupportedDeclaration"

  Scenario: A versioned document selects its root from its version
    When I prepare the document bundle "doc"
    And I canonicalize the JSON "{\"doc\":{\"op\":[\"Stop\"]},\"formatVersion\":\"2.0.0\"}"
    Then the canonical JSON is "{\"formatVersion\":2,\"doc\":{\"op\":[\"Stop\"]}}"
    When I check the JSON "{\"formatVersion\":1,\"doc\":{\"op\":[\"Stop\"]}}"
    Then the codec finding is "KindMismatch" at "/doc/op"
    When I check the JSON "{\"formatVersion\":\"3.0.0\",\"doc\":{\"op\":{\"Stop\":{}}}}"
    Then the codec finding is "UnsupportedVersion" at "/formatVersion"
    When I check the JSON "{\"doc\":{\"op\":{\"Stop\":{}}}}"
    Then the codec finding is "MissingVersion" at "/formatVersion"

  Scenario: The value validator keeps its standard union encoding
    Then the value validator still reports "example#Doc"

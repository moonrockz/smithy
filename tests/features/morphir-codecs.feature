Feature: Morphir v3 and v4 codec bundles
  The models in examples/morphir-codecs/model declare the Morphir IR v3 and v4 JSON representations with
  serialization traits. The Morphir adapters normalize names and format versions. Every case comes from the
  pinned upstream corpus (examples/morphir-codecs/cases.json) or is a negative case that the corpus lacks.

  Background:
    Given the Morphir codec models and adapters

  Rule: Full artifacts decode and write their canonical form

    Scenario Outline: A pinned v3 artifact round-trips byte for byte
      Given the root "morphir.ir.v3#IRFile30" with profile "morphir-v3"
      When I canonicalize the file "upstream/finos-morphir/website/static/ir/examples/v3/<file>"
      Then the output is the file "upstream/finos-morphir/website/static/ir/examples/v3/<file>"

      Examples:
        | file                       |
        | greeting-example.json      |
        | direct-rules-example.json  |
        | rule-set-example.json      |

    Scenario: The v4 complete example canonicalizes to the kit's canonical distribution
      Given the root "morphir.ir.v4#IRFile" with profile "morphir-v4"
      When I canonicalize the file "upstream/finos-morphir/website/static/ir/examples/v4/complete-example.json"
      Then the output is the canonical JSON of case "mck/distributions-0004/json-canonical"

    Scenario Outline: A pinned v4 artifact canonicalizes stably
      Given the root "morphir.ir.v4#IRFile" with profile "morphir-v4"
      When I canonicalize the file "<file>"
      Then the output starts with '{"formatVersion":4,"distribution":{"Library":'
      And canonicalizing the output again gives the same text

      Examples:
        | file                                                                        |
        | upstream/finos-morphir/website/static/ir/examples/v4/books-and-records-example.json |
        | upstream/finos-morphir/spec/ir/mck/node-address-fixtures/v4-library.json    |

  Rule: Upstream conformance cases keep their recorded outcomes

    Scenario Outline: Conformance case <id>
      When I run the conformance case "<id>"
      Then the case has its expected outcome

      Examples: v3 nodes
        | id                                       |
        | mck/versions-0001/json-canonical         |
        | mck/versions-0006/json-canonical         |
        | mck/versions-0007/json-canonical         |
        | mck/versions-0008/json-canonical         |
        | mck/distributions-0011/json-canonical    |
        | format-version/header-order/1            |
        | format-version/root/1                    |

      Examples: v4 types, values, patterns and literals
        | id                                             |
        | mck/types-0002/json-accepted-3                 |
        | mck/types-0003/json-canonical                  |
        | mck/types-0004/json-accepted-1                 |
        | mck/types-0005/json-accepted-3                 |
        | mck/types-0007/json-accepted-3                 |
        | mck/types-0010/json-canonical                  |
        | mck/types-0011/json-rejected-1                 |
        | mck/values-0001/json-accepted-2                |
        | mck/values-0007/json-rejected-1                |
        | mck/values-0008/json-accepted-1                |
        | mck/values-0012/json-accepted-1                |
        | mck/values-0017/json-accepted-2                |
        | mck/patterns-and-literals-0001/json-accepted-1 |
        | mck/patterns-and-literals-0003/json-accepted-1 |
        | mck/patterns-and-literals-0006/json-canonical  |
        | mck/patterns-and-literals-0013/json-rejected-1 |
        | mck/patterns-and-literals-0019/json-canonical  |

      Examples: v4 definitions, distributions and versions
        | id                                             |
        | mck/definitions-0001/json-accepted-1           |
        | mck/definitions-0001/json-accepted-3           |
        | mck/definitions-0002/json-accepted-1           |
        | mck/definitions-0018/json-accepted-2           |
        | mck/definitions-0004/json-accepted-1           |
        | mck/definitions-0006/json-accepted-1           |
        | mck/definitions-0020/json-accepted-1           |
        | mck/definitions-0031/json-rejected-2           |
        | mck/distributions-0002/json-accepted-1         |
        | mck/distributions-0003/json-rejected-1         |
        | mck/distributions-0004/text-accepted-1         |
        | mck/distributions-0008/json-canonical          |
        | mck/versions-0010/json-rejected-1              |

      Examples: names and format versions
        | id                                   |
        | mck/names-0001/json-accepted-1       |
        | mck/names-0003/json-rejected-1       |
        | naming/legacyDecodeCases/07          |
        | naming/rejectCases/13                |
        | format-version/scalar/08             |
        | format-version/scalar/29             |

      Examples: recorded gaps fail as recorded
        | id                                   |
        | mck/definitions-0007/json-accepted-1 |
        | mck/definitions-0008/json-rejected-1 |

  Rule: The expanded writer is an output choice, not another semantic value

    Scenario Outline: Expanded output of a v4 type
      Given the root "morphir.ir.v4#Type" with profile "morphir-v4-expanded"
      When I canonicalize '<input>'
      Then the output is '<expanded>'
      And canonicalizing the output again gives the same text

      Examples:
        | input                                       | expanded                                                                                    |
        | "a"                                         | {"Variable":{"name":"a"}}                                                                   |
        | "morphir/SDK:basics#int"                    | {"Reference":{"fqname":"morphir/SDK:basics#int"}}                                           |
        | {"Reference":["morphir/SDK:list#list","a"]} | {"Reference":{"fqname":"morphir/SDK:list#list","args":[{"Variable":{"name":"a"}}]}}         |
        | ["a","b"]                                   | {"Tuple":{"elements":[{"Variable":{"name":"a"}},{"Variable":{"name":"b"}}]}}                |

    Scenario Outline: The compact writer reads expanded output back to the canonical form
      Given the root "morphir.ir.v4#<root>" with profile "morphir-v4"
      When I canonicalize '<expanded>'
      Then the output is '<canonical>'

      Examples:
        | root  | expanded                                                                            | canonical                                    |
        | Type  | {"Reference":{"fqname":"morphir/SDK:list#list","args":[{"Variable":{"name":"a"}}]}} | {"Reference":["morphir/SDK:list#list","a"]}  |
        | Value | {"Literal":{"literal":{"IntegerLiteral":{"value":42}}}}                             | {"Literal":{"IntegerLiteral":42}}            |
        | Value | {"List":{"items":[{"Variable":{"name":"x"}}]}}                                      | {"List":[{"Variable":"x"}]}                  |

  Rule: Inputs that the corpus does not cover are refused

    Scenario Outline: An invalid v4 node
      Given the root "morphir.ir.v4#<root>" with profile "morphir-v4"
      When I check '<input>'
      Then the input is refused with "<code>"

      Examples: duplicate members and keys below the root
        | root                     | input                                                                                                                  | code           |
        | Type                     | {"Record":{"fields":{"a":"morphir/SDK:basics#int","a":"morphir/SDK:basics#int"}}}                                      | DuplicateName  |
        | Type                     | {"Record":{"fields":{"a":"morphir/SDK:basics#int","a":"morphir/SDK:basics#int"}}}                                 | DuplicateName  |
        | Value                    | {"Apply":{"function":"f","function":"g","argument":"x"}}                                                               | DuplicateName  |
        | TypeSpecification        | {"CustomTypeSpecification":{"typeParams":[],"constructors":[[["u","s"],[]],["US",[]]]}}                              | DuplicateKey   |
        | ValueSpecification       | {"inputs":[[["value","in","u","s","d"],"a"],["value-in-USD","a"]],"output":"a"}                                      | DuplicateKey   |

      Examples: alias and canonical spellings together, and two variants
        | root                            | input                                                                                                                          | code            |
        | Type                            | {"Function":{"parameterType":"a","argumentType":"a","returnType":"a"}}                                                         | MemberCollision |
        | Value                           | {"IfThenElse":{"condition":true,"then":1,"thenBranch":1,"else":2}}                                                             | MemberCollision |
        | AccessControlledTypeDefinition  | {"Public":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"a"},"CustomTypeDefinition":{"typeParams":[],"constructors":{}}}} | Arity           |
        | AccessControlledTypeDefinition  | {"Public":{"doc":"no definition"}}                                                                                             | MissingMember   |
        | AccessControlledTypeDefinition  | {"Public":{"value":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"a"}},"TypeAliasDefinition":{"typeParams":[],"typeExp":"a"}}} | MemberCollision |
        | TypeSpecification               | ["TypeAliasSpecification",[],"a"]                                                                                              | Arity           |

      Examples: name, literal and version spellings
        | root    | input                                   | code            |
        | Type    | "Usd"                                   | KindMismatch    |
        | Type    | "morphir/SDK:basics#Int-x"              | KindMismatch    |
        | Value   | "x y"                                   | KindMismatch    |
        | Literal | {"IntegerLiteral":4.0}                  | AdapterFailure  |
        | Literal | {"DecimalLiteral":"1.0.0"}              | Pattern         |
        | IRFile  | {"formatVersion":"4.0.0","distribution":{"Library":{"packageName":"example","dependencies":{},"def":{"modules":{}}}},"$meta":1} | UnknownMember |

    Scenario Outline: An invalid v3 node
      Given the root "morphir.ir.v3#<root>" with profile "morphir-v3"
      When I check '<input>'
      Then the input is refused with "<code>"

      Examples:
        | root    | input                                                                                          | code          |
        | Value   | ["Record",{},[[["a"],["Unit",{}]],[["a"],["Unit",{}]]]]                                       | DuplicateKey  |
        | Value   | ["Unit",{},{}]                                                                                 | Arity         |
        | Type    | ["Variable",{"x":1},["a"]]                                                                     | UnknownMember |
        | Type    | ["Variable",{},["A"]]                                                                          | AdapterFailure |
        | Literal | ["CharLiteral","ab"]                                                                           | Length        |
        | Literal | ["IntegerLiteral",1]                                                                           | UnknownTag    |
        | IRFile30 | {"formatVersion":3,"distribution":["Library",[["p"]],[],{"modules":[]}],"extra":1}            | UnknownMember |

  Rule: v3 nodes outside the pinned artifacts round-trip in Elm order

    Scenario Outline: A v3 node round-trips
      Given the root "morphir.ir.v3#<root>" with profile "morphir-v3"
      When I canonicalize '<input>'
      Then the output is '<input>'

      Examples:
        | root              | input                                                                                                               |
        | Literal           | ["CharLiteral","a"]                                                                                                 |
        | Literal           | ["DecimalLiteral","-10.50"]                                                                                         |
        | Literal           | ["FloatLiteral",2.50]                                                                                               |
        | Type              | ["ExtensibleRecord",{},["r"],[{"name":["email"],"tpe":["Unit",{}]}]]                                                |
        | Type              | ["Unit",{}]                                                                                                         |
        | Value             | ["Destructure",{},["TuplePattern",{},[["AsPattern",{},["WildcardPattern",{}],["a"]],["UnitPattern",{}]]],["Variable",{},["p"]],["Variable",{},["a"]]] |
        | Value             | ["LetRecursion",{},[[["f"],{"inputTypes":[],"outputType":["Unit",{}],"body":["Variable",{},["f"]]}]],["Variable",{},["f"]]] |
        | Value             | ["UpdateRecord",{},["Variable",{},["r"]],[[["name"],["Literal",{},["StringLiteral","x"]]]]]                         |
        | Value             | ["PatternMatch",{},["Variable",{},["l"]],[[["HeadTailPattern",{},["WildcardPattern",{}],["EmptyListPattern",{}]],["Unit",{}]]]] |
        | TypeSpecification | ["OpaqueTypeSpecification",[["a"]]]                                                                                 |
        | TypeSpecification | ["TypeAliasSpecification",[],["Unit",{}]]                                                                           |
        | TypeSpecification | ["CustomTypeSpecification",[["a"]],[[["just"],[[["value"],["Variable",{},["a"]]]]],[["nothing"],[]]]]                |

    Scenario: v3 dictionaries are written in Elm Dict order
      Given the root "morphir.ir.v3#Value" with profile "morphir-v3"
      When I canonicalize '["Record",{},[[["b"],["Unit",{}]],[["a","b"],["Unit",{}]],[["a"],["Unit",{}]]]]'
      Then the output is '["Record",{},[[["a"],["Unit",{}]],[["a","b"],["Unit",{}]],[["b"],["Unit",{}]]]]'

  Rule: The bundle selects one release before it reads the payload and never migrates

    Background:
      Given the Morphir document bundle

    Scenario: A v3.0 artifact keeps integer 3
      When I canonicalize the file "upstream/finos-morphir/website/static/ir/examples/v3/greeting-example.json" with the bundle
      Then the output is the file "upstream/finos-morphir/website/static/ir/examples/v3/greeting-example.json"

    Scenario: A v4 artifact is read through the bundle
      When I canonicalize the file "upstream/finos-morphir/website/static/ir/examples/v4/complete-example.json" with the bundle
      Then the output is the canonical JSON of case "mck/distributions-0004/json-canonical"

    Scenario Outline: Supported releases keep their identity
      When I decode the document '<document>' with the bundle
      Then the decoded release is "<release>"

      Examples:
        | document                                                                                                      | release |
        | {"formatVersion":3,"distribution":["Library",[["p"]],[],{"modules":[]}]}                                      | 3.0.0   |
        | {"formatVersion":"3.0.1","distribution":["Library",[["p"]],[],{"modules":[]}]}                                | 3.0.1   |
        | {"formatVersion":"3.1.0","distribution":["Specs",[["p"]],[],{"modules":[]}]}                                  | 3.1.0   |
        | {"distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}},"formatVersion":"4.0.0"} | 4.0.0  |
        | {"formatVersion":"4.0.1","distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}}} | 4.0.1  |

    Scenario Outline: Canonical output keeps the release and puts formatVersion first
      When I canonicalize the document '<document>' with the bundle
      Then the output is '<canonical>'

      Examples:
        | document                                                                                                        | canonical                                                                                                  |
        | {"distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}},"formatVersion":"4.0.0"} | {"formatVersion":4,"distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}}}  |
        | {"formatVersion":"4.0.1","distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}}} | {"formatVersion":"4.0.1","distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}}} |
        | {"formatVersion":"3.0.0","distribution":["Library",[["p"]],[],{"modules":[]}]}                                  | {"formatVersion":3,"distribution":["Library",[["p"]],[],{"modules":[]}]}                                   |
        | {"distribution":["Specs",[["p"]],[],{"modules":[]}],"formatVersion":"3.1.0"}                                    | {"formatVersion":"3.1.0","distribution":["Specs",[["p"]],[],{"modules":[]}]}                               |

    Scenario: The expanded output profile writes the same v4 value
      When I canonicalize the document '{"formatVersion":4,"distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{"m":{"Public":{"types":{"t":{"Public":{"TypeAliasDefinition":{"typeParams":[],"typeExp":"a"}}}},"values":{}}}}}}}}' with the bundle and output profile "morphir-v4-expanded"
      Then the output is '{"formatVersion":4,"distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{"m":{"Public":{"types":{"t":{"Public":{"TypeAliasDefinition":{"typeParams":[],"typeExp":{"Variable":{"name":"a"}}}}}},"values":{}}}}}}}}'

    Scenario Outline: Unsupported, invalid and conflicting versions are refused before the payload is read
      When I canonicalize the document '<document>' with the bundle
      Then the input is refused with "<code>"

      Examples:
        | document                                                                                     | code               |
        | {"formatVersion":1,"distribution":[]}                                                        | UnsupportedVersion |
        | {"formatVersion":2,"distribution":[]}                                                        | UnsupportedVersion |
        | {"formatVersion":"3.2.0","distribution":["Library",[["p"]],[],{"modules":[]}]}               | UnsupportedVersion |
        | {"formatVersion":"4.1.0","distribution":{}}                                                  | UnsupportedVersion |
        | {"formatVersion":"4.0.0-beta","distribution":{}}                                             | InvalidVersion     |
        | {"formatVersion":3.0,"distribution":["Library",[["p"]],[],{"modules":[]}]}                   | InvalidVersion     |
        | {"distribution":["Library",[["p"]],[],{"modules":[]}]}                                       | MissingVersion     |
        | {"formatVersion":3,"formatVersion":3,"distribution":["Library",[["p"]],[],{"modules":[]}]}   | DuplicateName      |

    Scenario Outline: A payload of another family is not reinterpreted
      When I canonicalize the document '<document>' with the bundle
      Then the input is refused with "<code>"

      Examples:
        | document                                                                                                 | code         |
        | {"formatVersion":3,"distribution":["Specs",[["p"]],[],{"modules":[]}]}                                   | UnknownTag   |
        | {"formatVersion":"3.0.0","distribution":{"Library":{"packageName":"p","dependencies":{},"def":{"modules":{}}}}} | KindMismatch |
        | {"formatVersion":4,"distribution":["Library",[["p"]],[],{"modules":[]}]}                                 | KindMismatch |

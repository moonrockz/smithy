Feature: Parsing Smithy IDL
  The parser reads Smithy IDL 2.0 text into a typed AST with spans and a
  lossless CST. These scenarios are the acceptance contract for the shapes,
  members, traits and node values the grammar defines.

  Scenario: Documentation precedes traits and trailing comments stay ordinary comments
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace example.docs
      @deprecated
      /// ignored after a trait
      string Name /// ignored on the shape line
      /// kept
      string Other
      """
    When I parse the model
    Then there are no errors
    And the shape "Name" has docs ""
    And the shape "Other" has docs " kept"

  Scenario: Every statement form parses clean
    Given the Smithy model:
      """smithy
      $version: "2"
      metadata foo = ["bar"]
      namespace smithy.example
      use smithy.api#String

      /// Docs.
      @deprecated(message: "old")
      structure Foo with [Mix] {
          @required
          bar: String = "x"
          $baz
      }

      @mixin
      structure Mix {
          baz: Integer
      }

      enum Color {
          RED = "red"
          BLUE
      }

      operation GetFoo {
          input := {
              id: String
          }
          output: Foo
          errors: [NotFound]
      }

      @error("client")
      structure NotFound {}

      apply Foo @since("1.0")
      """
    When I parse the model
    Then there are no diagnostics
    And the version is "2"
    And the namespace is "smithy.example"
    And the shapes are "Foo, Mix, Color, GetFoo, NotFound"
    And the shape "Foo" has docs " Docs."
    And the shape "Foo" has the traits "deprecated"
    And the member "Foo$bar" targets "String" with default "x"
    And the member "Foo$baz" is elided
    And the CST prints the model back unchanged

  Scenario: Shape IDs are read as written, not resolved
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace a.b

      structure S {
          x: c.d#E$f
          y: Local
      }
      """
    When I parse the model
    Then there are no diagnostics
    And the member "S$x" targets "c.d#E$f"
    And the member "S$y" targets "Local"

  Scenario: Text blocks decode per the specification
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace a

      @documentation("""
          Hello,
            world.
          """)
      string S
      """
    When I parse the model
    Then there are no diagnostics
    And the trait "documentation" on "S" has the string value:
      """
      Hello,
        world.

      """

  Scenario: A 1.0 model may not use mixins
    Given the Smithy model:
      """smithy
      $version: "1.0"
      namespace a

      string S with [M]
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-007"
    And the first message is "Mixins can only be used with Smithy version 2 or later"

  Scenario: An absent version remains absent
    Given the Smithy model:
      """smithy
      namespace a
      string S
      """
    When I parse the model
    Then there are no diagnostics
    And the version is "none"

  Scenario: Object pairs need whitespace
    Given the Smithy model:
      """smithy
      metadata x = {a:"x"b:"y"}
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-003"
    And the first title is "MISSING SEPARATOR"
    And the first message is "I was expecting whitespace between entries in an object but found `b`"

  Scenario: Trait entries need whitespace
    Given the Smithy model:
      """smithy
      namespace a
      @t(a:"x"b:"y")
      string S
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-003"
    And the first message is "I was expecting whitespace between entries in a trait body but found `b`"

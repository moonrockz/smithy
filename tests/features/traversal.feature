Feature: Traversing the Smithy IDL syntax tree
  The traversal package gives one read-only node model over the AST and
  traversal styles that agree. These scenarios check the tree invariants on
  reference files and check that the kind table in the package README
  matches the code.

  Scenario Outline: The tree invariants hold for <case>
    Given the TCK case "<case>"
    When I build the syntax tree
    Then every child lies inside its parent, in source order
    And every child's parent is the identical node it came from
    And every node's fields match the kind table
    And node_at at the start of every node finds that node or a descendant
    And walk, fold, reduce, the event reader and the cursor enter the same nodes

    Examples:
      | case                                       |
      | valid/doc-comments/doc-comments.smithy     |
      | valid/inline-io/inline-io.smithy           |
      | valid/apply/block-apply-statement.smithy   |
      | valid/enums/enums.smithy                   |
      | valid/mixins/services.smithy               |
      | valid/text-blocks.smithy                   |
      | valid/metadata.smithy                      |
      | valid/use/use-shapes.smithy                |
      | error-recovery/to-docs.smithy              |
      | error-recovery/to-trait.smithy             |

  Scenario: The kind table in the package README matches the node model
    Given the file "pkgs/smithy-syntax/src/traversal/README.mbt.md"
    Then the kind table between the markers matches the node model

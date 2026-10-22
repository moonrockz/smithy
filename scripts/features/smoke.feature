Feature: Smoke evidence
  The fingerprint names the inputs of the release binaries and of the smoke check. A trusted run that
  smokes every platform records evidence under the fingerprint. A change that leaves the inputs as they
  are keeps the fingerprint, so the evidence carries forward and no smoke runs.

  Scenario Outline: The smoke inputs
    Then the path "<path>" is an input: "<input>"

    Examples:
      | path                                            | input |
      | moon.mod                                        | yes   |
      | moon.work                                       | yes   |
      | .config/mise/config.toml                        | yes   |
      | .config/mise/config.local.toml.example          | no    |
      | .github/workflows/ci.yml                        | yes   |
      | .github/workflows/release.yml                   | yes   |
      | .github/workflows/smoke.yml                     | yes   |
      | .github/actions/setup/action.yml                | yes   |
      | scripts/dist.mbtx                               | yes   |
      | scripts/zig-cross.mbtx                          | yes   |
      | scripts/smoke.mbtx                              | yes   |
      | scripts/release.mbtx                            | no    |
      | scripts/test-cli.mbtx                           | no    |
      | apps/smithy/main/main.mbt                       | yes   |
      | apps/smithy/moon.mod                            | yes   |
      | apps/smithy/main/main_test.mbt                  | no    |
      | apps/smithy/README.md                           | no    |
      | pkgs/smithy-syntax/src/parser/parser.mbt        | yes   |
      | pkgs/smithy-syntax/src/parser/parser_wbtest.mbt | no    |
      | pkgs/smithy-syntax/src/traversal/README.mbt.md  | no    |
      | pkgs/smithy-syntax/tests/features/a.feature     | no    |
      | pkgs/smithy-syntax/tests/tck/a.smithy           | yes   |
      | pkgs/smithy/moon.pkg                            | yes   |
      | docs/cookbook/main.mbt                          | no    |
      | docs/x_test.mbt                                 | no    |
      | tests/bdd/steps.mbt                             | no    |
      | examples/openrpc/main.mbtx                      | no    |
      | README.md                                       | no    |
      | CHANGELOG.md                                    | no    |
      | AGENTS.md                                       | no    |
      | .claude/skills/release-manager/SKILL.md         | no    |

  Scenario: A change outside the inputs keeps the fingerprint
    Given the tree has "100644" "aaa" "pkgs/smithy/src/model.mbt"
    And the tree has "100644" "bbb" "README.md"
    When I take the fingerprint
    And the tree has "100644" "ccc" "README.md"
    And the tree has "100644" "ddd" "pkgs/smithy/src/model_test.mbt"
    Then the fingerprint is the same

  Scenario: A change to an input changes the fingerprint
    Given the tree has "100644" "aaa" "pkgs/smithy/src/model.mbt"
    When I take the fingerprint
    And the tree has "100644" "abc" "pkgs/smithy/src/model.mbt"
    Then the fingerprint is not the same

  Scenario: A new input changes the fingerprint
    Given the tree has "100644" "aaa" "pkgs/smithy/src/model.mbt"
    When I take the fingerprint
    And the tree has "100644" "bbb" "pkgs/smithy/src/extra.mbt"
    Then the fingerprint is not the same

  Scenario: A mode change of an input changes the fingerprint
    Given the tree has "100644" "aaa" "scripts/dist.mbtx"
    When I take the fingerprint
    And the tree has "100755" "aaa" "scripts/dist.mbtx"
    Then the fingerprint is not the same

  Scenario: The fingerprint does not depend on the order of the entries
    Given the tree has "100644" "aaa" "pkgs/a.mbt"
    And the tree has "100644" "bbb" "pkgs/b.mbt"
    When I take the fingerprint
    And the tree is empty
    And the tree has "100644" "bbb" "pkgs/b.mbt"
    And the tree has "100644" "aaa" "pkgs/a.mbt"
    Then the fingerprint is the same

  Scenario: The fingerprint is a SHA-256 of the schema line and the input entries
    Given the tree has "100644" "aaa" "moon.mod"
    And the tree has "100644" "bbb" "README.md"
    Then the fingerprint text is:
      """
      smoke-evidence v1
      100644 aaa	moon.mod
      """
    And the fingerprint has 64 hex digits

  Scenario: Read NUL-separated git ls-tree output
    When I read the ls-tree records "100644 blob aaa	pkgs/a b.mbt|160000 commit ccc	pkgs/sub|100755 blob bbb	moon.mod"
    Then the entries are "100644 aaa pkgs/a b.mbt|160000 ccc pkgs/sub|100755 bbb moon.mod"

  Scenario: The evidence record
    Then the evidence for fingerprint "f1" of commit "abc" in run "https://github.com/o/r/actions/runs/7" attempt "2" of event "push" on "refs/heads/main" with the checksums "h1  smithy-linux-x64.tar.gz|h2  smithy.wasm" is:
      """
      {
        "schema": "smoke-evidence v1",
        "fingerprint": "f1",
        "commit": "abc",
        "run": "https://github.com/o/r/actions/runs/7",
        "attempt": "2",
        "event": "push",
        "ref": "refs/heads/main",
        "platforms": [
          "linux-x64",
          "linux-arm64",
          "darwin-arm64",
          "darwin-x64",
          "windows-x64"
        ],
        "checksums": {
          "smithy-linux-x64.tar.gz": "h1",
          "smithy.wasm": "h2"
        }
      }
      """

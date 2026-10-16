Feature: Release tooling
  A release is a pull request that sets one version across the workspace (`release prepare`, with
  `scripts/versions.mbtx`) and adds its section to CHANGELOG.md. `release notes` prints the GitHub
  release notes from that section, and `release refresh` updates the pull request body.

  Scenario Outline: Choose the next version from git-cliff
    Given git-cliff exits with <code> and prints "<stdout>"
    Then the printed version is "<version>"

    Examples:
      | code | stdout   | version |
      | 0    | v0.2.0   | v0.2.0  |
      | 1    | v0.2.0   | v0.0.1  |
      | 0    |          | v0.0.1  |
      | 127  |          | v0.0.1  |

  Scenario Outline: Read a version
    When I read the version "<text>"
    Then the version is "<version>"

    Examples:
      | text    | version |
      | 0.3.0   | 0.3.0   |
      | v0.3.0  | 0.3.0   |
      | 1.10.20 | 1.10.20 |
      | v10.0.0 | 10.0.0  |

  Scenario Outline: Reject what is not a version
    When I read the version "<text>"
    Then it fails with "not a version: <text>"

    Examples:
      | text        |
      | 0.3         |
      | 0.3.0.1     |
      | 0.3.x       |
      | 0.3.0-rc.1  |
      | vv0.3.0     |
      | 0..3        |

  Scenario Outline: Choose the release version
    When I choose the release version with request "<request>", computed "<computed>" and latest tag "<tag>"
    Then the version is "<version>"

    Examples:
      | request | computed | tag    | version |
      |         | v0.3.0   | v0.2.0 | 0.3.0   |
      |         | v0.2.1   | v0.2.0 | 0.2.1   |
      | 1.0.0   | v0.3.0   | v0.2.0 | 1.0.0   |
      | v0.2.5  | v0.3.0   | v0.2.0 | 0.2.5   |

  Scenario: Nothing released yet: moon.mod 0.1.0, no tag, requested 0.0.1
    When I choose the release version with request "0.0.1", computed "v0.0.1" and latest tag ""
    Then the version is "0.0.1"

  Scenario: Nothing released yet and no request
    When I choose the release version with request "", computed "v0.0.1" and latest tag ""
    Then the version is "0.0.1"

  Scenario Outline: The release version must be above the latest tag
    When I choose the release version with request "<request>", computed "<computed>" and latest tag "<tag>"
    Then it fails with "<message>"

    Examples:
      | request | computed | tag    | message                                                                                            |
      |         | v0.2.0   | v0.2.0 | version 0.2.0 is not above the latest tag v0.2.0; nothing to release, or pass a higher version     |
      | 0.1.9   | v0.3.0   | v0.2.0 | version 0.1.9 is not above the latest tag v0.2.0; nothing to release, or pass a higher version     |
      | next    | v0.3.0   | v0.2.0 | not a version: next                                                                                |
      | 0.2.0   | v0.3.0   | next   | the latest tag is not a version: next                                                              |


  Scenario: Tidy a changelog after git cliff --prepend
    Given the text:
      """
      # Changelog

      <!-- git-cliff: end of header -->


      ## [0.3.0] - 2026-10-02


      - Two


      ## [0.2.0] - 2026-10-01

      - One

      """
    When I tidy the changelog
    Then the result is:
      """
      # Changelog

      <!-- git-cliff: end of header -->

      ## [0.3.0] - 2026-10-02

      - Two

      ## [0.2.0] - 2026-10-01

      - One
      """


  Scenario: Take one version's section
    Given the text:
      """
      # Changelog

      ## [0.3.0] - 2026-10-02

      Highlights of 0.3.0.

      ### 🚀 Features

      - Two ([#40](https://github.com/moonrockz/smithy/pull/40))

      ## [0.2.0] - 2026-10-01

      - One
      """
    When I take the changelog section for "v0.3.0"
    Then the result is:
      """
      Highlights of 0.3.0.

      ### 🚀 Features

      - Two ([#40](https://github.com/moonrockz/smithy/pull/40))
      """

  Scenario: Take the last section
    Given the text:
      """
      ## [0.3.0] - 2026-10-02

      - Two

      ## [0.2.0] - 2026-10-01

      - One
      """
    When I take the changelog section for "0.2.0"
    Then the result is:
      """
      - One
      """

  Scenario Outline: No section for the version
    Given the text:
      """
      ## [0.3.0] - 2026-10-02

      - Two

      ## [0.2.0] - 2026-10-01
      """
    When I take the changelog section for "<version>"
    Then there is no section

    Examples:
      | version |
      | 0.4.0   |
      | 0.3.1   |
      | 0.30.0  |

  Scenario: A section with no lines is still a section
    Given the text:
      """
      ## [0.3.0] - 2026-10-02
      """
    When I take the changelog section for "0.3.0"
    Then the section is empty


  Scenario: Release notes start with the install lines
    Given the text:
      """
      Highlights of 0.3.0.

      ### 🚀 Features

      - Two
      """
    When I make the release notes for "0.3.0"
    Then the result is:
      """
      **Install:**

      - `mise use github:moonrockz/smithy@0.3.0`
      - `moon add moonrockz/smithy-syntax@0.3.0`
      - `moonx moonrockz/zig-cross@0.3.0 --help`

      Highlights of 0.3.0.

      ### 🚀 Features

      - Two
      """


  Scenario: A section with the highlights placeholder
    Given the text:
      """

      <!-- Highlights: replace this comment with a few sentences on what this release brings. -->

      ### Features

      - One
      """
    Then the section has highlights: "no"

  Scenario: A section with written highlights
    Given the text:
      """

      smithy can now read a model.

      ### Features

      - One
      """
    Then the section has highlights: "yes"


  Scenario Outline: Refresh the release pull request from its branch only
    Then refreshing on branch "<branch>" for version "0.5.0" gives "<result>"

    Examples:
      | branch         | result                                                           |
      | release/v0.5.0 | ok: release/v0.5.0                                               |
      | main           | error: run release:refresh on release/v0.5.0, not on main        |
      | release/v0.4.0 | error: run release:refresh on release/v0.5.0, not on release/v0.4.0 |

  Scenario: The release pull request body tells how to refresh it
    Then the pull request body for "0.5.0" mentions "mise run release:refresh"

  Scenario: The release pull request opens as a draft
    Then opening the release pull request for "0.5.0" passes "--draft" to gh

  Scenario Outline: Refresh marks the release pull request ready once it has highlights
    Given the changelog section has highlights: "<highlights>"
    Then refreshing runs the gh commands "<commands>"

    Examples:
      | highlights | commands          |
      | yes        | pr edit, pr ready |
      | no         | pr edit           |

  Scenario Outline: Refresh uses the pushed changelog and warns about local changes
    Then refreshing with the local changelog "<local>" and the pushed changelog "<pushed>" warns "<warning>"

    Examples:
      | local       | pushed      | warning                                                                                                                              |
      | highlights  | highlights  |                                                                                                                                      |
      | highlights  | placeholder | warning: CHANGELOG.md differs from origin/release/v0.5.0; refresh uses the pushed text. Commit and push, then run release:refresh again |


  Scenario Outline: A breaking commit needs a BREAKING CHANGE footer
    Given the commit "<subject>" with the footer "<footer>"
    Then the breaking commits without a footer are "<missing>"

    Examples:
      | subject                                  | footer                                | missing                                  |
      | feat(printer)!: Elm formatter (#44)       | BREAKING CHANGE: print_file changes   |                                          |
      | feat(printer)!: Elm formatter (#44)       | BREAKING-CHANGE: print_file changes   |                                          |
      | feat(printer)!: Elm formatter (#44)       |                                       | feat(printer)!: Elm formatter (#44)       |
      | feat!: drop the old API                   | breaking change: lower case           | feat!: drop the old API                   |
      | feat(parser): a new rule (#45)            |                                       |                                          |
      | fix: say what breaks! (#46)               |                                       |                                          |

  Scenario: Read the commits of a git log
    Given the text:
      """
      feat(printer)!: Elm formatter (#44)

      Adds format.

      BREAKING CHANGE: print_file changes.
      ==smithy-commit-end==
      fix(scanner)!: stricter hex (#45)
      ==smithy-commit-end==
      docs: cookbook (#46)
      ==smithy-commit-end==
      """
    Then the breaking commits without a footer in the log are "fix(scanner)!: stricter hex (#45)"

  Scenario: The release pull request body names breaking commits without a footer
    Then the pull request body for "0.5.0" with the missing footer "fix(scanner)!: stricter hex (#45)" mentions "fix(scanner)!: stricter hex (#45)"


  Scenario Outline: The latest version among the tags
    Then the latest version of tags "<tags>" is "<latest>"

    Examples:
      | tags                         | latest |
      | v0.1.0 v0.2.0                | 0.2.0  |
      | v0.10.0 v0.9.0 v0.2.0        | 0.10.0 |
      | v0.2.0 0.3.0 vnext v1.0      | 0.2.0  |
      | other                        | none   |

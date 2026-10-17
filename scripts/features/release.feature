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

      **Wasm files:**

      - `smithy.wasm` needs a host that supplies the `__moonbit_fs_unstable` imports and `wasi_snapshot_preview1.fd_write`. `wasmtime` alone fails with `unknown import: __moonbit_fs_unstable::…`.
      - `smithy-gc.wasm` needs a host with WebAssembly GC that supplies the `__moonbit_fs_unstable` imports and `spectest.print_char`. `wasmtime` alone fails with `unknown import: __moonbit_fs_unstable::…`.

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

  Scenario Outline: Decide whether a Release run releases
    Given the event is "<event>", the ref type is "<type>" and the ref name is "<name>"
    And the commit is on main: "<main>"
    And the dry run input is: "<dry>"
    And the GitHub release exists: "<released>"
    And the changelog has the section: "<section>"
    Then the plan for version "0.0.1" is "<plan>"

    Examples:
      | event             | type   | name   | main | dry | released | section | plan                                                                                  |
      | pull_request      | branch | 12/merge | no   | no  | no       | no      | dry run 0.0.1                                                                         |
      | pull_request      | branch | 12/merge | no   | no  | yes      | yes     | dry run 0.0.1                                                                         |
      | workflow_dispatch | branch | main   | yes  | yes | no       | yes     | dry run 0.0.1                                                                         |
      | workflow_dispatch | branch | main   | yes  | yes | yes      | no      | dry run 0.0.1                                                                         |
      | push              | branch | main   | yes  | no  | no       | yes     | release 0.0.1                                                                         |
      | workflow_dispatch | branch | main   | yes  | no  | no       | yes     | release 0.0.1                                                                         |
      | push              | branch | main   | yes  | no  | yes      | yes     | skip: v0.0.1 is already released                                                      |
      | push              | branch | main   | yes  | no  | no       | no      | error: CHANGELOG.md has no section for 0.0.1; release with `mise run release:prepare` |
      | push              | tag    | v0.0.1 | yes  | no  | no       | yes     | release 0.0.1                                                                         |
      | push              | tag    | v0.0.1 | yes  | no  | yes      | yes     | skip: v0.0.1 is already released                                                      |
      | push              | tag    | v0.0.1 | no   | no  | no       | yes     | error: v0.0.1 is not on main                                                          |
      | push              | tag    | v0.0.2 | yes  | no  | no       | yes     | error: tag v0.0.2 does not match moon.mod version 0.0.1 (v0.0.1)                      |
      | push              | branch | topic  | no   | no  | no       | yes     | error: topic is not on main                                                           |

  Scenario Outline: A release needs its highlights
    Given the event is "push", the ref type is "branch" and the ref name is "main"
    And the changelog section has highlights: "<highlights>"
    Then the plan for version "0.0.1" is "<plan>"

    Examples:
      | highlights | plan                                                                                                                                  |
      | yes        | release 0.0.1                                                                                                                         |
      | no         | error: the CHANGELOG.md section for 0.0.1 still has the highlights placeholder; write the highlights on release/v0.0.1, then merge |

  Scenario: A dry run needs no highlights
    Given the event is "pull_request", the ref type is "branch" and the ref name is "7/merge"
    And the changelog section has highlights: "no"
    Then the plan for version "0.0.1" is "dry run 0.0.1"

  Scenario: Outputs for the workflow
    Then the outputs for a "release" of "0.0.1" are:
      """
      release=true
      dry_run=false
      version=0.0.1
      tag=v0.0.1
      """

  Scenario: Outputs for a dry run
    Then the outputs for a "dry run" of "0.0.1" are:
      """
      release=false
      dry_run=true
      version=0.0.1
      tag=v0.0.1
      """

  Scenario: Outputs for a skip
    Then the outputs for a "skip" of "0.0.1" are:
      """
      release=false
      dry_run=false
      """

  Scenario Outline: The gh commands of the GitHub release step
    Given the local assets are "smithy.wasm checksums.txt" and the GitHub release has "<remote>"
    Then the gh steps when the release exists: "<exists>" are "<steps>"

    Examples:
      | exists | remote                    | steps                                                                                                   |
      | no     |                           | release create v0.0.1 --target abc123 --title v0.0.1 --notes-file notes.md dist/smithy.wasm dist/checksums.txt |
      | yes    | smithy.wasm checksums.txt |                                                                                                         |
      | yes    | smithy.wasm               | release upload v0.0.1 dist/checksums.txt --clobber                                                      |
      | yes    |                           | release upload v0.0.1 dist/smithy.wasm dist/checksums.txt --clobber                                     |

  Scenario: A draft release is published after its assets are complete
    Given the local assets are "smithy.wasm checksums.txt" and the GitHub release has "smithy.wasm checksums.txt"
    Then the gh steps for a draft release are "release edit v0.0.1 --draft=false"

  Scenario: A draft release that lacks assets gets them first
    Given the local assets are "smithy.wasm checksums.txt" and the GitHub release has "smithy.wasm"
    Then the gh steps for a draft release are "release upload v0.0.1 dist/checksums.txt --clobber | release edit v0.0.1 --draft=false"

  Scenario Outline: Retry only the failures that a retry can fix
    Then a command that exits with <code> and prints "<output>" is transient: "<transient>"

    Examples:
      | code | output                           | transient |
      | 0    | timed out                        | no        |
      | 1    | Connection reset by peer         | yes       |
      | 1    | HTTP 503 Service Unavailable     | yes       |
      | 1    | API rate limit exceeded          | yes       |
      | 1    | HTTP 403 rate limit exceeded     | no        |
      | 1    | HTTP 401 Unauthorized            | no        |
      | 1    | HTTP 409 timeout                 | no        |
      | 1    | release not found                | no        |

  Scenario: The version mooncakes.io publishes
    Given the text:
      """
      {"module":"moonrockz/smithy-syntax","version":"0.0.1","yanked":false}
      """
    Then the mooncakes.io version is "0.0.1"

  Scenario Outline: mooncakes.io answers without a version
    Given the text:
      """
      <answer>
      """
    Then the mooncakes.io version is "none"

    Examples:
      | answer                   |
      | {"error":"not found"}    |
      | <html>Bad gateway</html> |
      | {"version":"latest"}     |

  Scenario: Released
    Given moon.mod on main is "0.0.1" and the latest tag is "0.0.1"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has "0.0.1"
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      ok: v0.0.1 is released: tag, GitHub release and mooncakes.io
      """

  Scenario: An independently released tool does not hide the original publication
    Given the text:
      """json
      {"version":"0.1.2","versions":[{"version":"0.1.2","yanked":false},{"version":"0.1.1","yanked":false}]}
      """
    Then the mooncakes.io version for release "0.1.1" is "0.1.1"

  Scenario: A newer version does not prove the original release was published
    Given the text:
      """json
      {"version":"0.1.2","versions":[{"version":"0.1.2","yanked":false}]}
      """
    Then the mooncakes.io version for release "0.1.1" is "0.1.2"

  Scenario Outline: Missing or yanked publication data cannot pass status
    Given the text:
      """json
      <answer>
      """
    Then the mooncakes.io version for release "0.1.1" is "none"

    Examples:
      | answer                                                                      |
      | {"version":"0.1.1"}                                                         |
      | {"version":"0.1.1","versions":[]}                                           |
      | {"version":"0.1.1","versions":[{"version":"0.1.1","yanked":true}]}          |
      | {"error":"not found"}                                                       |

  Scenario: Released, with work on main and an open release pull request
    Given moon.mod on main is "0.0.1" and the latest tag is "0.0.1"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has "0.0.1"
    And 4 unreleased commits and release pull requests "release/v0.0.2"
    Then the status report is:
      """
      ok: v0.0.1 is released: tag, GitHub release and mooncakes.io
      info: 4 commits on main since v0.0.1
      info: open release pull request: release/v0.0.2
      """

  Scenario: Tagged without a GitHub release
    Given moon.mod on main is "0.0.1" and the latest tag is "0.0.1"
    And the main version is tagged: "yes", has a GitHub release: "no", mooncakes.io has "0.0.1"
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: v0.0.1 is tagged but has no GitHub release; run `gh workflow run release.yml --ref v0.0.1`
      """

  Scenario: The GitHub release lacks assets
    Given moon.mod on main is "0.0.1" and the latest tag is "0.0.1"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has "0.0.1"
    And the GitHub release lacks the assets "smithy.wasm checksums.txt"
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: the GitHub release v0.0.1 lacks assets: smithy.wasm, checksums.txt; run `gh workflow run release.yml --ref v0.0.1`
      """

  Scenario: Tagged but not published
    Given moon.mod on main is "0.0.2" and the latest tag is "0.0.2"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has "0.0.1"
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: v0.0.2 is tagged but mooncakes.io has 0.0.1; run `gh workflow run release.yml --ref v0.0.2`
      """

  Scenario: One module is behind on mooncakes.io
    Given moon.mod on main is "0.0.2" and the latest tag is "0.0.2"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has "0.0.2"
    And mooncakes.io has "0.0.2" for "moonrockz/smithy-syntax" and "0.0.1" for "moonrockz/zig-cross"
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: v0.0.2 is tagged but mooncakes.io has moonrockz/smithy-syntax 0.0.2, moonrockz/zig-cross 0.0.1; run `gh workflow run release.yml --ref v0.0.2`
      """

  Scenario: mooncakes.io cannot be read
    Given moon.mod on main is "0.0.1" and the latest tag is "0.0.1"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has ""
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: v0.0.1 is tagged but mooncakes.io could not be read; run `gh workflow run release.yml --ref v0.0.1`
      """

  Scenario: The version on main has no tag
    Given moon.mod on main is "0.0.2" and the latest tag is "0.0.1"
    And the main version is tagged: "no", has a GitHub release: "no", mooncakes.io has "0.0.2"
    And 1 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: moon.mod on main is 0.0.2 but v0.0.2 has no tag (mooncakes.io has 0.0.2); check the latest Release run (`gh run list --workflow release.yml`), fix the cause, then run `gh workflow run release.yml --ref main`
      info: 1 commits on main since v0.0.1
      """

  Scenario: The version on main is below the latest tag
    Given moon.mod on main is "0.0.1" and the latest tag is "0.0.2"
    And the main version is tagged: "no", has a GitHub release: "no", mooncakes.io has "0.0.2"
    And 0 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: moon.mod on main is 0.0.1 but the latest tag is v0.0.2; set moon.mod to the released version or release a higher one
      """

  Scenario: Nothing released yet
    Given moon.mod on main is "0.0.1" and the latest tag is ""
    And the main version is tagged: "no", has a GitHub release: "no", mooncakes.io has ""
    And 12 unreleased commits and release pull requests ""
    Then the status report is:
      """
      info: Nothing released yet; moon.mod on main is 0.0.1
      info: 12 commits on main
      """

  Scenario: mooncakes.io has the version but there is no tag
    Given moon.mod on main is "0.0.1" and the latest tag is ""
    And the main version is tagged: "no", has a GitHub release: "no", mooncakes.io has "0.0.1"
    And 3 unreleased commits and release pull requests ""
    Then the status report is:
      """
      problem: mooncakes.io already has 0.0.1 but there is no tag and no GitHub release (mooncakes.io has 0.0.1); re-run failed jobs, or run `gh workflow run release.yml --ref main`
      info: 3 commits on main
      """

  Scenario: Two open release pull requests
    Given moon.mod on main is "0.0.2" and the latest tag is "0.0.2"
    And the main version is tagged: "yes", has a GitHub release: "yes", mooncakes.io has "0.0.2"
    And 2 unreleased commits and release pull requests "release/v0.0.3, release/v0.0.4"
    Then the status report is:
      """
      ok: v0.0.2 is released: tag, GitHub release and mooncakes.io
      info: 2 commits on main since v0.0.2
      problem: more than one open release pull request (release/v0.0.3, release/v0.0.4); close all but one
      """

  Scenario Outline: Tell from git whether the commit is on main
    Then git merge-base exits with <code> and prints "<output>" gives "<answer>"

    Examples:
      | code | output                | answer                                                                                                                                                                 |
      | 0    |                       | on main                                                                                                                                                                |
      | 1    |                       | not on main                                                                                                                                                            |
      | 128  | fatal: no merge base  | error: cannot tell whether v0.0.1 is on main: `git merge-base --is-ancestor HEAD origin/main` exited with 128: fatal: no merge base                                  |

  Scenario Outline: A release counts as done only with every asset
    Given the event is "push", the ref type is "tag" and the ref name is "v0.0.1"
    And the GitHub release exists with draft "<draft>" and the assets "<assets>"
    Then the plan for version "0.0.1" is "<plan>"

    Examples:
      | draft | assets                                                                                                                                       | plan                             |
      | no    | smithy-linux-x64.tar.gz smithy-linux-arm64.tar.gz smithy-darwin-arm64.tar.gz smithy-darwin-x64.tar.gz smithy-windows-x64.zip smithy.wasm smithy-gc.wasm checksums.txt | skip: v0.0.1 is already released |
      | no    | smithy-linux-x64.tar.gz smithy-linux-arm64.tar.gz smithy-darwin-arm64.tar.gz smithy-darwin-x64.tar.gz smithy-windows-x64.zip smithy.wasm smithy-gc.wasm | release 0.0.1                    |
      | no    |                                                                                                                                              | release 0.0.1                    |
      | yes   | smithy-linux-x64.tar.gz smithy-linux-arm64.tar.gz smithy-darwin-arm64.tar.gz smithy-darwin-x64.tar.gz smithy-windows-x64.zip smithy.wasm smithy-gc.wasm checksums.txt | release 0.0.1                    |

  Scenario: The expected assets are the files that dist.mbtx writes
    Then the expected assets are the names that dist.mbtx writes

  Scenario: Check a released version against its original publication list
    Given the publication script is:
      """moonbit
      let publish_list : Array[(String, String)] = [
        ("pkgs/smithy-syntax", "moonrockz/smithy-syntax"),
        ("apps/zig-cross", "moonrockz/zig-cross"),
      ]
      """
    Then status for version "0.0.1" tagged "yes" reads "v0.0.1:scripts/publish.mbtx"
    And the publication modules are "moonrockz/smithy-syntax, moonrockz/zig-cross"

  Scenario Outline: Releases after the tool migration exclude zig-cross
    Given the publication script is:
      """moonbit
      let publish_list : Array[(String, String)] = [
        ("pkgs/smithy-syntax", "moonrockz/smithy-syntax"),
        ("pkgs/smithy", "moonrockz/smithy"),
        ("apps/smithy", "moonrockz/smithy-cli"),
      ]
      """
    Then status for version "0.2.0" tagged "<tagged>" reads "<source>"
    And the publication modules are "moonrockz/smithy-syntax, moonrockz/smithy, moonrockz/smithy-cli"

    Examples:
      | tagged | source                          |
      | no     | origin/main:scripts/publish.mbtx |
      | yes    | v0.2.0:scripts/publish.mbtx       |

  Scenario: A missing publication list cannot silently pass release status
    Given the publication script is:
      """moonbit
      let renamed_list = []
      """
    Then the publication modules are "error: publication script has no publish_list"

  Scenario: Read publication entries wrapped by moon fmt
    Given the publication script is:
      """moonbit
      let publish_list : Array[(String, String)] = [
        (
          "pkgs/a-very-long-package-directory",
          "moonrockz/a-very-long-module-name",
        ),
        ("apps/smithy", "moonrockz/smithy-cli"),
      ]
      """
    Then the publication modules are "moonrockz/a-very-long-module-name, moonrockz/smithy-cli"

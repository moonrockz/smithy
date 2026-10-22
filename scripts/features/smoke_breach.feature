Feature: One GitHub issue per smoke breach
  A breach is a failed smoke in a trusted run on main or on a release tag. Its signature is the
  fingerprint of the smoke inputs and the result of each failed platform. The report files one issue
  with the label smoke-breach. The same breach again changes nothing. A changed breach updates the open
  issue. A breach that comes back after a close reopens its issue. A passing smoke closes the open issue.

  Scenario: The failed legs of a run
    When I read the jobs of the run:
      """
      {"jobs": [
        {"name": "Smoke / Smoke (linux-x64)", "conclusion": "success", "html_url": "https://x/1", "check_run_url": "https://api.github.com/repos/o/r/check-runs/1"},
        {"name": "Smoke / Smoke (darwin-x64)", "conclusion": "failure", "html_url": "https://x/2", "check_run_url": "https://api.github.com/repos/o/r/check-runs/2"},
        {"name": "Smoke / Smoke (windows-x64)", "conclusion": "timed_out", "html_url": "https://x/3", "check_run_url": "https://api.github.com/repos/o/r/check-runs/3"},
        {"name": "Smoke / Record smoke evidence", "conclusion": "skipped", "html_url": "https://x/4", "check_run_url": "https://api.github.com/repos/o/r/check-runs/4"},
        {"name": "Cross-build release outputs", "conclusion": "failure", "html_url": "https://x/5", "check_run_url": "https://api.github.com/repos/o/r/check-runs/5"},
        {"name": "Smoke / Smoke (linux-arm64)", "conclusion": null, "html_url": "https://x/6", "check_run_url": "https://api.github.com/repos/o/r/check-runs/6"}
      ]}
      """
    Then the failed legs are "darwin-x64 failure repos/o/r/check-runs/2|windows-x64 timed_out repos/o/r/check-runs/3|linux-arm64 unknown repos/o/r/check-runs/6"

  Scenario: The failure messages of a leg
    When I read the annotations of a leg:
      """
      [
        {"annotation_level": "warning", "message": "Node.js 20 is deprecated."},
        {"annotation_level": "failure", "message": "smithy version did not print 0.5.0"},
        {"annotation_level": "failure", "message": "Process completed with exit code 1."}
      ]
      """
    Then the messages are "smithy version did not print 0.5.0|Process completed with exit code 1."

  Scenario: The signature names the inputs and the failed platforms, not the run
    Given a breach of fingerprint "f1" with "darwin-x64 failure" in run "https://x/runs/1"
    When I take the signature
    And the breach is in run "https://x/runs/2" of commit "other"
    Then the signature is the same

  Scenario: The signature does not depend on the order of the legs
    Given a breach of fingerprint "f1" with "darwin-x64 failure,linux-arm64 failure" in run "https://x/runs/1"
    When I take the signature
    And the breach has the legs "linux-arm64 failure,darwin-x64 failure"
    Then the signature is the same

  Scenario Outline: A change of the breach changes the signature
    Given a breach of fingerprint "f1" with "darwin-x64 failure" in run "https://x/runs/1"
    When I take the signature
    And the breach is of fingerprint "<fingerprint>" with "<legs>"
    Then the signature is not the same

    Examples:
      | fingerprint | legs                                   |
      | f2          | darwin-x64 failure                     |
      | f1          | darwin-x64 timed_out                   |
      | f1          | darwin-x64 failure,linux-arm64 failure |
      | f1          | linux-arm64 failure                    |

  Scenario: Read the signature from an issue body
    Then the signature in the body "text\n<!-- smoke-breach v1 signature=abc123 -->\nmore" is "abc123"
    And the signature in the body "no marker" is ""

  Scenario Outline: What the report does
    Given the issues "<issues>"
    Then the report for signature "s1" is "<action>"

    Examples:
      | issues                        | action    |
      |                               | create    |
      | 4 closed s9                   | create    |
      | 4 closed                      | create    |
      | 4 open s1                     | nothing 4 |
      | 4 open s2                     | update 4  |
      | 4 open                        | update 4  |
      | 4 closed s1                   | reopen 4  |
      | 4 closed s1,7 closed s1      | reopen 7  |
      | 4 closed s1,9 open s2        | update 9  |
      | 9 open s2,12 open s1         | nothing 12 |

  Scenario: What a passing smoke closes
    Given the issues "4 closed s1,9 open s2,12 open s1"
    Then a passing smoke closes "9|12"

  Scenario Outline: Which gh failures are tried again
    Then a gh call that exits with <code> and prints "<output>" is transient: "<transient>"

    Examples:
      | code | output                                 | transient |
      | 0    | ok                                     | no        |
      | 1    | HTTP 502: Bad Gateway                  | yes       |
      | 1    | Get api.github.com: i/o timeout        | yes       |
      | 1    | connection reset by peer               | yes       |
      | 1    | API rate limit exceeded                | yes       |
      | 1    | HTTP 403: Resource not accessible      | no        |
      | 1    | HTTP 401: Bad credentials              | no        |
      | 1    | HTTP 422: Validation Failed            | no        |

  Scenario: The issue title names the failed platforms
    Given a breach of fingerprint "f1" with "darwin-x64 failure,linux-arm64 timed_out" in run "https://x/runs/1"
    Then the title is "Smoke failed on main: darwin-x64, linux-arm64"

  Scenario: The issue body
    Given a breach of fingerprint "f1" with "darwin-x64 failure" in run "https://x/runs/1"
    And the leg "darwin-x64" has the job "https://x/2" and the messages "smithy version did not print 0.5.0"
    Then the body starts with:
      """
      A release binary failed its smoke test in a trusted run. A release of these inputs will fail its smoke job.

      | Platform | Result | Job | Messages |
      | --- | --- | --- | --- |
      | darwin-x64 | failure | [job](https://x/2) | smithy version did not print 0.5.0 |

      - Run: https://x/runs/1 (push, refs/heads/main)
      - Commit: abc
      - Version: 0.5.0
      - Fingerprint of the smoke inputs: `f1`

      Fix the cause. A passing smoke in a trusted run closes this issue. To smoke again, run the Release workflow with `dry_run` on main.
      """
    And the body ends with the marker of its signature

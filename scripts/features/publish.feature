Feature: Publish to mooncakes.io
  The publish script publishes the public modules in dependency order. A network failure that a retry can fix
  is tried again. A version that mooncakes.io already holds counts as published, so a second release run for
  the same tag succeeds.

  Scenario Outline: Classify the result of moon publish
    Given moon publish exits with <code> and prints "<output>"
    Then the outcome is "<outcome>"

    Examples:
      | code | output                                                                                                                                       | outcome           |
      | 0    | Server status: 200 OK                                                                                                                        | published         |
      | 255  | Server status: 409 Conflict, detail: Version Error: The version you are attempting to upload (0.2.0) is duplicated with an existing version. | already published |
      | 255  | Server status: 401 Unauthorized                                                                                                              | failed            |
      | 255  | Server status: 503 Service Unavailable                                                                                                       | transient         |
      | 1    | connection reset by peer                                                                                                                     | transient         |
      | 1    | Check failed                                                                                                                                 | failed            |

  Scenario Outline: Retry only the failures that a retry can fix
    Then a command that exits with <code> and prints "<output>" is transient: "<transient>"

    Examples:
      | code | output                       | transient |
      | 0    | timed out                    | no        |
      | 1    | request timed out            | yes       |
      | 1    | Connection reset by peer     | yes       |
      | 1    | HTTP 502 Bad Gateway         | yes       |
      | 1    | HTTP 503 Service Unavailable | yes       |
      | 1    | API rate limit exceeded      | yes       |
      | 1    | HTTP 403 rate limit exceeded | no        |
      | 1    | HTTP 401 Unauthorized        | no        |
      | 1    | HTTP 409 timeout             | no        |
      | 255  | Prebuilt wasm asset does not exist | yes |
      | 1    | Check failed                 | no        |

  Scenario: Every module in the publish list is a workspace member
    Then every module in the publish list is in moon.work

  Scenario: The two copies of the publish list agree
    Then the publish list is the one in release.mbtx

  Scenario: Smithy publishes its own modules after the tool migration
    Then the published modules are "moonrockz/jmespath, moonrockz/smithy-syntax, moonrockz/smithy, moonrockz/smithy-cli"

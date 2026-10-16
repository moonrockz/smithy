Feature: mooncakes.io credentials
  The credentials script writes the token from MOONCAKES_USER_TOKEN to
  ~/.moon/credentials.json for the release workflow.

  Scenario: Plain token
    Given the token is "abc123"
    When I render the credentials
    Then the credentials file is:
      """
      {
        "token": "abc123"
      }
      """

  Scenario: Token with characters that JSON must escape
    Given the token is 'a"b\c'
    When I render the credentials
    Then the credentials file is:
      """
      {
        "token": "a\"b\\c"
      }
      """

  Scenario: Missing token
    Given no token is set
    When I render the credentials
    Then rendering fails with "MOONCAKES_USER_TOKEN is not set; cannot write mooncakes.io credentials"

  Scenario: Empty token
    Given the token is ""
    When I render the credentials
    Then rendering fails with "MOONCAKES_USER_TOKEN is not set; cannot write mooncakes.io credentials"

  Scenario: MOON_HOME is set
    Given MOON_HOME is "/opt/moon"
    And HOME is "/home/ci"
    When I choose the credentials directory
    Then the directory is "/opt/moon"

  Scenario: MOON_HOME is empty
    Given MOON_HOME is ""
    And HOME is "/home/ci"
    When I choose the credentials directory
    Then the directory is "/home/ci/.moon"

  Scenario: MOON_HOME is not set
    Given HOME is "/home/ci"
    When I choose the credentials directory
    Then the directory is "/home/ci/.moon"

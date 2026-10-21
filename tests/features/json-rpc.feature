Feature: JSON-RPC requests and notifications
  A Smithy service defines the methods whose incoming JSON messages are checked.

  Scenario: Version 2 positional calls use the explicit input order
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC message "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":1}"
    Then the RPC message is a valid "call"
    When I validate the RPC message "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,\"23\"],\"id\":1}"
    Then the RPC finding is "TypeMismatch" at "/params/1" on "example#SubtractInput$subtrahend"

  Scenario: Version 2 named notifications use member names
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC message "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":{\"subtrahend\":23,\"minuend\":42}}"
    Then the RPC message is a valid "notification"

  Scenario: Version 1 null ID means notification
    Given the calculator API prepared for JSON-RPC "1.0"
    When I validate the RPC message "{\"method\":\"subtract\",\"params\":[42,23],\"id\":null}"
    Then the RPC message is a valid "notification"
    When I validate the RPC message "{\"method\":\"subtract\",\"params\":[42,23],\"id\":99}"
    Then the RPC message is a valid "call"

  Scenario: Version 2 present null ID remains a call
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC message "{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":null}"
    Then the RPC message is a valid "call"
    And the RPC message has only an ID advisory

  Scenario: Unknown methods are rejected
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC message "{\"jsonrpc\":\"2.0\",\"method\":\"missing\"}"
    Then the RPC finding is "UnknownMethod" at "/method" on "example#Calculator"

  Scenario: Omitted parameters still require modeled inputs
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC message "{\"jsonrpc\":\"2.0\",\"method\":\"subtract\"}"
    Then the RPC finding is "RequiredMember" at "/params/minuend" on "example#SubtractInput$minuend"

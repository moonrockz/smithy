Feature: JSON-RPC requests notifications and batches
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

  Scenario: Request batches retain original element paths
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC request batch "[{\"jsonrpc\":\"2.0\",\"method\":\"ping\"},{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,\"bad\"]}]"
    Then the batch finding is "TypeMismatch" at "/1/params/1"

  Scenario: Response batch order does not determine method association
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC request batch "[{\"jsonrpc\":\"2.0\",\"method\":\"subtract\",\"params\":[42,23],\"id\":9007199254740993},{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":\"second\"}]"
    And I validate its response batch "[{\"jsonrpc\":\"2.0\",\"result\":null,\"id\":\"second\"},{\"jsonrpc\":\"2.0\",\"result\":19,\"id\":9007199254740993}]"
    Then the response batch is valid

  Scenario: Notifications require silence instead of an empty response array
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC request batch "[{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}]"
    And I validate its absent batch response
    Then the response batch is valid
    When I validate its response batch "[]"
    Then the response batch is invalid

  Scenario: Empty batches require one invalid-request error
    Given the calculator API prepared for JSON-RPC "2.0"
    When I validate the RPC request batch "[]"
    Then the batch finding is "InvalidEnvelope" at ""
    When I validate its response batch "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"},\"id\":null}"
    Then the response batch is valid

  Scenario: Version 1 multiple messages are distinct from version 2 batches
    Given the calculator API prepared for JSON-RPC "1.0"
    When I validate the RPC request batch "[{\"method\":\"ping\",\"params\":[],\"id\":1}]"
    Then the batch finding is "UnsupportedMessage" at ""

Feature: OpenRPC documents describe the same methods as JSON-RPC validation

  Scenario: Export a complete JSON-RPC service
    Given the OpenRPC calculator model
    When I export OpenRPC with settings "{\"service\":\"example.rpc#Calculator\"}"
    Then the OpenRPC document describes named positional and either methods
    And OpenRPC preserves explicit null results and application error data

  Scenario: Make omitted protocol semantics visible
    Given the OpenRPC calculator model
    When I export OpenRPC with settings "{\"service\":\"example.rpc#Calculator\",\"extensions\":\"omit\"}"
    Then OpenRPC reports structured omission warnings

  Scenario: Reject a JSON-RPC 1.0 selection
    Given the OpenRPC calculator model
    When I export OpenRPC with settings "{\"service\":\"example.rpc#Calculator\",\"protocolVersion\":\"1.0\"}"
    Then OpenRPC reports an invalid selection for "example.rpc#Calculator"

  Scenario: Reject a missing service
    Given the OpenRPC calculator model
    When I export OpenRPC with settings "{\"service\":\"example.rpc#Missing\"}"
    Then OpenRPC reports an invalid selection for "example.rpc#Missing"

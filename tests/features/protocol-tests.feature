Feature: HTTP protocol compliance cases
  Load modeled cases and compare messages produced by an external protocol.

  Scenario: A serialized request matches its modeled case
    Given the greeting protocol test suite
    When the fixture protocol produces a "POST" request
    Then the protocol case matches

  Scenario: A mismatch names the HTTP field
    Given the greeting protocol test suite
    When the fixture protocol produces a "GET" request
    Then the protocol case reports a method mismatch

  Scenario: An omitted body expectation makes no body assertion
    Given the greeting protocol test suite
    When the fixture protocol produces a response with an arbitrary body
    Then the protocol case matches

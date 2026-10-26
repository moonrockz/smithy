Feature: JSON-RPC transcripts
  A two-peer protocol names the services that each peer accepts. A transcript
  records the messages that the peers send, and the checker correlates replies
  with calls.

  Scenario: Version 1 echo and chat transcripts are valid
    Given the "example.peers#EchoChat" protocol in "peers.smithy"
    When I check the transcript file "echo.json"
    Then the transcript is valid
    And the transcript has no findings
    When I check the transcript file "chat.json"
    Then the transcript is valid
    And the transcript has no findings

  Scenario: Replies are correlated per sender
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the transcript file "editor.json"
    Then the transcript is valid
    And the transcript has no findings

  Scenario: Unsolicited, duplicate and wrong-responder replies
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the transcript:
      """json
      {
        "version": "2.0",
        "entries": [
          { "from": "server", "message": {"jsonrpc": "2.0", "id": 9, "result": "full"} },
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}} },
          { "from": "server", "message": {"jsonrpc": "2.0", "id": 1, "result": "full"} },
          { "from": "server", "message": {"jsonrpc": "2.0", "id": 1, "result": "full"} },
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 2, "method": "shutdown"} },
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 2, "result": null} }
        ]
      }
      """
    Then the transcript is invalid
    And the transcript has the error "UnsolicitedResponse" at entry 0
    And the transcript has the error "DuplicateResponse" at entry 3
    And the transcript has the error "WrongResponder" at entry 5

  Scenario: Null versus absent notification IDs differ between 1.0 and 2.0
    Given the "example.peers#EchoChat" protocol in "peers.smithy"
    When I check the transcript:
      """json
      {
        "version": "1.0",
        "complete": true,
        "entries": [
          { "from": "client", "message": {"method": "postMessage", "params": ["Hello all!"], "id": null} },
          { "from": "server", "message": {"result": 1, "error": null, "id": null} }
        ]
      }
      """
    Then the transcript has the error "ResponseToNotification" at entry 1
    And the transcript has no finding at entry 0
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the transcript:
      """json
      {
        "version": "2.0",
        "complete": true,
        "entries": [
          { "from": "client", "message": {"jsonrpc": "2.0", "method": "exit"} },
          { "from": "client", "message": {"jsonrpc": "2.0", "method": "shutdown", "id": null} }
        ]
      }
      """
    Then the transcript has the error "MissingResponse" at entry 1
    And the transcript has no finding at entry 0

  Scenario: A partial transcript lists outstanding calls; a complete one reports missing replies
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the transcript:
      """json
      {
        "version": "2.0",
        "entries": [
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}} }
        ]
      }
      """
    Then the transcript is valid
    And the transcript has the advisory "OutstandingCall" at entry 0
    And 1 call is outstanding
    When I check the same transcript as complete
    Then the transcript is invalid
    And the transcript has the error "MissingResponse" at entry 0

  Scenario: A batch in a transcript
    Given the "batch#Link" protocol in "batches.smithy"
    When I check the transcript file "batches.json"
    Then the transcript is valid
    And the transcript has no findings

  Scenario: Expected findings make a negative transcript pass
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the transcript file "editor-negative.json"
    Then the transcript is invalid
    And the transcript matches its expected findings

  Scenario: Markdown transcripts
    Given the "example.peers#EchoChat" protocol in "peers.smithy"
    When I check the transcript file "echo.md"
    Then the transcript is valid
    And the transcript has no findings
    When I check the transcript file "chat.md"
    Then the transcript is valid
    And the transcript has no findings

  Scenario: A Markdown transcript with expected findings
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the Markdown transcript:
      """markdown
      ---
      version: "2.0"
      ---
      A reply with no call.

      ```jsonrpc server -> client
      {"jsonrpc": "2.0", "id": 9, "result": "full"}
      ```

      ```jsonrpc-expect
      [{"code": "UnsolicitedResponse", "entry": 0}]
      ```
      """
    Then the transcript is invalid
    And the transcript has the error "UnsolicitedResponse" at entry 0
    And the transcript matches its expected findings

  Scenario: A JSONL log is read line by line
    Given the "example.peers#Editor" protocol in "peers.smithy"
    And the log direction "in" is sent by "client"
    And the log direction "out" is sent by "server"
    When I check the version "2.0" log file "editor.jsonl"
    Then the transcript is valid
    And the transcript has no findings
    And the log has 19 lines, 8 not JSON and 2 skipped
    When I check the version "2.0" log:
      """
      starting
      {"dir": "out", "message": {"jsonrpc": "2.0", "id": 9, "result": "full"}}
      {"dir": "sideways", "message": {"jsonrpc": "2.0", "method": "exit"}}
      """
    Then the transcript is invalid
    And the transcript has the error "UnsolicitedResponse" at entry 0
    And the log has 3 lines, 1 not JSON and 0 skipped

  Scenario: A session checks the order of methods and the advertised capabilities
    Given the "example.lifecycle#Lifecycle" protocol in "lifecycle.smithy"
    When I check the transcript file "lifecycle-valid.json"
    Then the transcript is valid
    And the transcript has no findings
    When I check the transcript file "lifecycle-violation.json"
    Then the transcript is invalid
    And the transcript has the error "StateViolation" at entry 0
    And the transcript has the error "CapabilityNotAdvertised" at entry 3
    And the transcript has the advisory "CancelInactiveCall" at entry 5
    And the transcript has the error "RefusalExpected" at entry 6
    And the transcript has the error "StateViolation" at entry 9
    And the transcript matches its expected findings

  Scenario: An LSP-like editor session starts with initialize and ends with shutdown and exit
    Given the "example.peers#OrderedEditor" protocol in "peers.smithy"
    When I check the transcript file "editor.json"
    Then the transcript is valid
    And the transcript has no findings
    When I check the transcript:
      """json
      {
        "version": "2.0",
        "entries": [
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "textDocument/hover", "params": {"uri": "file:///a.txt"}} },
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 2, "method": "initialize", "params": {"processId": 42}} },
          { "from": "server", "message": {"jsonrpc": "2.0", "id": 2, "result": "full"} },
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 3, "method": "shutdown"} },
          { "from": "server", "message": {"jsonrpc": "2.0", "id": 3, "result": null} },
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 4, "method": "textDocument/hover", "params": {"uri": "file:///a.txt"}} },
          { "from": "client", "message": {"jsonrpc": "2.0", "method": "exit"} }
        ]
      }
      """
    Then the transcript is invalid
    And the transcript has the error "StateViolation" at entry 0
    And the transcript has the error "StateViolation" at entry 5
    And the transcript has no finding at entry 6

  Scenario: A protocol without a session ignores the lifecycle traits
    Given the "example.peers#Editor" protocol in "peers.smithy"
    When I check the transcript:
      """json
      {
        "version": "2.0",
        "complete": true,
        "entries": [
          { "from": "client", "message": {"jsonrpc": "2.0", "id": 1, "method": "textDocument/hover", "params": {"uri": "file:///a.txt"}} },
          { "from": "server", "message": {"jsonrpc": "2.0", "id": 1, "result": "docs"} }
        ]
      }
      """
    Then the transcript is valid
    And the transcript has no findings

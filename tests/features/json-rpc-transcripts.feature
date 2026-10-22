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

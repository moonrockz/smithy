$version: "2"
namespace example

use smithy.test#httpRequestTests
use smithy.test#httpResponseTests

@trait
@protocolDefinition
structure fixtureProtocol {}

@httpRequestTests([{
    id: "GreetingRequest"
    protocol: fixtureProtocol
    method: "POST"
    uri: "/greeting"
    params: {name: "Ada"}
    headers: {"Content-Type": "application/json"}
    forbidHeaders: ["X-Secret"]
    body: "{\"name\":\"Ada\"}"
    bodyMediaType: "application/json"
}])
@httpResponseTests([{
    id: "GreetingResponse"
    protocol: fixtureProtocol
    code: 200
    params: {greeting: "Hello, Ada"}
}])
operation Greet { input: Input, output: Output }

structure Input { @required name: String }
structure Output { greeting: String }

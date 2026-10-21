$version: "2"
namespace example.core

use aws.protocols#restJson1

@restJson1
@httpBasicAuth
@httpBearerAuth
@auth([httpBasicAuth, httpBearerAuth])
service Example {
    version: "2026-10-21"
    resources: [Widget]
}

resource Widget {
    identifiers: {id: String}
    properties: {value: Value}
    read: Read
}

@readonly
@http(method: "GET", uri: "/widgets/{id}")
@auth([httpBearerAuth])
operation Read {
    input: ReadInput
    output: ReadOutput
    errors: [SecondError, FirstError]
}

@input
structure ReadInput {
    @required
    @httpLabel
    id: String
}

@trait(selector: "structure")
structure Annotation {}

@output
@Annotation
structure ReadOutput {
    @required
    value: Value
}

union Value {
    text: String
    record: Record
    document: Document
}

structure Record {
    @required
    name: String
}

@error("client")
structure FirstError {
    @required
    message: String
    @required
    @httpHeader("retry-after")
    retry: Integer
}

@error("client")
structure SecondError {
    message: String
    @httpHeader("retry-after")
    retry: Integer
}

// Prefix headers on an unbound structure do not participate in conversion.
structure Detached {
    @httpPrefixHeaders("x-detached-")
    headers: Headers
}

map Headers { key: String, value: String }

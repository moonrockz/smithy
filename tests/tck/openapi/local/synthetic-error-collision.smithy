$version: "2"
namespace example.review
use aws.protocols#restJson1

@restJson1
service Collision { version: "1", operations: [Get] }
@http(method: "GET", uri: "/")
operation Get { output: Output, errors: [First, Second] }
@output
structure Output { modeled: Get400Error }
structure Get400Error { original: String }
@error("client")
structure First { first: String }
@error("client")
structure Second { second: Integer }

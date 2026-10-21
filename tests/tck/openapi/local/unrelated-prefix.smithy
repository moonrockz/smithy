$version: "2"
namespace example.review
use aws.protocols#restJson1

@restJson1
service Selected { version: "1", operations: [Get] }
@http(method: "GET", uri: "/selected")
operation Get {}

@restJson1
service Other { version: "1", operations: [Unused] }
@http(method: "GET", uri: "/unused")
operation Unused { input: OtherInput }
@input
structure OtherInput { @httpPrefixHeaders("x-other-") headers: Headers }
map Headers { key: String, value: String }

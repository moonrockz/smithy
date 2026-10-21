$version: "2"
namespace example.review
use aws.protocols#restJson1

@restJson1
service Structures { version: "1", operations: [GetStructures] }
@http(method: "GET", uri: "/structures")
operation GetStructures { output: StructureOutput }
@output
structure StructureOutput { first: Foo_Bar, second: FooBar }
structure Foo_Bar { text: String }
structure FooBar { count: Integer }

@restJson1
service Maps { version: "1", operations: [GetMaps] }
@http(method: "GET", uri: "/maps")
operation GetMaps { output: MapOutput }
@output
structure MapOutput { first: Map_Foo, second: MapFoo }
map Map_Foo { key: String, value: String }
map MapFoo { key: String, value: Integer }

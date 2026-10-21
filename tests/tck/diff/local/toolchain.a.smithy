$version: "2"
metadata removed = { x: 1 }
metadata changed = "old"
namespace example.diff

@trait
structure OldTrait {}
@length(min: 0, max: 100)
string Text
@range(min: -100, max: 100)
integer Number
@default(0)
integer Default
structure Value {
    @required
    required: String
    @required
    client: String
    defaulted: Integer = 0
    optional: String
}
structure In { value: Value, text: Text, number: Number }
structure In2 { value: Value, text: Text, number: Number }
structure Out {}
structure Out2 {}
@error("client")
structure OldError {}
@error("client")
structure NewError {}
@error("client")
structure OldServiceError {}
@error("client")
structure NewServiceError {}
operation Op { input: In, output: Out, errors: [OldError] }
operation Op2 {}
operation Op3 {}
resource Child {}
resource Parent { operations: [Op2] }
service Api {
    version: "1"
    operations: [Op]
    errors: [OldServiceError]
    resources: [Parent]
    rename: { "example.diff#Value": "OldValue", "example.diff#Text": "OldText" }
}

$version: "2"
metadata added = [true]
metadata changed = "new"
namespace example.diff

@trait
structure NewTrait {}
@length(min: 1, max: 50)
string Text
@range(min: -50, max: 50)
integer Number
@default(1)
integer Default
structure Value {
    required: String
    @required @clientOptional
    client: String
    defaulted: Integer = 1
    @required
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
operation Op { input: In2, output: Out2, errors: [NewError] }
operation Op2 {}
operation Op3 {}
resource Child {}
resource Parent { operations: [Op3], resources: [Child] }
service Api {
    version: "2"
    operations: [Op]
    errors: [NewServiceError]
    resources: [Parent]
    rename: { "example.diff#Value": "NewValue", "example.diff#Number": "NewNumber" }
}

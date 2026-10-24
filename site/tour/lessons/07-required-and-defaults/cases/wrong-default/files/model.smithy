$version: "2"

namespace example

structure Customer {
    @required
    name: String

    email: String

    points: Integer = "zero"
}

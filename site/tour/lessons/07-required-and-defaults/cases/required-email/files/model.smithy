$version: "2"

namespace example

structure Customer {
    @required
    name: String

    @required
    email: String

    points: Integer = 0
}

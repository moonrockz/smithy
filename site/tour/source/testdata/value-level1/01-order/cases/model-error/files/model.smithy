$version: "2"

namespace example

structure Order {
    @range(min: 1)
    id: String

    @range(min: 1, max: 10)
    quantity: Integer
}

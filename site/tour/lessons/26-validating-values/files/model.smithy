$version: "2"

namespace example.orders

/// An order in a shop.
structure Order {
    @required
    id: String

    @range(min: 1, max: 10)
    quantity: Integer

    @length(max: 20)
    note: String
}

$version: "2"
namespace example

structure Order {
    @required
    id: String

    @range(min: 1)
    quantity: Integer
}

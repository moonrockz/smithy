$version: "2"

namespace example

union PaymentMethod {
    card: Card
    cash: Unit
}

structure Card {
    @required
    number: String
}

structure Order {
    payment: PaymentMethod
}

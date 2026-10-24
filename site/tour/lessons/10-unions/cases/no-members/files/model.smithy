$version: "2"

namespace example

union PaymentMethod {
}

structure Card {
    @required
    number: String
}

structure Order {
    payment: PaymentMethod
}

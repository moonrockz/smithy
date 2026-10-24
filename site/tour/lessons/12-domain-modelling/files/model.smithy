$version: "2"

namespace example.shop

/// An order ID, such as `ORD-12345`.
@pattern("^ORD-[0-9]{5}$")
string OrderId

/// The state of an order.
enum OrderState {
    PLACED
    PAID
    SHIPPED
    CANCELLED
}

/// One way to pay for an order.
union PaymentMethod {
    card: CardPayment
    invoice: Unit
}

structure CardPayment {
    /// The last four digits of the card number.
    @required
    @pattern("^[0-9]{4}$")
    lastDigits: String
}

@range(min: 1, max: 99)
integer Quantity

structure OrderLine {
    @required
    sku: String

    @required
    quantity: Quantity
}

list OrderLines {
    member: OrderLine
}

structure Order {
    @required
    id: OrderId

    @required
    state: OrderState = "PLACED"

    @required
    payment: PaymentMethod

    @required
    @length(min: 1)
    lines: OrderLines
}

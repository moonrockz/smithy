$version: "2"

namespace example

enum OrderState {
    PENDING
    SHIPPED = "shipped"
    DELIVERED = "delivered"
}

intEnum Priority {
    LOW
    HIGH = 2
}

structure Order {
    state: OrderState
    priority: Priority
}

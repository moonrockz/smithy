$version: "2"

namespace example

enum OrderState {
    PENDING
    SHIPPED = "shipped"
    DELIVERED = "shipped"
}

intEnum Priority {
    LOW = 1
    HIGH = 2
}

structure Order {
    state: OrderState
    priority: Priority
}

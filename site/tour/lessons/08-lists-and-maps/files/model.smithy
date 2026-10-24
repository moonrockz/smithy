$version: "2"

namespace example

list Tags {
    member: String
}

map Stock {
    key: String
    value: Integer
}

structure Product {
    tags: Tags
    stock: Stock
}

$version: "2"

namespace example

list Tags {
    member: String
}

map Stock {
    key: Integer
    value: Integer
}

structure Product {
    tags: Tags
    stock: Stock
}

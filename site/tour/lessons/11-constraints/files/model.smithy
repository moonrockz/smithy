$version: "2"

namespace example

@length(min: 1, max: 64)
string ProductName

@pattern("^[A-Z]{3}$")
string CurrencyCode

@range(min: 1, max: 100)
integer Quantity

structure OrderLine {
    name: ProductName
    currency: CurrencyCode
    quantity: Quantity
}

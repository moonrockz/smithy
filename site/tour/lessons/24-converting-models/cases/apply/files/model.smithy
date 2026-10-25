$version: "2"

namespace example

/// A city on the map.
structure City {
    @required
    name: String

    population: Integer
}

apply City$name @length(min: 1, max: 64)

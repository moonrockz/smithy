$version: "2"

namespace example

/// A city on the map.
structure City {
    @required
    name: String

    population: Integer

    country: CountryCode
}

@length(min: 2, max: 2)
string CountryCode

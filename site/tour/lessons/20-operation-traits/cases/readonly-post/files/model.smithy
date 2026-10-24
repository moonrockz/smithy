$version: "2"

namespace example

use aws.protocols#restJson1

@restJson1
service Weather {
    version: "2024-01-01"
    operations: [ListCities, GetCity, PutCity, DeleteCity]
}

/// Lists the cities, one page at a time.
@readonly
@paginated(inputToken: "nextToken", outputToken: "nextToken", pageSize: "pageSize", items: "cities")
@http(method: "GET", uri: "/cities")
operation ListCities {
    input := {
        @httpQuery("nextToken")
        nextToken: String

        @httpQuery("pageSize")
        pageSize: Integer
    }

    output := {
        nextToken: String

        @required
        cities: CityNames
    }
}

@readonly
@http(method: "POST", uri: "/cities/{name}")
operation GetCity {
    input := {
        @required
        @httpLabel
        name: String
    }

    output := {
        @required
        name: String
    }
}

@idempotent
@http(method: "PUT", uri: "/cities/{name}")
operation PutCity {
    input := {
        @required
        @httpLabel
        name: String

        population: Integer
    }
}

@idempotent
@http(method: "DELETE", uri: "/cities/{name}")
operation DeleteCity {
    input := {
        @required
        @httpLabel
        name: String
    }
}

list CityNames {
    member: String
}

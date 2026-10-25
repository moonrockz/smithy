$version: "2"

namespace example

/// Gives the weather of a city.
service Weather {
    version: "2024-01-01"
    resources: [City]
}

/// A city that has a forecast.
resource City {
    identifiers: { cityId: CityId }
    create: CreateCity
    read: GetCity
    list: ListCities
    operations: [GetForecast]
}

operation CreateCity {
    input := {
        @required
        name: String
    }
    output := {
        @required
        cityId: CityId
    }
}

@readonly
operation GetCity {
    input := {
        @required
        cityId: CityId
    }
    output := {
        @required
        name: String
    }
}

@readonly
operation ListCities {
    output := {
        @required
        cityIds: CityIdList
    }
}

@readonly
operation GetForecast {
    input := {
        @required
        cityId: CityId
    }
    output := {
        chanceOfRain: Float
    }
}

@pattern("^[a-z0-9-]+$")
string CityId

list CityIdList {
    member: CityId
}

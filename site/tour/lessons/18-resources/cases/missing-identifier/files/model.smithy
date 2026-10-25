$version: "2"

namespace example

use smithy.protocols#rpcv2Json

@rpcv2Json
service Weather {
    version: "2024-01-01"
    resources: [City]
}

/// A city that has a forecast.
resource City {
    identifiers: { cityId: CityId }
    properties: { name: String }
    create: CreateCity
    read: GetCity
    list: ListCities
}

@pattern("^[a-z0-9-]+$")
string CityId

operation CreateCity {
    input := for City {
        @required
        $name
    }

    output := for City {
        @required
        $cityId
    }
}

@readonly
operation GetCity {
    input := for City {
        @required
        $name
    }

    output := for City {
        @required
        $cityId

        @required
        $name
    }
}

@readonly
operation ListCities {
    output := {
        @required
        cityIds: CityIdList
    }
}

list CityIdList {
    member: CityId
}

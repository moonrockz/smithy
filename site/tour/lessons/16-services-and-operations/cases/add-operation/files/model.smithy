$version: "2"

namespace example

use smithy.protocols#rpcv2Json

/// Gives the weather of a city.
@rpcv2Json
service Weather {
    version: "2024-01-01"
    operations: [GetForecast, GetCity]
}

/// Gives the forecast for one city.
operation GetForecast {
    input := {
        @required
        cityId: String
    }

    output := {
        @required
        chanceOfRain: Float
    }
}

/// Gives the name of a city.
operation GetCity {
    input := {
        @required
        cityId: String
    }

    output := {
        @required
        name: String
    }
}

$version: "2"

namespace example

use smithy.protocols#rpcv2Json

@rpcv2Json
service Weather {
    version: "2024-01-01"
    operations: [GetForecast]
    errors: [ServiceUnavailable]
}

operation GetForecast {
    input := {
        @required
        cityId: String
    }

    output := {
        @required
        chanceOfRain: Float
    }

    errors: [CityNotFound]
}

/// The city does not exist.
@error("client")
@httpError(200)
structure CityNotFound {
    @required
    message: String
}

/// The service cannot answer now. Try again later.
@error("server")
@retryable
structure ServiceUnavailable {
    message: String
}

$version: "2"

namespace example

use aws.protocols#restJson1

@restJson1
service Weather {
    version: "2024-01-01"
    operations: [GetForecast, PutPhoto]
}

@readonly
@http(method: "GET", uri: "/forecast")
operation GetForecast {
    input := {
        @required
        @httpLabel
        cityId: String

        @httpQuery("days")
        days: Integer

        @httpHeader("Accept-Language")
        language: String
    }

    output := {
        @required
        chanceOfRain: Float

        @httpHeader("Cache-Control")
        cacheControl: String
    }
}

@idempotent
@http(method: "PUT", uri: "/cities/{cityId}/photo")
operation PutPhoto {
    input := {
        @required
        @httpLabel
        cityId: String

        @required
        @httpPayload
        photo: Blob
    }
}

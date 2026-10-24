$version: "2"

namespace example

use aws.protocols#restJson1

@restJson1
service Weather {
    version: "2024-01-01"
    operations: [GetCity]
}

@readonly
@http(method: "GET", uri: "/cities/{cityId}")
operation GetCity {
    input := {
        @required
        @httpLabel
        cityId: String
    }

    output := {
        @required
        name: String

        population: Integer

        photo: Photo
    }
}

@mediaType("image/png")
blob Photo

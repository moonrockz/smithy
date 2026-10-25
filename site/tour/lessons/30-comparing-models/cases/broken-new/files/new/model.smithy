$version: "2"

namespace example.weather

service Weather {
    version: "2026-10-01"
    operations: [GetForecast]
}

operation GetForecast {
    input := {
        @required
        city: String

        days: Integer
    }

    output := {
        @required
        summary: String

        celsius: Celsius

        humidity: Integer
    }
}

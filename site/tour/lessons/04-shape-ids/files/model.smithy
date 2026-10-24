$version: "2"

namespace example.weather

use example.common#CityName

structure Forecast {
    city: CityName
    summary: String
}

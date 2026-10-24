$version: "2"

namespace example

@documentation("A city on the map.")
@tag(["geo"])
structure City {
    @required
    @length(min: 1, max: 64)
    name: String

    @range(min: -90, max: 90)
    latitude: Float
}

apply City$latitude @documentation("Degrees north of the equator.")

$version: "2"

namespace example

@documentation("A city on the map.")
@tags(["geo"])
structure City {
    @required
    @length(min: 1, max: 64)
    name: String

    @length(min: 1)
    latitude: Float
}

apply City$latitude @documentation("Degrees north of the equator.")

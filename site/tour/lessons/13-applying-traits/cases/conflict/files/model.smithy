$version: "2"

namespace example

@documentation("A city on the map.")
@tags(["geo"])
structure City {
    @required
    @length(min: 1, max: 64)
    name: String

    @range(min: -90, max: 90)
    latitude: Float
}

apply City$latitude @documentation("Degrees north of the equator.")
apply City$name @length(min: 2)

$version: "2"

namespace example

/// The fields that every record has.
@mixin
structure Audited {
    @required
    createdAt: Timestamp

    updatedAt: Timestamp
}

/// A city on the map.
structure City with [Audited] {
    @required
    name: String
}

apply City$createdAt @documentation("When the city was added.")

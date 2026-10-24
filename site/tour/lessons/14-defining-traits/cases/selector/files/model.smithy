$version: "2"

namespace example

/// Marks a structure as an event that the service publishes.
@trait(selector: "structure[trait|error]")
structure event {
    /// The name of the event on the wire.
    @required
    name: String
}

@event(name: "city-created")
structure CityCreated {
    @required
    cityId: String
}

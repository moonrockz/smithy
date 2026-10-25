$version: "2"

namespace example

use smithy.contracts#conditions

/// A period of time in a log search.
@conditions({
    startBeforeEnd: {
        expression: "start < end"
        documentation: "The start time must be before the end time."
    }
})
structure TimeRange {
    @required
    start: Timestamp

    @required
    end: Timestamp
}

/// The ID of a city, such as "new-york".
@conditions({
    NoSpaces: {
        expression: "!contains(@, ' ')"
        documentation: "A city ID has no spaces."
    }
})
string CityId

structure Search {
    cityId: CityId = "new-york"

    range: TimeRange
}

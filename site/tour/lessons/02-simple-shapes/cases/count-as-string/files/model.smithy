$version: "2"

namespace example

string SensorName

structure Reading {
    sensor: SensorName
    count: String
    valid: Boolean
    takenAt: Timestamp
    raw: Blob
    value: BigDecimal
    extra: Document
}

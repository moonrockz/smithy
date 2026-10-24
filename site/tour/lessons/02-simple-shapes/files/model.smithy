$version: "2"

namespace example

string SensorName

structure Reading {
    sensor: SensorName
    count: Integer
    valid: Boolean
    takenAt: Timestamp
    raw: Blob
    value: BigDecimal
    extra: Document
}

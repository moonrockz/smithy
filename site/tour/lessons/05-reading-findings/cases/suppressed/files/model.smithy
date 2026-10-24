$version: "2"

namespace example

@deprecated(message: "Use Celsius.")
integer Fahrenheit

integer Celsius

structure Reading {
    @suppress(["DeprecatedShape"])
    temperature: Fahrenheit
}

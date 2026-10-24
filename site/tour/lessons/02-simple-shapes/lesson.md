# Simple shapes

A simple shape has no nested types, and it does not refer to other shapes.

This lesson uses seven simple types:

- `string`: UTF-8 text.
- `integer`: a 32-bit signed integer.
- `boolean`: a Boolean value.
- `timestamp`: an instant in time, with a resolution of 1 millisecond.
- `blob`: binary data that Smithy does not interpret.
- `bigDecimal`: a signed decimal number of arbitrary precision.
- `document`: open content, a kind of "any" type. It can hold strings, numbers, Booleans, nulls, lists and maps with string keys.

Smithy has more simple types, for example `long`, `double` and `enum`.

To define a simple shape, write the type and a name. This model defines the string shape `SensorName`.

The members of the structure `Reading` target simple shapes. The member `sensor` targets `SensorName`. The other members target shapes from the prelude, such as `Integer` and `Timestamp`. Every model can use these shapes. [Shape IDs, use and the prelude](../shape-ids/) gives more information about the prelude.

Look at the JSON Schema output. The converter gives each member a JSON Schema:

- `string` and `blob` become `"type": "string"`.
- `integer` and `bigDecimal` become `"type": "number"`.
- `boolean` becomes `"type": "boolean"`.
- `timestamp` becomes `"type": "string"` with `"format": "date-time"`.
- `document` becomes `{}`, a schema with no type.

Now change `count: Integer` to `count: String`. The output now gives `count` the type `"string"`. Change it back.

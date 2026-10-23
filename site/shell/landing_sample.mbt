///|
/// The hero example. `landing/sample/` holds the same text; the prerender
/// test and `scripts/test-cli.mbtx` keep both in step with the real CLI.
pub struct HeroSample {
  model : String
  value : String
  command : String
  output : String
}

///|
pub fn hero_sample() -> HeroSample {
  {
    model: hero_model,
    value: hero_value,
    command: hero_command,
    output: hero_output,
  }
}

///|
let hero_model : String =
  #|$version: "2"
  #|namespace example
  #|
  #|structure Order {
  #|    @required
  #|    id: String
  #|
  #|    @range(min: 1)
  #|    quantity: Integer
  #|}
  #|

///|
let hero_value : String =
  #|{"id": "A-17", "quantity": 0}
  #|

///|
let hero_command : String =
  #|smithy validate value --shape example#Order --value order.json order.smithy
  #|

///|
let hero_output : String =
  #|order.json/quantity: error[Range] example#Order$quantity: I expected the number to satisfy the modeled range.
  #|

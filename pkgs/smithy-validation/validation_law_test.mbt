///|
test "law: JSON and NodeValue adapters agree without changing inputs" {
  let prepared = validator(
    "list Value { member: Record }\nstructure Record { @range(min: -100, max: 100) number: Long, @length(max: 4) text: String, nested: Document }",
  )
  @quickcheck.check(
    (entries : Array[(Int64, String)]) => {
      let input = Json::array(
        entries.map(entry => {
          let numeric = Json::number(
            entry.0.to_double(),
            repr=entry.0.to_string(),
          )
          Json::object({
            "number": numeric,
            "text": Json::string(entry.1),
            "nested": Json::array([
              numeric,
              Json::object({ "text": Json::string(entry.1) }),
            ]),
          })
        }),
      )
      let original = input.stringify()
      let node = @smithy.NodeValue::from_json(input) catch { _ => return false }
      let json_result = prepared.validate_json(input)
      let node_result = prepared.validate(node)
      json_result == node_result &&
      input.stringify() == original &&
      prepared.validate_json(input) == json_result
    },
    count=250,
    max_size=20,
    seed=3403,
  )
}

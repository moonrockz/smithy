///|
priv struct Constraints {
  min : @smithy.NodeNumber?
  max : @smithy.NodeNumber?
  min_length : @smithy.NodeNumber?
  max_length : @smithy.NodeNumber?
  pattern : BoundedPattern?
  unique : Bool
  timestamp : TimestampFormat
} derive(Debug)

///|
fn effective_trait(
  shape : @smithy.Shape,
  target : @smithy.Shape,
  name : String,
) -> @smithy.NodeValue? {
  match shape.trait_value(name) {
    Some(value) => Some(value)
    None => target.trait_value(name)
  }
}

///|
fn constraint_bounds(
  value : @smithy.NodeValue?,
  id : @smithy.ShapeId,
  length~ : Bool = false,
) -> (@smithy.NodeNumber?, @smithy.NodeNumber?) raise PreparationError {
  guard value is Some(value) else { return (None, None) }
  guard value is Object(fields) else {
    raise InvalidModel(
      id, "I expected an object constraint, but found another value kind.",
    )
  }
  let read = fn(name : String) -> @smithy.NodeNumber? raise PreparationError {
    match fields.get(name) {
      None => None
      Some(Number(number)) => {
        if length &&
          (
            !number.is_integer() ||
            number.numeric_compare(@smithy.NodeNumber::parse("0").unwrap()) < 0
          ) {
          raise InvalidModel(
            id, "I expected a nonnegative integer length bound.",
          )
        }
        Some(number)
      }
      _ => raise InvalidModel(id, "I expected a numeric constraint bound.")
    }
  }
  for name, _ in fields {
    if name != "min" && name != "max" {
      raise InvalidModel(id, "I found an unknown constraint bound.")
    }
  }
  let min = read("min")
  let max = read("max")
  if min is None && max is None {
    raise InvalidModel(id, "I expected at least one constraint bound.")
  }
  if min is Some(min) && max is Some(max) && min.numeric_compare(max) > 0 {
    raise InvalidModel(
      id, "I expected the minimum constraint bound to be no greater than the maximum.",
    )
  }
  (min, max)
}

///|
fn annotation(
  value : @smithy.NodeValue?,
  id : @smithy.ShapeId,
) -> Bool raise PreparationError {
  match value {
    None => false
    Some(Object(fields)) if fields.is_empty() => true
    _ => raise InvalidModel(id, "I expected an empty annotation object.")
  }
}

///|
fn prepare_constraints(
  shape : @smithy.Shape,
  target : @smithy.Shape,
  config : Config,
) -> Constraints raise PreparationError {
  let id = shape.id
  let trait_ = fn(name) { effective_trait(shape, target, "smithy.api#" + name) }
  if effective_trait(shape, target, "smithy.contracts#conditions") is Some(_) {
    raise UnsupportedConstraint(
      id, "I cannot evaluate runtime contract conditions in this validation profile.",
    )
  }
  let range = trait_("range")
  let length = trait_("length")
  let pattern = trait_("pattern")
  let unique = annotation(trait_("uniqueItems"), id) || target.is_legacy_set()
  if range is Some(_) &&
    !(target.body
    is Simple(
      Byte
      | Short
      | Integer
      | Long
      | Float
      | Double
      | BigInteger
      | BigDecimal
    ) ||
    target.body is IntEnum(_)) {
    raise InvalidModel(
      id, "I expected a numeric target for the range constraint.",
    )
  }
  if length is Some(_) &&
    !(target.body is Simple(String | Blob) ||
    target.body is Enum(_) ||
    target.body is List(_) ||
    target.body is Map(..)) {
    raise InvalidModel(
      id, "I expected a string, blob or collection for the length constraint.",
    )
  }
  if unique && !(target.body is List(_)) {
    raise InvalidModel(id, "I expected a list for the uniqueness constraint.")
  }
  let (min, max) = constraint_bounds(range, id)
  let (min_length, max_length) = constraint_bounds(length, id, length=true)
  let compiled = match pattern {
    None => None
    Some(String(text)) if target.body is Simple(String) ||
      target.body is Enum(_) => Some(compile_pattern(text, id))
    _ =>
      raise InvalidModel(id, "I expected a string pattern on a string shape.")
  }
  let timestamp = match trait_("timestampFormat") {
    None => config.timestamp_format
    Some(String("epoch-seconds")) => EpochSeconds
    Some(String("date-time")) => DateTime
    Some(String(_)) =>
      raise UnsupportedConstraint(
        id, "I cannot validate this timestamp format in the JSON value profile.",
      )
    _ => raise InvalidModel(id, "I expected a string timestamp format.")
  }
  { min, max, min_length, max_length, pattern: compiled, unique, timestamp, }
}

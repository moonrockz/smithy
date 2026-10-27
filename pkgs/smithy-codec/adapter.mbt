///|
/// A logical scalar produced or consumed by an adapter.
pub(all) enum ScalarValue {
  Text(String)
  Numeric(@smithy.NodeNumber)
  Flag(Bool)
} derive(Eq, Debug)

///|
fn ScalarValue::kind(self : ScalarValue) -> @contract.JsonKind {
  match self {
    Text(_) => StringKind
    Numeric(_) => NumberKind
    Flag(_) => BooleanKind
  }
}

///|
/// An adapter refusal, at a path relative to the value that the adapter reads.
pub struct AdapterFailure {
  path : @validation.InstancePath
  message : String
} derive(Eq, Debug)

///|
pub fn AdapterFailure::new(
  message : String,
  path~ : @validation.InstancePath = @validation.InstancePath::root(),
) -> AdapterFailure {
  { path, message, }
}

///|
/// What an adapter may do during one call: charge work to the request.
pub struct AdapterContext {
  priv meter : @validation.WorkMeter
}

///|
/// Charge `units` of work. False means that the request has no work left; the adapter must then fail.
pub fn AdapterContext::charge(self : AdapterContext, units : Int32) -> Bool {
  self.meter.charge(units)
}

///|
/// A trusted host scalar adapter. It reads its declared JSON kinds into one logical scalar, writes the
/// canonical spelling of that scalar and may order dictionary keys. A model can name it, but only the host
/// can register it.
pub struct ScalarAdapter {
  signature : @contract.AdapterSignature
  priv reader : (Json, AdapterContext) -> Result[ScalarValue, AdapterFailure]
  priv writer : (ScalarValue, AdapterContext) -> Result[Json, AdapterFailure]
  priv compare : ((String, String) -> Int32)?
}

///|
pub fn ScalarAdapter::new(
  id : @contract.AdapterId,
  inputs~ : Array[@contract.JsonKind],
  output~ : @contract.JsonKind,
  read~ : (Json, AdapterContext) -> Result[ScalarValue, AdapterFailure],
  write~ : (ScalarValue, AdapterContext) -> Result[Json, AdapterFailure],
  compare~ : ((String, String) -> Int32)? = None,
) -> ScalarAdapter raise @contract.IdentityError {
  let signature = @contract.AdapterSignature::new(
    id,
    inputs~,
    output~,
    orders_keys=compare is Some(_),
  )
  { signature, reader: read, writer: write, compare, }
}

///|
pub fn ScalarAdapter::id(self : ScalarAdapter) -> @contract.AdapterId {
  self.signature.id
}

///|
/// The adapters that a host trusts, by identifier.
pub struct AdapterRegistry {
  priv adapters : Map[@contract.AdapterId, ScalarAdapter]
}

///|
pub fn AdapterRegistry::new() -> AdapterRegistry {
  { adapters: Map([]), }
}

///|
/// Register an adapter. Registering a second adapter with the same identifier is refused.
pub fn AdapterRegistry::register(
  self : AdapterRegistry,
  adapter : ScalarAdapter,
) -> AdapterRegistry raise @validation.ConfigurationError {
  if self.adapters.contains(adapter.id()) {
    raise @validation.ConfigurationError(
      "I already have an adapter \{adapter.id()}.",
    )
  }
  let adapters = Map::from_iter(self.adapters.iter())
  adapters[adapter.id()] = adapter
  { adapters, }
}

///|
pub fn AdapterRegistry::signatures(
  self : AdapterRegistry,
) -> Array[@contract.AdapterSignature] {
  self.adapters.values().map(a => a.signature).to_array()
}

///|
pub fn AdapterRegistry::get(
  self : AdapterRegistry,
  id : @contract.AdapterId,
) -> ScalarAdapter? {
  self.adapters.get(id)
}

///|
/// The exact number of a JSON number, using its retained token when present.
pub fn json_number(value : Json) -> @smithy.NodeNumber? {
  match value {
    Number(n, repr~) => @smithy.NodeNumber::parse(repr.unwrap_or(n.to_string()))
    _ => None
  }
}

///|
/// A JSON number that keeps the exact token of `n`.
pub fn number_json(n : @smithy.NodeNumber) -> Json {
  Json::number(n.approximate, repr=n.to_string())
}

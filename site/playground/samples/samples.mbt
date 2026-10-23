///|
/// One example of the playground picker: its title and the repository path
/// of its model.
pub(all) struct SampleSource {
  title : String
  path : String
} derive(Eq, Debug)

///|
pub extend SampleSource with Eq::{equal, not_equal}

///|
pub extend SampleSource with @debug.Debug::{to_repr}

///|
/// The examples of the playground picker, in the order of the picker. A model
/// from `examples/` is the file of that example. A model that only the
/// playground uses, such as the one with a deliberate mistake, is in
/// `site/playground/samples/`, so the examples index does not list it.
pub let manifest : Array[SampleSource] = [
  { title: "JSON-RPC chat protocol", path: "examples/json-rpc/peers.smithy", },
  {
    title: "JSON-RPC chat protocol (with a mistake)",
    path: "site/playground/samples/chat-error.smithy",
  },
  { title: "Order", path: "site/landing/sample/order.smithy", },
]

///|
/// The index in `manifest` of the example that the playground opens with.
pub let default_index : Int32 = 1

///|
/// An example of the picker with the text of its model.
pub(all) struct Sample {
  title : String
  path : String
  model : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Sample with Eq::{equal, not_equal}

///|
pub extend Sample with @debug.Debug::{to_repr}

///|
pub extend Sample with ToJson::{to_json}

///|
pub extend Sample with FromJson::{from_json}

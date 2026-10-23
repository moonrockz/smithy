///|
/// A model whose edge order differs from the lexical order of its shape IDs, so
/// that the tests below pin the evaluation order of each selector step.
fn selector_order_model() -> @smithy.Model {
  let source =
    #|$version: "2"
    #|namespace example
    #|
    #|@mixin
    #|structure Zeta { z: String }
    #|
    #|@documentation("root")
    #|structure Root with [Zeta] {
    #|  b: Bravo
    #|  a: Alpha
    #|  c: Bravo
    #|}
    #|
    #|structure Bravo { r: Root, n: Integer }
    #|
    #|@documentation("alpha")
    #|structure Alpha { r: Root, y: Bravo }
    #|
    #|service Shop {
    #|  version: "1"
    #|  resources: [Store]
    #|  operations: [Ping]
    #|}
    #|
    #|@documentation("store")
    #|resource Store {
    #|  operations: [Sell, Buy]
    #|  resources: [Shelf]
    #|}
    #|
    #|resource Shelf {
    #|  operations: [Stock]
    #|}
    #|
    #|operation Ping {}
    #|operation Sell {}
    #|operation Buy {}
    #|
    #|@documentation("stock")
    #|operation Stock {}
  @smithy.Loader::new().add_idl("order.smithy", source).assemble().model.unwrap()
}

///|
/// The selected IDs in evaluation order, without the lexical sort of
/// `select_ids`.
fn selector_order(selector : String) -> Array[String] raise {
  @smithy.Selector::parse(selector)
  .select_matches(selector_order_model())
  .map(m => m.id)
}

///|
test "forward neighbors keep the edge order" {
  debug_inspect(
    selector_order("structure[id|name=Root] > *"),
    content=(
      #|[
      #|  "example#Zeta",
      #|  "example#Root$z",
      #|  "example#Root$b",
      #|  "example#Root$a",
      #|  "example#Root$c",
      #|]
    ),
  )
  debug_inspect(
    selector_order("structure[id|name=Root] -[trait, mixin]-> *"),
    content=(
      #|["example#Zeta", "smithy.api#documentation"]
    ),
  )
  debug_inspect(
    selector_order("structure[id|name=Root] > member > *"),
    content=(
      #|["smithy.api#String", "example#Bravo", "example#Alpha"]
    ),
  )
}

///|
test "reverse neighbors keep the edge order" {
  debug_inspect(
    selector_order("structure[id|name=Root] < *"),
    content=(
      #|["example#Bravo$r", "example#Alpha$r"]
    ),
  )
  debug_inspect(
    selector_order("member[id|member=r] <-[member]- *"),
    content=(
      #|["example#Bravo", "example#Alpha"]
    ),
  )
  debug_inspect(
    selector_order("structure[id|name=Bravo] < member < *"),
    content=(
      #|["example#Root", "example#Alpha"]
    ),
  )
  debug_inspect(
    selector_order("[id|name=documentation] <-[trait]- [id|namespace=example]"),
    content=(
      #|["example#Root", "example#Alpha", "example#Store", "example#Stock"]
    ),
  )
}

///|
test "recursive neighbors keep the traversal order" {
  debug_inspect(
    selector_order("structure[id|name=Root] ~> *"),
    content=(
      #|[
      #|  "example#Zeta",
      #|  "example#Root$z",
      #|  "example#Root$b",
      #|  "example#Root$a",
      #|  "example#Root$c",
      #|  "example#Bravo",
      #|  "example#Bravo$r",
      #|  "example#Bravo$n",
      #|  "smithy.api#Integer",
      #|  "example#Alpha",
      #|  "example#Alpha$r",
      #|  "example#Alpha$y",
      #|  "smithy.api#String",
      #|  "example#Zeta$z",
      #|]
    ),
  )
  debug_inspect(
    selector_order("service ~> operation"),
    content=(
      #|["example#Ping", "example#Sell", "example#Buy", "example#Stock"]
    ),
  )
}

///|
test "in, recursive and topdown keep their output order" {
  debug_inspect(
    selector_order("structure[id|name=Root] ~> :in(structure)"),
    content=(
      #|["example#Zeta", "example#Bravo", "example#Alpha"]
    ),
  )
  debug_inspect(
    selector_order("structure[id|name=Root] :recursive(> member > *)"),
    content=(
      #|[
      #|  "smithy.api#String",
      #|  "example#Bravo",
      #|  "example#Alpha",
      #|  "example#Root",
      #|  "smithy.api#Integer",
      #|]
    ),
  )
  debug_inspect(
    selector_order("service :topdown(*)"),
    content=(
      #|[
      #|  "example#Shop",
      #|  "example#Store",
      #|  "example#Shelf",
      #|  "example#Stock",
      #|  "example#Buy",
      #|  "example#Sell",
      #|  "example#Ping",
      #|]
    ),
  )
  debug_inspect(
    selector_order("service :topdown([trait|documentation])"),
    content=(
      #|[
      #|  "example#Store",
      #|  "example#Shelf",
      #|  "example#Stock",
      #|  "example#Buy",
      #|  "example#Sell",
      #|]
    ),
  )
  debug_inspect(
    selector_order("service :topdown(*, [trait|documentation])"),
    content=(
      #|[
      #|  "example#Shop",
      #|  "example#Shelf",
      #|  "example#Buy",
      #|  "example#Sell",
      #|  "example#Ping",
      #|]
    ),
  )
}

///|
test "select_ids sorts and dedupes the matches of every start shape" {
  let model = selector_order_model()
  debug_inspect(
    @smithy.Selector::parse("[id|namespace=example] > member > structure").select_ids(
      model,
    ),
    content=(
      #|["example#Alpha", "example#Bravo", "example#Root"]
    ),
  )
  debug_inspect(
    @smithy.Selector::parse("> member > *").select_ids_from(
      model, "example#Root",
    ),
    content=(
      #|["example#Alpha", "example#Bravo", "smithy.api#String"]
    ),
  )
}

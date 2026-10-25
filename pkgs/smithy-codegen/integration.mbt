///|
/// A named extension of a generator. `C` is the context type of the director.
/// The fields are read-only outside this package.
pub struct Integration[C] {
  name : String
  run_before : Array[String]
  run_after : Array[String]
  priority : Int32
  preprocess_model : (@smithy.Model, PluginContext) -> @smithy.Model raise CodegenError
  decorate_symbol_provider : (SymbolProvider, PluginContext) -> SymbolProvider
  interceptors : (C) -> Array[Interceptor]
  customize : (C) -> Unit raise CodegenError
}

///|
pub fn[C] Integration::new(
  name : String,
  run_before~ : Array[String] = [],
  run_after~ : Array[String] = [],
  priority~ : Int32 = 0,
  preprocess_model~ : (@smithy.Model, PluginContext) -> @smithy.Model raise CodegenError = (
    m,
    _,
  ) => m,
  decorate_symbol_provider~ : (SymbolProvider, PluginContext) -> SymbolProvider = (
    p,
    _,
  ) => p,
  interceptors~ : (C) -> Array[Interceptor] = _ => [],
  customize~ : (C) -> Unit raise CodegenError = _ => (),
) -> Integration[C] {
  {
    name,
    run_before,
    run_after,
    priority,
    preprocess_model,
    decorate_symbol_provider,
    interceptors,
    customize,
  }
}

///|
/// Put the integrations in run order. `a.run_before` with `b` puts a before b.
/// `a.run_after` with `b` puts b before a. Names that no integration has are
/// ignored. Among the integrations that can run, the highest priority goes
/// first, then the smallest name. The sort uses no recursion.
pub fn[C] sort_integrations(
  items : Array[Integration[C]],
) -> Array[Integration[C]] raise CodegenError {
  let index : Map[String, Int32] = Map([])
  for i, item in items {
    if index.contains(item.name) {
      raise DuplicateIntegration(item.name)
    }
    index[item.name] = i
  }
  let after : Array[Set[Int32]] = items.map(_ => Set([]))
  let blockers : Array[Set[Int32]] = items.map(_ => Set([]))
  for i, item in items {
    for name in item.run_before {
      if index.get(name) is Some(j) {
        after[i].add(j)
        blockers[j].add(i)
      }
    }
    for name in item.run_after {
      if index.get(name) is Some(j) {
        after[j].add(i)
        blockers[i].add(j)
      }
    }
  }
  let waiting = blockers.map(set => set.length())
  let ready : Array[Int32] = []
  for i in 0..<items.length() {
    if waiting[i] == 0 {
      ready.push(i)
    }
  }
  let result : Array[Integration[C]] = []
  while !ready.is_empty() {
    let mut best = 0
    for k in 1..<ready.length() {
      let candidate = items[ready[k]]
      let current = items[ready[best]]
      if candidate.priority > current.priority ||
        (
          candidate.priority == current.priority &&
          candidate.name < current.name
        ) {
        best = k
      }
    }
    let picked = ready.remove(best)
    result.push(items[picked])
    for next in after[picked] {
      waiting[next] = waiting[next] - 1
      if waiting[next] == 0 {
        ready.push(next)
      }
    }
  }
  if result.length() < items.length() {
    let left : Array[String] = []
    for i in 0..<items.length() {
      if waiting[i] > 0 {
        left.push(items[i].name)
      }
    }
    left.sort()
    raise IntegrationCycle(left)
  }
  result
}

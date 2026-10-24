// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Modified for moonrockz/smithy-validation: the tables also hold the cost of
// each transition and the last search that charged it, and `reset` empties
// the tables.

///|
struct Regex {
  profile : Profile
  ctx : @automata.Context
  expr : @automata.Expr
  groups : ReadOnlyArray[String?]
  symbol_table : @symbol_map.Table
  symbol_repr : ReadOnlyArray[Rechar]
  start_states : Array[(Category, StateId)]
  mut state_table : @hashmap.HashMap[@automata.State, StateId]
  /// Indexed by `transition_base + symbol`; holds the encoded next state.
  mut transition_table : FixedArray[Int32]
  /// Parallel to `transition_table`; holds the slot of the next state so the
  /// scan loop needs no per-state lookup.
  mut slot_table : FixedArray[Int32]
  /// Parallel to `transition_table`; the work units that the transition cost
  /// when it was built.
  mut cost_table : FixedArray[Int32]
  /// Parallel to `transition_table`; the last search that charged the
  /// transition.
  mut stamp_table : FixedArray[Int32]
  /// The number of searches so far; the stamp of the running search.
  mut search : Int32
  /// Largest slot index of any stabilized state (bounds the scratch buffer).
  mut max_slot : Int32
  positions : Positions
  mut final_table : FixedArray[
    @list.List[(Category, @automata.Slot, @automata.Status, Int32)],
  ]
  mut states : FixedArray[@automata.State]
  mut num_states : Int32
}

///|
/// Function `group_names`.
pub fn Regex::group_names(self : Regex) -> ReadOnlyArray[String?] {
  self.groups
}

///|
fn Regex::new(
  profile : Profile,
  ctx : @automata.Context,
  expr : @automata.Expr,
  groups : ReadOnlyArray[String?],
  symbol_table : @symbol_map.Table,
  symbol_repr : ReadOnlyArray[Rechar],
) -> Regex {
  {
    profile,
    ctx,
    expr,
    groups,
    symbol_table,
    symbol_repr,
    start_states: [],
    state_table: HashMap([]),
    transition_table: [],
    slot_table: [],
    cost_table: [],
    stamp_table: [],
    search: 0,
    max_slot: 0,
    positions: Positions::new(),
    final_table: [],
    states: [],
    num_states: 0,
  }
}

///|
fn Regex::num_symbols(self : Regex) -> Int32 {
  self.symbol_repr.length()
}

///|
/// Forget every state, as a new `Regex` of the same pattern.
fn Regex::reset(self : Regex) -> Unit {
  self.start_states.clear()
  self.state_table = HashMap([])
  self.transition_table = []
  self.slot_table = []
  self.cost_table = []
  self.stamp_table = []
  self.max_slot = 0
  self.final_table = []
  self.states = []
  self.num_states = 0
}

///|
/// The work units that one transition is charged for the table growth that a
/// new state may need. A state has 4 * symbols + 2 cells in the six tables,
/// and doubling the tables allocates and copies at most 6 cells for each cell
/// of a state that was added. One unit pays for 8 cells: allocating or copying
/// a cell takes 0.07 ns native, 0.4 ns wasm-gc and 2.4 ns js, and one unit of
/// derivative work takes 12 to 20 ns.
fn Regex::growth_units(self : Regex) -> Int32 {
  (6 * (4 * self.num_symbols() + 2) + 7) / 8
}

///|
/// The most states the tables keep between searches: a power of two, at most
/// 4,096, with at most about 2^17 cells. A search starts with at most this
/// many states, so the first table doubling in it allocates and copies at
/// most 3 * max_states * (4 * symbols + 2) <= 3 * 2^17 cells; the growth
/// shares of earlier transitions pay for it. Later doublings in the same
/// search are paid by the states that the search adds.
fn Regex::max_states(self : Regex) -> Int32 {
  let limit = Int32::min(4096, (1 << 17) / (4 * self.num_symbols() + 2))
  let mut states = 16
  while states * 2 <= limit {
    states *= 2
  }
  states
}

// Added for moonrockz/smithy-validation.

///|
/// Search `input` from its start, spending at most `work` units. Returns
/// whether the search matched and the units it spent, or `None` when it needs
/// more than `work` units. A search that stops keeps no partial state. The
/// units depend only on the pattern and `input`: a transition that the tables
/// already hold costs what it cost to build, once per search. The tables are
/// emptied before a search when they hold `max_states` states.
pub fn Regex::matches(
  self : Regex,
  input : StringView,
  work~ : Int32,
) -> (Bool, Int32)? {
  if self.num_states >= self.max_states() {
    self.reset()
  }
  let meter = @automata.Meter::new(work)
  self.ctx.meter(meter)
  let matched = self.execute(input, 0) catch {
    @automata.Exhausted => {
      self.ctx.meter(@automata.Meter::unlimited())
      return None
    }
  }
  self.ctx.meter(@automata.Meter::unlimited())
  Some((matched is Some(_), work - meter.left()))
}

// Added for moonrockz/smithy-validation.

///|
/// Search `input` from its start, spending at most `work` units. Returns
/// whether the search matched and the units it spent, or `None` when it needs
/// more than `work` units. A search that stops keeps no partial state.
pub fn Regex::matches(
  self : Regex,
  input : StringView,
  work~ : Int32,
) -> (Bool, Int32)? {
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

// Added for moonrockz/smithy-validation.

///|
/// The work units that one match may still spend. A unit is one visit of an
/// expression node or a thread while the automaton builds a state, one table
/// cell that the automaton allocates or copies, or one input code unit.
pub struct Meter {
  mut left : Int32
}

///|
/// Raised when a match needs more units than its meter has left.
pub suberror Exhausted

///|
pub fn Meter::new(work : Int32) -> Meter {
  { left: work, }
}

///|
/// A meter that never runs out, as the upstream engine behaves.
pub fn Meter::unlimited() -> Meter {
  { left: 0x7fffffff, }
}

///|
pub fn Meter::left(self : Meter) -> Int32 {
  self.left
}

///|
/// Spend `units`, or raise `Exhausted` and spend nothing when too few are left.
pub fn Meter::spend(self : Meter, units : Int32) -> Unit raise Exhausted {
  if units > self.left {
    raise Exhausted
  }
  self.left -= units
}

///|
/// Spend `units` from the meter of the running match.
pub fn Context::spend(self : Context, units : Int32) -> Unit raise Exhausted {
  self.meter.spend(units)
}

///|
/// Run the next matches against `meter`.
pub fn Context::meter(self : Context, meter : Meter) -> Unit {
  self.meter = meter
}

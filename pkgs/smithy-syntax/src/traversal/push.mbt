///|
/// Callbacks for `push_events`. `on_enter` steers the run with its
/// `Control`; both methods have defaults (`Continue` and nothing), so a
/// handler implements only what it needs.
pub(open) trait Handler {
  fn on_enter(Self, EnterEvent) -> Control = _
  fn on_leave(Self, LeaveEvent) -> Unit = _
}

///|
impl Handler with fn on_enter(_self, _event) {
  Continue
}

///|
impl Handler with fn on_leave(_self, _event) {
  ()
}

///|
/// Read every event of `source` and call `handler`: `on_enter` for an
/// `Enter` (`SkipChildren` calls `source.skip_children()`, `Stop` ends the
/// run) and `on_leave` for a `Leave`.
/// A handler is a type of yours with `impl Handler` for the methods it needs.
pub fn[S : EventSource, H : Handler] push_events(
  source : S,
  handler : H,
) -> Unit {
  while source.next() is Some(event) {
    match event {
      Enter(e) =>
        match handler.on_enter(e) {
          Continue => ()
          SkipChildren => source.skip_children()
          Stop => return
        }
      Leave(e) => handler.on_leave(e)
    }
  }
}

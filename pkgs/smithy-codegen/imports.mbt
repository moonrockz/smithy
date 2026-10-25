///|
/// The tracker of imports and dependencies. All writers of one file share it
/// by reference. Task 6 gives it its fields.
#warnings("-unused_field")
priv struct ImportTracker {
  mut count : Int32
}

///|
fn ImportTracker::new() -> ImportTracker {
  { count: 0, }
}

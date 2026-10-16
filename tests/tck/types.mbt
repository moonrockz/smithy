///|
pub(all) enum CaseKind {
  Valid
  Invalid(line~ : Int32, column~ : Int32, message~ : String)
  Recovery
} derive(Eq, Debug)

///|
pub(all) struct Case {
  path : String
  kind : CaseKind
  text : String
} derive(Debug)

///|
/// A vendored reference JSON model, embedded so compatibility checks need no
/// network or file system.
pub(all) struct JsonCase {
  path : String
  text : String
} derive(Debug)

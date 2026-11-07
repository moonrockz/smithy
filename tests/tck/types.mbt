///|
#derive(Eq, Debug)
pub(all) enum CaseKind {
  Valid
  Invalid(line~ : Int32, column~ : Int32, message~ : String)
  Recovery
}

///|
#derive(Debug)
pub(all) struct Case {
  path : String
  kind : CaseKind
  text : String
}

///|
/// A vendored reference JSON model, embedded so compatibility checks need no
/// network or file system.
#derive(Debug)
pub(all) struct JsonCase {
  path : String
  text : String
}

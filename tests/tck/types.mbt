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

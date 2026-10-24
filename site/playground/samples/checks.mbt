///|
/// What a value check does with a member that the shape does not have: the CLI
/// option `--unknown-members`.
pub(all) enum UnknownMembers {
  Reject
  Ignore
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend UnknownMembers with Eq::{equal, not_equal}

///|
pub extend UnknownMembers with @debug.Debug::{to_repr}

///|
pub extend UnknownMembers with ToJson::{to_json}

///|
pub extend UnknownMembers with FromJson::{from_json}

///|
/// The member names that a value check reads: the CLI option `--member-names`.
/// `JsonName` reads the name of the `jsonName` trait where a member has one.
pub(all) enum MemberNames {
  Smithy
  JsonName
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend MemberNames with Eq::{equal, not_equal}

///|
pub extend MemberNames with @debug.Debug::{to_repr}

///|
pub extend MemberNames with ToJson::{to_json}

///|
pub extend MemberNames with FromJson::{from_json}

///|
/// The options of a value check, as the CLI options of `smithy validate value`.
pub(all) struct ValueOptions {
  unknown_members : UnknownMembers
  member_names : MemberNames
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend ValueOptions with Eq::{equal, not_equal}

///|
pub extend ValueOptions with @debug.Debug::{to_repr}

///|
pub extend ValueOptions with ToJson::{to_json}

///|
pub extend ValueOptions with FromJson::{from_json}

///|
/// The defaults of the CLI: `--unknown-members reject`, `--member-names smithy`.
pub fn ValueOptions::default() -> ValueOptions {
  { unknown_members: Reject, member_names: Smithy, }
}

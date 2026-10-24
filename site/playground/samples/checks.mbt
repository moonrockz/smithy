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

///|
/// The JSON-RPC version of a message check: the CLI option `--version`.
pub(all) enum RpcVersion {
  V1_0
  V2_0
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend RpcVersion with Eq::{equal, not_equal}

///|
pub extend RpcVersion with @debug.Debug::{to_repr}

///|
pub extend RpcVersion with ToJson::{to_json}

///|
pub extend RpcVersion with FromJson::{from_json}

///|
/// What a response check knows of the call that the response answers: the CLI
/// options `--envelope-only`, `--method`, `--operation` and `--request`.
/// `OriginalRequest` holds the text of the request, not a file name.
pub(all) enum ResponseContext {
  EnvelopeOnly
  Method(String)
  Operation(String)
  OriginalRequest(String)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend ResponseContext with Eq::{equal, not_equal}

///|
pub extend ResponseContext with @debug.Debug::{to_repr}

///|
pub extend ResponseContext with ToJson::{to_json}

///|
pub extend ResponseContext with FromJson::{from_json}

///|
/// How a response check reads a JSON-RPC 1.0 error: the CLI option
/// `--legacy-errors`. `CodeMessageData` applies only to JSON-RPC 1.0.
pub(all) enum LegacyErrors {
  Opaque
  CodeMessageData
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LegacyErrors with Eq::{equal, not_equal}

///|
pub extend LegacyErrors with @debug.Debug::{to_repr}

///|
pub extend LegacyErrors with ToJson::{to_json}

///|
pub extend LegacyErrors with FromJson::{from_json}

///|
/// The kind of the message of a message check.
pub(all) enum MessageKind {
  /// --message: a request or a notification.
  RequestMessage
  /// --response, with the context options of the CLI.
  ResponseMessage(context~ : ResponseContext?, legacy_errors~ : LegacyErrors)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend MessageKind with Eq::{equal, not_equal}

///|
pub extend MessageKind with @debug.Debug::{to_repr}

///|
pub extend MessageKind with ToJson::{to_json}

///|
pub extend MessageKind with FromJson::{from_json}

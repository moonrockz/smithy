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
/// `profile` is the option `--profile`: a declared serialization profile of the
/// target, which the check then reads with the JSON codec. It is `None` for the
/// plain value check.
pub(all) struct ValueOptions {
  unknown_members : UnknownMembers
  member_names : MemberNames
  profile : String?
} derive(Eq, Debug)

///|
pub extend ValueOptions with Eq::{equal, not_equal}

///|
pub extend ValueOptions with @debug.Debug::{to_repr}

///|
/// The JSON of the options. Without a profile it is the JSON of the two plain
/// options alone, as before profiles existed.
pub impl ToJson for ValueOptions with fn to_json(self) {
  let fields : Map[String, Json] = {
    "unknown_members": self.unknown_members.to_json(),
    "member_names": self.member_names.to_json(),
  }
  if self.profile is Some(profile) {
    fields["profile"] = Json::string(profile)
  }
  Json::object(fields)
}

///|
pub impl FromJson for ValueOptions with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise @json.JsonDecodeError((path, "expected an object of value options"))
  }
  let unknown_members : UnknownMembers = match fields.get("unknown_members") {
    Some(value) => FromJson::from_json(value, path.add_key("unknown_members"))
    None =>
      raise @json.JsonDecodeError((path, "expected the field unknown_members"))
  }
  let member_names : MemberNames = match fields.get("member_names") {
    Some(value) => FromJson::from_json(value, path.add_key("member_names"))
    None =>
      raise @json.JsonDecodeError((path, "expected the field member_names"))
  }
  let profile = match fields.get("profile") {
    None | Some(Null) => None
    Some(String(text)) => Some(text)
    Some(_) =>
      raise @json.JsonDecodeError(
        (path.add_key("profile"), "expected a profile identifier"),
      )
  }
  { unknown_members, member_names, profile, }
}

///|
/// The defaults of the CLI: `--unknown-members reject`, `--member-names smithy`,
/// no `--profile`.
pub fn ValueOptions::default() -> ValueOptions {
  { unknown_members: Reject, member_names: Smithy, profile: None, }
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
/// `--legacy-errors`. The option applies only to JSON-RPC 1.0.
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
  /// --response, with the context options of the CLI. `legacy_errors` is
  /// `None` when the option is absent; the check then reads a 1.0 error as
  /// `Opaque`. The CLI rejects the option, with any value, for JSON-RPC 2.0.
  ResponseMessage(context~ : ResponseContext?, legacy_errors~ : LegacyErrors?)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend MessageKind with Eq::{equal, not_equal}

///|
pub extend MessageKind with @debug.Debug::{to_repr}

///|
pub extend MessageKind with ToJson::{to_json}

///|
pub extend MessageKind with FromJson::{from_json}

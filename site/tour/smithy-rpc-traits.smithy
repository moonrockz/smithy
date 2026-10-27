$version: "2"
namespace smithy.rpc
@trait(selector: "service")
structure jsonRpc {
  @required versions: Versions
  undeclaredServerErrors: UndeclaredServerErrors
}
enum UndeclaredServerErrors {
  ACCEPT = "accept"
  ADVISORY = "advisory"
  ERROR = "error"
}
@length(min: 1)
list Versions { member: Version }
enum Version {
  V1 = "1.0"
  V2 = "2.0"
}
@trait(selector: "operation")
structure method {
  @required name: MethodName
  @required params: ParameterMode
  positional: MemberOrder
  resultMember: String
  nullResult: Boolean
  kind: MethodKind
}
enum MethodKind {
  REQUEST = "request"
  NOTIFICATION = "notification"
  EITHER = "either"
}
@trait(selector: ":is(service, structure)")
enum unknownMembers {
  REJECT = "reject"
  IGNORE = "ignore"
}
@trait(selector: "structure > member")
structure criticalPaths { @required separator: String }
@length(min: 1)
string MethodName
enum ParameterMode {
  NAMED = "named"
  POSITIONAL = "positional"
  EITHER = "either"
}
list MemberOrder { member: String }
@trait(selector: "structure[trait|error]")
structure rpcError { @required code: Integer, dataMember: String, absentData: Boolean }
@trait(selector: "structure")
structure jsonRpcProtocol { @required versions: Versions, @required peers: Peers }
@length(min: 2, max: 2)
list Peers { member: Peer }
structure Peer { @required name: PeerName, accepts: ServiceRef }
@pattern("^[A-Za-z][A-Za-z0-9_-]{0,63}$")
string PeerName
@idRef(failWhenMissing: true, selector: "service")
string ServiceRef
@trait(selector: "structure [trait|smithy.rpc#jsonRpcProtocol]")
structure jsonRpcSession {
  @required states: StateNames
  capabilities: CapabilitySources
  refusals: Refusals
  capabilityRefusal: Integer
}
list Refusals { member: Refusal }
structure Refusal { @required states: StateNames, @required code: Integer }
@length(min: 1)
list StateNames { member: StateName }
@pattern("^[A-Za-z][A-Za-z0-9_-]{0,63}$")
string StateName
list CapabilitySources { member: CapabilitySource }
structure CapabilitySource {
  @required name: String
  @required method: MethodName
  @required pointer: String
}
@trait(selector: "operation")
structure jsonRpcLifecycle {
  allowedIn: StateNames
  onCall: StateName
  onSuccess: StateName
  onError: StateName
  requires: CapabilityNames
}
list CapabilityNames { member: String }
@trait(selector: "operation")
structure jsonRpcCancels {
  @required idMember: String
  code: Integer
}
@trait(selector: "operation")
structure jsonRpcRefersToCall { @required idMember: String }
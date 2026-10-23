///|
/// Opt in to the JSON-RPC trait model. Ordinary Smithy/JSON consumers do not
/// depend on this package. Use this loader for IDL or JSON AST API definitions.
/// The trait definitions are a built-in source named `<smithy-rpc-traits>`, so
/// an exported model omits them, as it omits the prelude. With protocol_tests,
/// the loader also adds the Smithy protocol test traits.
pub fn loader(protocol_tests~ : Bool = false) -> @smithy.Loader {
  @smithy.Loader::new(protocol_tests~).add_builtin_idl(
    "<smithy-rpc-traits>",
    trait_definitions(),
  )
}

///|
/// The source can also be supplied to an existing Loader or saved as a model file.
pub fn trait_definitions() -> String {
  (
    #|$version: "2"
    #|namespace smithy.rpc
    #|@trait(selector: "service")
    #|structure jsonRpc { @required versions: Versions }
    #|@length(min: 1)
    #|list Versions { member: Version }
    #|enum Version {
    #|  V1 = "1.0"
    #|  V2 = "2.0"
    #|}
    #|@trait(selector: "operation")
    #|structure method {
    #|  @required name: MethodName
    #|  @required params: ParameterMode
    #|  positional: MemberOrder
    #|  resultMember: String
    #|  nullResult: Boolean
    #|}
    #|@length(min: 1)
    #|string MethodName
    #|enum ParameterMode {
    #|  NAMED = "named"
    #|  POSITIONAL = "positional"
    #|  EITHER = "either"
    #|}
    #|list MemberOrder { member: String }
    #|@trait(selector: "structure[trait|error]")
    #|structure rpcError { @required code: Integer, dataMember: String, absentData: Boolean }
    #|@trait(selector: "structure")
    #|structure jsonRpcProtocol { @required versions: Versions, @required peers: Peers }
    #|@length(min: 2, max: 2)
    #|list Peers { member: Peer }
    #|structure Peer { @required name: PeerName, accepts: ServiceRef }
    #|@pattern("^[A-Za-z][A-Za-z0-9_-]{0,63}$")
    #|string PeerName
    #|@idRef(failWhenMissing: true, selector: "service")
    #|string ServiceRef
    #|@trait(selector: "structure [trait|smithy.rpc#jsonRpcProtocol]")
    #|structure jsonRpcSession {
    #|  @required states: StateNames
    #|  capabilities: CapabilitySources
    #|}
    #|@length(min: 1)
    #|list StateNames { member: StateName }
    #|@pattern("^[A-Za-z][A-Za-z0-9_-]{0,63}$")
    #|string StateName
    #|list CapabilitySources { member: CapabilitySource }
    #|structure CapabilitySource {
    #|  @required name: String
    #|  @required method: MethodName
    #|  @required pointer: String
    #|}
    #|@trait(selector: "operation")
    #|structure jsonRpcLifecycle {
    #|  allowedIn: StateNames
    #|  onCall: StateName
    #|  onSuccess: StateName
    #|  onError: StateName
    #|  requires: CapabilityNames
    #|}
    #|list CapabilityNames { member: String }
    #|@trait(selector: "operation")
    #|structure jsonRpcCancels {
    #|  @required idMember: String
    #|  code: Integer
    #|}
  )
}

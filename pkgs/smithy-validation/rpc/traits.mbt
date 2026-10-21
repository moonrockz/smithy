///|
/// Opt in to the JSON-RPC trait model. Ordinary Smithy/JSON consumers do not
/// depend on this package. Use this loader for IDL or JSON AST API definitions.
pub fn loader() -> @smithy.Loader {
  @smithy.Loader::new().add_idl("<smithy-rpc-traits>", trait_definitions())
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
  )
}

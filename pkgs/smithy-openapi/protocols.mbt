///|
/// Trait definitions required by the bundled protocol converters. Callers that
/// already load these definitions from model dependencies can use those instead.
/// The inputs are ordinary provider models; this function performs no I/O.
pub fn protocol_definitions() -> Array[@smithy.ModelInput] {
  [
    @smithy.Idl(
      name="<openapi-rest-json-protocol>",
      text=(
        #|$version: "2.0"
        #|namespace aws.protocols
        #|@protocolDefinition(traits: [timestampFormat, cors, endpoint, hostLabel, http, httpError, httpHeader, httpLabel, httpPayload, httpPrefixHeaders, httpQuery, httpQueryParams, httpResponseCode, httpChecksumRequired, jsonName])
        #|@trait(selector: "service")
        #|structure restJson1 {
        #|    http: StringList
        #|    eventStreamHttp: StringList
        #|}
        #|@private
        #|list StringList { member: String }
      ),
    ),
    @smithy.Idl(
      name="<openapi-rpc-json-protocol>",
      text=(
        #|$version: "2.0"
        #|namespace smithy.protocols
        #|@trait(selector: "service")
        #|@protocolDefinition(traits: [cors, endpoint, hostLabel, httpError, requestCompression])
        #|structure rpcv2Json {
        #|    http: StringList
        #|    eventStreamHttp: StringList
        #|}
        #|@private
        #|list StringList { member: String }
      ),
    ),
  ]
}

$version: "2"
namespace servererrors

use smithy.rpc#jsonRpc
use smithy.rpc#method
use smithy.rpc#rpcError

@jsonRpc(versions: ["2.0"], undeclaredServerErrors: "advisory")
service Api {
    version: "1"
    operations: [Initialize]
    errors: [VersionMismatch]
}

@method(name: "initialize", params: "named")
operation Initialize {}

@error("client")
@rpcError(code: -32011)
structure VersionMismatch {
    @required
    hostVersions: Versions
    @required
    extensionVersions: Versions
}

map Versions {
    key: String
    value: String
}

$version: "2"

namespace example.rpcunit

use smithy.protocols#rpcv2Json

@rpcv2Json
service Units {
    version: "2024-01-01"
    operations: [Ping, Push, Pull]
}

operation Ping {
    errors: [Problem]
}

operation Push {
    input := {
        value: String
    }
}

operation Pull {
    output := {
        value: String
    }
}

@error("client")
structure Problem {
    message: String
}

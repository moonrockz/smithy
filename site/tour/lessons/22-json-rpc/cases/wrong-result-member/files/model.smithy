$version: "2"

namespace example

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#method
use smithy.rpc#rpcError

/// A weather server that a client calls with JSON-RPC 2.0.
@jsonRpc(versions: ["2.0"])
service WeatherApi {
    version: "2024-01-01"
    operations: [GetForecast]
}

/// The client receives alerts from the server.
@jsonRpc(versions: ["2.0"])
service WeatherClient {
    version: "2024-01-01"
    operations: [Alert]
}

/// The two peers of the weather protocol.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "client", accepts: WeatherClient }
        { name: "server", accepts: WeatherApi }
    ]
)
structure WeatherProtocol {}

@method(name: "weather/forecast", params: "named", resultMember: "rain")
operation GetForecast {
    input := {
        @required
        cityId: String
    }

    output := {
        @required
        chanceOfRain: Float
    }

    errors: [CityNotFound]
}

@method(name: "weather/alert", params: "named", nullResult: true)
operation Alert {
    input := {
        @required
        text: String
    }
}

@error("client")
@rpcError(code: 1001)
structure CityNotFound {
    message: String
}

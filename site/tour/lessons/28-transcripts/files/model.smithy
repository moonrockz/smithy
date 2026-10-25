$version: "2"
namespace example

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#method

/// The two peers of the weather protocol.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "client", accepts: WeatherClient }
        { name: "server", accepts: WeatherApi }
    ]
)
structure WeatherProtocol {}

/// The server answers forecast calls.
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

@method(name: "weather/forecast", params: "named", resultMember: "chanceOfRain")
operation GetForecast {
    input := {
        @required
        cityId: String
    }
    output := {
        @required
        chanceOfRain: Float
    }
}

@method(name: "weather/alert", params: "named", nullResult: true)
operation Alert {
    input := {
        @required
        text: String
    }
}

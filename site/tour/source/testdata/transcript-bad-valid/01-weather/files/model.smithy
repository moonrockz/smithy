$version: "2"
namespace example

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#method

@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "client", accepts: WeatherClient }
        { name: "server", accepts: WeatherServer }
    ]
)
structure WeatherProtocol {}

@jsonRpc(versions: ["2.0"])
service WeatherServer {
    version: "1"
    operations: [GetWeather]
}

@jsonRpc(versions: ["2.0"])
service WeatherClient {
    version: "1"
    operations: [Alert]
}

@method(name: "weather/get", params: "named", resultMember: "forecast")
operation GetWeather { input: GetWeatherInput, output: GetWeatherOutput }

structure GetWeatherInput { @required city: String }

structure GetWeatherOutput { forecast: String }

@method(name: "weather/alert", params: "named", nullResult: true)
operation Alert { input: AlertInput }

structure AlertInput { text: String }

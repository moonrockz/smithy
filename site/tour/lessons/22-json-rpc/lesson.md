# JSON-RPC services

> **Our extension:** The `smithy.rpc` traits and the OpenRPC output are features of this project. Standard Smithy does not have them. Read about the [OpenRPC converter](../../../../pkgs/smithy-openrpc/README.mbt.md).

The service trait `@jsonRpc` declares the JSON-RPC versions that the service supports. Each operation of the service needs the trait `@method`. It gives the method name on the wire and the parameter mode: `named`, `positional` or `either`. `resultMember` selects one member of the output as the result. Each error of an operation needs the trait `@rpcError` with an integer code.

The trait `@jsonRpcProtocol` names two peers. A peer can accept the calls of one service. Here the server accepts `WeatherApi`, and the client accepts `WeatherClient`.

Look at the output tab. It shows the OpenRPC 1.3.2 document of `WeatherApi`, the first JSON-RPC 2.0 service by shape ID. The method `weather/forecast` has the error code `1001`.

The model check finds errors in the value of each [trait](../14-defining-traits/lesson.md). The tools check the other JSON-RPC rules when they prepare the service. Make these changes one at a time. Change the model back after each change.

- Delete the line `@method(name: "weather/forecast", …)`. The Findings tab shows no error and no warning. The output tab says that `example#GetForecast` needs a nonempty method name.
- Change `resultMember: "chanceOfRain"` to `resultMember: "rain"`. The Findings tab shows no error and no warning. The output tab says that `resultMember` must name a declared output member.
- Delete the line `{ name: "client", accepts: WeatherClient }`. `@jsonRpcProtocol` needs two peers, so the Findings tab shows an error with the event ID `TraitValue` on `example#WeatherProtocol`.
- Move the block of the service `WeatherClient` above `WeatherApi`. The output still shows `WeatherApi`. The order in the file does not change the order of the shape IDs.

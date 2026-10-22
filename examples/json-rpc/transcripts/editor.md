---
version: "2.0"
complete: true
---
# Editor

The same transcript as `editor.json`. The client initializes the server, the server
calls the client back for its configuration, and the client asks for hover text and
then shuts the server down.

```jsonrpc client -> server
{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"processId": 42}}
```

```jsonrpc server -> client
{"jsonrpc": "2.0", "id": 1, "result": "full"}
```

The server calls the client back.

```jsonrpc server -> client
{"jsonrpc": "2.0", "id": 1, "method": "workspace/configuration", "params": {"section": "editor"}}
```

```jsonrpc client -> server
{"jsonrpc": "2.0", "id": 1, "result": ["tabs"]}
```

```jsonrpc client -> server
{"jsonrpc": "2.0", "id": 2, "method": "textDocument/hover", "params": {"uri": "file:///a.txt", "line": 1, "character": 2}}
```

```jsonrpc server -> client
{"jsonrpc": "2.0", "id": 2, "result": "docs"}
```

```jsonrpc client -> server
{"jsonrpc": "2.0", "id": 3, "method": "shutdown"}
```

```jsonrpc server -> client
{"jsonrpc": "2.0", "id": 3, "result": null}
```

```jsonrpc client -> server
{"jsonrpc": "2.0", "method": "exit"}
```

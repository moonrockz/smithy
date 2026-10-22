---
version: "1.0"
complete: true
---
# Echo

JSON-RPC 1.0 section 4: the client calls `echo` and the server replies.

```jsonrpc client -> server
{"method": "echo", "params": ["Hello JSON-RPC"], "id": 1}
```

```jsonrpc server -> client
{"result": "Hello JSON-RPC", "error": null, "id": 1}
```

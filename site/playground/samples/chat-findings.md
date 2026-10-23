---
version: 1.0
complete: true
---
# Chat

The client posts a message. The server calls the
client back and then replies.

```jsonrpc client -> server
{"method": "postMessage", "params": ["Hello all!"], "id": 99}
```

```jsonrpc server -> client
{"method": "handleMessage", "params": ["user1", "I'm in!"], "id": null}
```

```jsonrpc server
{"result": "one", "error": null, "id": 99}
```

```jsonrpc client -> server
{"method": "echo", "params": [], "id": 100}
```

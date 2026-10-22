---
version: 1.0
complete: true
---
# Chat

The client posts a message. The server calls the client back and then replies.
A call with a null id is a notification in 1.0.

```jsonrpc client -> server
{"method": "postMessage", "params": ["Hello all!"], "id": 99}
```

```jsonrpc server -> client
{"method": "handleMessage", "params": ["user1", "I'm in!"], "id": null}
```

```jsonrpc server
{"result": 1, "error": null, "id": 99}
```

```jsonrpc server -> client
{"method": "userLeft", "params": ["user3"], "id": null}
```

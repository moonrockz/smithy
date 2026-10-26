# moonrockz/smithy-codegen-python

A Smithy code generator for Python JSON-RPC 2.0 peers. Register it in the build runner as
`python-jsonrpc-codegen`. One run generates one peer of a protocol.

```json
{
  "version": "1.0",
  "plugins": {
    "python-jsonrpc-codegen::python-terminal": {
      "service": "example.payments#PaymentTerminal",
      "protocol": "example.payments#TerminalProtocol",
      "peer": "terminal",
      "package": "payment_terminal",
      "integrations": ["fastapi"]
    }
  }
}
```

## Settings

- `service`, `protocol`, `peer` and `transports`: the shared settings of the JSON-RPC plugins
  (`PeerSettings` in `moonrockz/smithy-codegen-jsonrpc`).
- `package` (required): the Python package name of the output, such as `payment_terminal`.
- `integrations` (optional): `["fastapi"]` adds FastAPI and uvicorn to the dependencies.

## Output

| File | Content |
| --- | --- |
| `pyproject.toml` | The project, with exact versions of the dependencies and the checks (pyright strict, ruff, pytest). |
| `<package>/models.py` | A frozen Pydantic v2 model for each structure, a model for each union member and a tagged type alias for each union, a `StrEnum` or `IntEnum` for each enum. Fields are `snake_case`; the wire names are the aliases. |
| `<package>/errors.py` | For each modeled error: a data model `<Name>Data` and an exception `<Name>` with `to_rpc_error()` and `from_data(data)`. |
| `<package>/handler.py` | A `Protocol` with one method for each method that the peer accepts, and `register_<service>(peer, handler)`. The cancel method has no handler: the runtime cancels the call. |
| `<package>/client.py` | A typed client of the service that the peer calls. Each call has `checked: bool = True`. |
| `<package>/session.py` | `session_rules()` from the prepared session contract, and `new_peer(log=None)`. |
| `<package>/_runtime/` | A copy of `runtimes/python/smithy_jsonrpc_runtime`. |
| `tests/test_generated.py` | A check of the session rules, the peer and one model. |

Exact values: a `bigDecimal` is a `Decimal` (`BigDecimal`), an integer of any size is an `int`
(`BigInteger`), a blob is `bytes` (base64 on the wire). A number never goes through `float`.

The generator does not interpret the RPC traits again. It renders the prepared contracts of
`moonrockz/smithy-validation/rpc`, so the generated peers and `smithy validate rpc transcript`
agree.

`mise run runtime:embed` copies the runtime into `runtime_files.mbt`. `mise run validate` checks
that the copy is current.

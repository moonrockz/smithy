"""Errors of the runtime and the standard JSON-RPC 2.0 error codes."""

from __future__ import annotations

from collections.abc import Callable, Mapping
from typing import TYPE_CHECKING, ClassVar

if TYPE_CHECKING:
    from .json_codec import JsonValue

PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603
REQUEST_CANCELLED = -32800
"""The default code of a cancelled call, when the model gives no code."""


class DecodeError(Exception):
    """A JSON value does not match the type that the code expects.

    `path` is a JSON Pointer to the value, relative to the decoded value. The
    dispatcher answers a call with -32602 when its handler raises this error.
    """

    def __init__(self, *, path: str, message: str) -> None:
        super().__init__(f"{message} (at {path or '/'})" if path else message)
        self.path = path
        self.message = message


class RpcError(Exception):
    """A JSON-RPC error object: a code, a message and optional data.

    A handler raises it to answer with this error. `Peer.request` raises it when
    the remote peer answers with an error, or when the local session check
    refuses the call. `data` is None when the error object has no data member.
    """

    def __init__(self, code: int, message: str, data: JsonValue | None = None) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message
        self.data = data

    def to_json(self) -> dict[str, JsonValue]:
        """Give the JSON-RPC error object."""
        error: dict[str, JsonValue] = {"code": self.code, "message": self.message}
        if self.data is not None:
            error["data"] = self.data
        return error


class ModeledError(Exception):
    """The base of the generated exception classes of modeled errors.

    A subclass sets `code` and implements `to_rpc_error`. A handler raises a
    subclass; the generated dispatcher sends `to_rpc_error()`.
    """

    code: ClassVar[int] = INTERNAL_ERROR

    def to_rpc_error(self) -> RpcError:
        """Give the JSON-RPC error with the modeled code, message and data."""
        return RpcError(self.code, str(self))


def modeled_error(
    error: RpcError, decoders: Mapping[int, Callable[[JsonValue | None], ModeledError]]
) -> Exception:
    """Give the modeled error of an error response, or the error itself.

    When the decoder of the code cannot read the data, I give the `RpcError`.
    """
    decoder = decoders.get(error.code)
    if decoder is None:
        return error
    try:
        return decoder(error.data)
    except (DecodeError, ValueError):
        return error

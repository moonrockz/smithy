"""An asyncio JSON-RPC 2.0 runtime for the peers that the Smithy Python generator makes.

The generator copies this package into the generated package as `_runtime`.
Every import in it is relative, so the copy works under any package name.
"""

from . import json_codec
from .connection import Connection, MemoryConnection, memory_pair
from .errors import (
    INTERNAL_ERROR,
    INVALID_PARAMS,
    INVALID_REQUEST,
    METHOD_NOT_FOUND,
    PARSE_ERROR,
    REQUEST_CANCELLED,
    DecodeError,
    RpcError,
)
from .ids import RequestId
from .json_codec import JsonObject, JsonValue
from .log import TranscriptLog
from .params import named_params, positional_params, to_positional
from .peer import CallContext, MethodKind, NotificationHandler, Peer, RequestHandler
from .session import CancelRule, CapabilitySource, MethodRule, Refusal, Session, SessionRules
from .stdio import (
    FramingError,
    ProcessConnection,
    StdioConnection,
    StreamConnection,
    spawn_stdio,
    stdio_connection,
)
from .values import (
    BigDecimal,
    BigInteger,
    Blob,
    DateTimeTimestamp,
    EpochSecondsTimestamp,
    HttpDateTimestamp,
    Timestamp,
    TimestampFormat,
    decode_blob,
    decode_decimal,
    decode_integer,
    encode_blob,
    to_wire,
)

__all__ = [
    "INTERNAL_ERROR",
    "INVALID_PARAMS",
    "INVALID_REQUEST",
    "METHOD_NOT_FOUND",
    "PARSE_ERROR",
    "REQUEST_CANCELLED",
    "BigDecimal",
    "BigInteger",
    "Blob",
    "CallContext",
    "CancelRule",
    "CapabilitySource",
    "Connection",
    "DateTimeTimestamp",
    "DecodeError",
    "EpochSecondsTimestamp",
    "FramingError",
    "HttpDateTimestamp",
    "JsonObject",
    "JsonValue",
    "MemoryConnection",
    "MethodKind",
    "MethodRule",
    "NotificationHandler",
    "Peer",
    "ProcessConnection",
    "Refusal",
    "RequestHandler",
    "RequestId",
    "RpcError",
    "Session",
    "SessionRules",
    "StdioConnection",
    "StreamConnection",
    "Timestamp",
    "TimestampFormat",
    "TranscriptLog",
    "decode_blob",
    "decode_decimal",
    "decode_integer",
    "encode_blob",
    "json_codec",
    "memory_pair",
    "named_params",
    "positional_params",
    "spawn_stdio",
    "stdio_connection",
    "to_positional",
    "to_wire",
]

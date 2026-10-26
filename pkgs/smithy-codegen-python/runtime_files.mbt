///|
/// The source files of the Python JSON-RPC runtime, from `runtimes/python/smithy_jsonrpc_runtime`.
/// `mise run runtime:embed` writes this file; do not edit it.
let runtime_files : Array[(String, String)] = [
  (
    "__init__.py",
    (
      #|"""An asyncio JSON-RPC 2.0 runtime for the peers that the Smithy Python generator makes.
      #|
      #|The generator copies this package into the generated package as `_runtime`.
      #|Every import in it is relative, so the copy works under any package name.
      #|"""
      #|
      #|from . import json_codec
      #|from .connection import Connection, MemoryConnection, memory_pair
      #|from .errors import (
      #|    INTERNAL_ERROR,
      #|    INVALID_PARAMS,
      #|    INVALID_REQUEST,
      #|    METHOD_NOT_FOUND,
      #|    PARSE_ERROR,
      #|    REQUEST_CANCELLED,
      #|    DecodeError,
      #|    ModeledError,
      #|    RpcError,
      #|    modeled_error,
      #|)
      #|from .ids import RequestId
      #|from .json_codec import JsonObject, JsonValue
      #|from .log import TranscriptLog
      #|from .params import named_params, positional_params, to_positional
      #|from .peer import CallContext, MethodKind, NotificationHandler, Peer, RequestHandler
      #|from .session import CancelRule, CapabilitySource, MethodRule, Refusal, Session, SessionRules
      #|from .stdio import (
      #|    FramingError,
      #|    ProcessConnection,
      #|    StdioConnection,
      #|    StreamConnection,
      #|    spawn_stdio,
      #|    stdio_connection,
      #|)
      #|from .values import (
      #|    BigDecimal,
      #|    BigInteger,
      #|    Blob,
      #|    Byte,
      #|    DateTimeTimestamp,
      #|    Document,
      #|    Double,
      #|    EpochSecondsTimestamp,
      #|    HttpDateTimestamp,
      #|    Integer,
      #|    Long,
      #|    Short,
      #|    Timestamp,
      #|    TimestampFormat,
      #|    Unit,
      #|    check_document,
      #|    decode_blob,
      #|    decode_decimal,
      #|    decode_double,
      #|    decode_integer,
      #|    encode_blob,
      #|    encode_double,
      #|    to_wire,
      #|    to_wire_object,
      #|    union_tag,
      #|)
      #|
      #|__all__ = [
      #|    "INTERNAL_ERROR",
      #|    "INVALID_PARAMS",
      #|    "INVALID_REQUEST",
      #|    "METHOD_NOT_FOUND",
      #|    "PARSE_ERROR",
      #|    "REQUEST_CANCELLED",
      #|    "BigDecimal",
      #|    "BigInteger",
      #|    "Blob",
      #|    "Byte",
      #|    "CallContext",
      #|    "CancelRule",
      #|    "CapabilitySource",
      #|    "Connection",
      #|    "DateTimeTimestamp",
      #|    "DecodeError",
      #|    "Document",
      #|    "Double",
      #|    "EpochSecondsTimestamp",
      #|    "FramingError",
      #|    "HttpDateTimestamp",
      #|    "Integer",
      #|    "JsonObject",
      #|    "JsonValue",
      #|    "Long",
      #|    "MemoryConnection",
      #|    "MethodKind",
      #|    "MethodRule",
      #|    "ModeledError",
      #|    "NotificationHandler",
      #|    "Peer",
      #|    "ProcessConnection",
      #|    "Refusal",
      #|    "RequestHandler",
      #|    "RequestId",
      #|    "RpcError",
      #|    "Session",
      #|    "SessionRules",
      #|    "Short",
      #|    "StdioConnection",
      #|    "StreamConnection",
      #|    "Timestamp",
      #|    "TimestampFormat",
      #|    "TranscriptLog",
      #|    "Unit",
      #|    "check_document",
      #|    "decode_blob",
      #|    "decode_decimal",
      #|    "decode_double",
      #|    "decode_integer",
      #|    "encode_blob",
      #|    "encode_double",
      #|    "json_codec",
      #|    "memory_pair",
      #|    "modeled_error",
      #|    "named_params",
      #|    "positional_params",
      #|    "spawn_stdio",
      #|    "stdio_connection",
      #|    "to_positional",
      #|    "to_wire",
      #|    "to_wire_object",
      #|    "union_tag",
      #|]
      #|
    ),
  ),
  (
    "connection.py",
    (
      #|"""The connection contract of a peer, and an in-memory connection pair."""
      #|
      #|from __future__ import annotations
      #|
      #|import asyncio
      #|from typing import Protocol
      #|
      #|from .ids import RequestId
      #|
      #|SESSION_HEADER = "Smithy-Session-Id"
      #|"""The HTTP header that ties the posts of one session together."""
      #|
      #|
      #|class Connection(Protocol):
      #|    """A transport that carries one JSON-RPC message per `send` and `receive`."""
      #|
      #|    async def receive(self) -> str | None:
      #|        """Give the text of the next message, or None when the remote peer closed."""
      #|        ...
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        """Send the text of one message.
      #|
      #|        `related` is the ID of the incoming call that this message belongs to:
      #|        the call that a response answers, or the call whose handler sends a
      #|        callback or a notification. An HTTP server uses it to put the message
      #|        on the stream of that call.
      #|        """
      #|        ...
      #|
      #|    async def close(self) -> None:
      #|        """Close the connection. Later `receive` calls give None."""
      #|        ...
      #|
      #|
      #|class MemoryConnection:
      #|    """One end of an in-memory connection pair, for tests."""
      #|
      #|    def __init__(self, inbox: asyncio.Queue[str | None], outbox: asyncio.Queue[str | None]) -> None:
      #|        self._inbox = inbox
      #|        self._outbox = outbox
      #|        self._closed = False
      #|        self.sent: list[tuple[str, RequestId | None]] = []
      #|
      #|    async def receive(self) -> str | None:
      #|        if self._closed and self._inbox.empty():
      #|            return None
      #|        return await self._inbox.get()
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        if self._closed:
      #|            raise ConnectionError("I cannot send on a closed memory connection.")
      #|        self.sent.append((text, related))
      #|        await self._outbox.put(text)
      #|
      #|    async def close(self) -> None:
      #|        if self._closed:
      #|            return
      #|        self._closed = True
      #|        await self._outbox.put(None)
      #|        await self._inbox.put(None)
      #|
      #|
      #|def memory_pair() -> tuple[MemoryConnection, MemoryConnection]:
      #|    """Give two connected in-memory ends: what one end sends, the other receives."""
      #|    left: asyncio.Queue[str | None] = asyncio.Queue()
      #|    right: asyncio.Queue[str | None] = asyncio.Queue()
      #|    return MemoryConnection(left, right), MemoryConnection(right, left)
      #|
    ),
  ),
  (
    "errors.py",
    (
      #|"""Errors of the runtime and the standard JSON-RPC 2.0 error codes."""
      #|
      #|from __future__ import annotations
      #|
      #|from collections.abc import Callable, Mapping
      #|from typing import TYPE_CHECKING, ClassVar
      #|
      #|if TYPE_CHECKING:
      #|    from .json_codec import JsonValue
      #|
      #|PARSE_ERROR = -32700
      #|INVALID_REQUEST = -32600
      #|METHOD_NOT_FOUND = -32601
      #|INVALID_PARAMS = -32602
      #|INTERNAL_ERROR = -32603
      #|REQUEST_CANCELLED = -32800
      #|"""The default code of a cancelled call, when the model gives no code."""
      #|
      #|
      #|class DecodeError(Exception):
      #|    """A JSON value does not match the type that the code expects.
      #|
      #|    `path` is a JSON Pointer to the value, relative to the decoded value. The
      #|    dispatcher answers a call with -32602 when its handler raises this error.
      #|    """
      #|
      #|    def __init__(self, *, path: str, message: str) -> None:
      #|        super().__init__(f"{message} (at {path or '/'})" if path else message)
      #|        self.path = path
      #|        self.message = message
      #|
      #|
      #|class RpcError(Exception):
      #|    """A JSON-RPC error object: a code, a message and optional data.
      #|
      #|    A handler raises it to answer with this error. `Peer.request` raises it when
      #|    the remote peer answers with an error, or when the local session check
      #|    refuses the call. `data` is None when the error object has no data member.
      #|    """
      #|
      #|    def __init__(self, code: int, message: str, data: JsonValue | None = None) -> None:
      #|        super().__init__(f"{code}: {message}")
      #|        self.code = code
      #|        self.message = message
      #|        self.data = data
      #|
      #|    def to_json(self) -> dict[str, JsonValue]:
      #|        """Give the JSON-RPC error object."""
      #|        error: dict[str, JsonValue] = {"code": self.code, "message": self.message}
      #|        if self.data is not None:
      #|            error["data"] = self.data
      #|        return error
      #|
      #|
      #|class ModeledError(Exception):
      #|    """The base of the generated exception classes of modeled errors.
      #|
      #|    A subclass sets `code` and implements `to_rpc_error`. A handler raises a
      #|    subclass; the generated dispatcher sends `to_rpc_error()`.
      #|    """
      #|
      #|    code: ClassVar[int] = INTERNAL_ERROR
      #|
      #|    def to_rpc_error(self) -> RpcError:
      #|        """Give the JSON-RPC error with the modeled code, message and data."""
      #|        return RpcError(self.code, str(self))
      #|
      #|
      #|def modeled_error(
      #|    error: RpcError, decoders: Mapping[int, Callable[[JsonValue | None], ModeledError]]
      #|) -> Exception:
      #|    """Give the modeled error of an error response, or the error itself.
      #|
      #|    When the decoder of the code cannot read the data, I give the `RpcError`.
      #|    """
      #|    decoder = decoders.get(error.code)
      #|    if decoder is None:
      #|        return error
      #|    try:
      #|        return decoder(error.data)
      #|    except (DecodeError, ValueError):
      #|        return error
      #|
    ),
  ),
  (
    "http_client.py",
    (
      #|"""The HTTP client transport, in the Streamable HTTP style. It needs `httpx`.
      #|
      #|- The client posts each message to the endpoint, such as `http://127.0.0.1:N/rpc`,
      #|  on a new connection. It posts the next message only after the response
      #|  headers of the last post arrive, so the server receives the messages in order.
      #|- The server answers a request with `text/event-stream`: each event carries one
      #|  message. The stream ends after the response to the request. The client also
      #|  accepts a response as `application/json`.
      #|- The server answers a notification or a response with 202.
      #|- The server sets `Smithy-Session-Id` on its responses. The client sends it on
      #|  each later post.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|import asyncio
      #|import contextlib
      #|import logging
      #|
      #|import httpx
      #|
      #|from .connection import SESSION_HEADER
      #|from .ids import RequestId
      #|
      #|_LOG = logging.getLogger(__name__)
      #|
      #|
      #|class HttpClientConnection:
      #|    """A connection to a JSON-RPC peer at an HTTP endpoint."""
      #|
      #|    def __init__(self, url: str, client: httpx.AsyncClient | None = None) -> None:
      #|        self.url = url
      #|        self.session_id: str | None = None
      #|        self._client = (
      #|            client
      #|            if client is not None
      #|            else httpx.AsyncClient(
      #|                timeout=httpx.Timeout(None, connect=10.0),
      #|                limits=httpx.Limits(max_keepalive_connections=0),
      #|            )
      #|        )
      #|        self._inbox: asyncio.Queue[str | None] = asyncio.Queue()
      #|        self._order = asyncio.Lock()
      #|        self._readers: set[asyncio.Task[None]] = set()
      #|        self._closed = False
      #|
      #|    async def receive(self) -> str | None:
      #|        if self._closed and self._inbox.empty():
      #|            return None
      #|        return await self._inbox.get()
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        async with self._order:
      #|            if self._closed:
      #|                raise ConnectionError(f"I cannot post to {self.url}: the connection is closed.")
      #|            headers = {
      #|                "Content-Type": "application/json",
      #|                "Accept": "application/json, text/event-stream",
      #|            }
      #|            if self.session_id is not None:
      #|                headers[SESSION_HEADER] = self.session_id
      #|            request = self._client.build_request(
      #|                "POST", self.url, content=text.encode("utf-8"), headers=headers
      #|            )
      #|            try:
      #|                response = await self._client.send(request, stream=True)
      #|            except httpx.HTTPError as error:
      #|                raise ConnectionError(f"I could not post to {self.url}: {error}") from error
      #|            found = response.headers.get(SESSION_HEADER)
      #|            if found is not None and self.session_id is None:
      #|                self.session_id = found
      #|            status = response.status_code
      #|            if status == 202:
      #|                await response.aclose()
      #|                return
      #|            if status != 200:
      #|                await response.aclose()
      #|                if status == 404:
      #|                    raise ConnectionError(
      #|                        f"I posted to {self.url} with session {self.session_id}; "
      #|                        "the server does not know the session (404)."
      #|                    )
      #|                raise ConnectionError(
      #|                    f"I expected status 200 or 202 from {self.url}; I received {status}."
      #|                )
      #|            kind = response.headers.get("content-type", "")
      #|            if kind.startswith("text/event-stream"):
      #|                task = asyncio.create_task(self._read_events(response))
      #|                self._readers.add(task)
      #|                task.add_done_callback(self._readers.discard)
      #|                return
      #|            try:
      #|                body = (await response.aread()).decode("utf-8")
      #|            finally:
      #|                await response.aclose()
      #|            if body.strip():
      #|                self._inbox.put_nowait(body)
      #|
      #|    async def _read_events(self, response: httpx.Response) -> None:
      #|        data: list[str] = []
      #|        try:
      #|            async for raw in response.aiter_lines():
      #|                line = raw.rstrip("\r\n")
      #|                if line == "":
      #|                    if data:
      #|                        self._inbox.put_nowait("\n".join(data))
      #|                        data = []
      #|                    continue
      #|                if line.startswith(":"):
      #|                    continue
      #|                name, _, value = line.partition(":")
      #|                if name == "data":
      #|                    data.append(value.removeprefix(" "))
      #|            if data:
      #|                self._inbox.put_nowait("\n".join(data))
      #|        except httpx.HTTPError as error:
      #|            _LOG.warning("I lost an event stream from %s: %s", self.url, error)
      #|        finally:
      #|            await response.aclose()
      #|
      #|    async def close(self) -> None:
      #|        if self._closed:
      #|            return
      #|        self._closed = True
      #|        for task in list(self._readers):
      #|            task.cancel()
      #|        for task in list(self._readers):
      #|            with contextlib.suppress(asyncio.CancelledError):
      #|                await task
      #|        self._inbox.put_nowait(None)
      #|        await self._client.aclose()
      #|
      #|
      #|async def http_connect(url: str) -> HttpClientConnection:
      #|    """Give a connection to the JSON-RPC endpoint at `url`, such as `http://127.0.0.1:8080/rpc`.
      #|
      #|    The first post opens the session.
      #|    """
      #|    if not (url.startswith("http://") or url.startswith("https://")):
      #|        raise ValueError(f"I expected an http:// or https:// URL; I found {url!r}.")
      #|    return HttpClientConnection(url)
      #|
    ),
  ),
  (
    "ids.py",
    (
      #|"""JSON-RPC request IDs."""
      #|
      #|from __future__ import annotations
      #|
      #|from dataclasses import dataclass
      #|
      #|from .errors import DecodeError
      #|from .json_codec import JsonValue, describe, dumps
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class RequestId:
      #|    """A request ID: a string or an integer, kept exactly.
      #|
      #|    The string "1" and the integer 1 are different IDs.
      #|    """
      #|
      #|    value: int | str
      #|
      #|    def __post_init__(self) -> None:
      #|        if isinstance(self.value, bool) or not isinstance(self.value, (int, str)):  # pyright: ignore[reportUnnecessaryIsInstance]
      #|            raise TypeError(f"I expected a string or integer request ID; I found {self.value!r}.")
      #|
      #|    def __eq__(self, other: object) -> bool:
      #|        if not isinstance(other, RequestId):
      #|            return NotImplemented
      #|        return type(self.value) is type(other.value) and self.value == other.value
      #|
      #|    def __hash__(self) -> int:
      #|        return hash((type(self.value).__name__, self.value))
      #|
      #|    def to_json(self) -> JsonValue:
      #|        """Give the ID as a JSON value."""
      #|        return self.value
      #|
      #|    @staticmethod
      #|    def from_json(value: JsonValue, *, path: str = "/id") -> RequestId:
      #|        """Read an ID. Raises `DecodeError` for any value except a string or an integer."""
      #|        if isinstance(value, bool) or not isinstance(value, (int, str)):
      #|            raise DecodeError(
      #|                path=path,
      #|                message=f"I expected a string or integer request ID; I found {describe(value)}.",
      #|            )
      #|        return RequestId(value)
      #|
      #|    def __str__(self) -> str:
      #|        return dumps(self.value)
      #|
    ),
  ),
  (
    "json_codec.py",
    (
      #|"""Exact JSON reading and writing.
      #|
      #|The reader gives `int` for each integer number and `decimal.Decimal` for each
      #|number with a fraction or an exponent. A number never goes through `float`.
      #|The writer writes a `Decimal` as a JSON number with its exact text, so
      #|`Decimal("20.00")` stays `20.00`. The writer is compact and keeps non-ASCII
      #|text as UTF-8.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|import json
      #|import math
      #|from decimal import Decimal
      #|from typing import TypeAlias, Union, cast
      #|
      #|from .errors import DecodeError
      #|
      #|JsonValue: TypeAlias = Union[  # noqa: UP007
      #|    bool, int, Decimal, float, str, list["JsonValue"], dict[str, "JsonValue"], None
      #|]
      #|"""A JSON value. An object is a `dict`, an array is a `list`."""
      #|
      #|JsonObject: TypeAlias = dict[str, JsonValue]
      #|
      #|
      #|def _reject_constant(name: str) -> JsonValue:
      #|    raise ValueError(f"I expected a JSON number; I found {name}.")
      #|
      #|
      #|def loads(text: str) -> JsonValue:
      #|    """Parse JSON text exactly.
      #|
      #|    Raises `DecodeError` with the path "" when the text is not JSON.
      #|    """
      #|    try:
      #|        value: JsonValue = json.loads(
      #|            text,
      #|            parse_float=Decimal,
      #|            parse_int=int,
      #|            parse_constant=_reject_constant,
      #|        )
      #|    except (ValueError, RecursionError) as error:
      #|        message = f"I could not parse the message as JSON: {error}."
      #|        raise DecodeError(path="", message=message) from None
      #|    return value
      #|
      #|
      #|def _number_text(value: Decimal) -> str:
      #|    if not value.is_finite():
      #|        raise ValueError(f"I expected a finite decimal number; I found {value}.")
      #|    return str(value)
      #|
      #|
      #|def _write(value: object, out: list[str]) -> None:
      #|    if value is None:
      #|        out.append("null")
      #|    elif value is True:
      #|        out.append("true")
      #|    elif value is False:
      #|        out.append("false")
      #|    elif isinstance(value, str):
      #|        out.append(json.dumps(value, ensure_ascii=False))
      #|    elif isinstance(value, int):
      #|        out.append(int.__repr__(value))
      #|    elif isinstance(value, Decimal):
      #|        out.append(_number_text(value))
      #|    elif isinstance(value, float):
      #|        if not math.isfinite(value):
      #|            raise ValueError(f"I expected a finite number; I found {value!r}.")
      #|        out.append(float.__repr__(value))
      #|    elif isinstance(value, dict):
      #|        out.append("{")
      #|        first = True
      #|        for key, item in cast("dict[object, object]", value).items():
      #|            if not isinstance(key, str):
      #|                raise TypeError(f"I expected a string object key; I found {key!r}.")
      #|            if not first:
      #|                out.append(",")
      #|            first = False
      #|            out.append(json.dumps(key, ensure_ascii=False))
      #|            out.append(":")
      #|            _write(item, out)
      #|        out.append("}")
      #|    elif isinstance(value, (list, tuple)):
      #|        out.append("[")
      #|        for index, item in enumerate(cast("list[object]", value)):
      #|            if index:
      #|                out.append(",")
      #|            _write(item, out)
      #|        out.append("]")
      #|    else:
      #|        raise TypeError(f"I expected a JSON value; I found a {type(value).__name__}.")
      #|
      #|
      #|def dumps(value: JsonValue) -> str:
      #|    """Write a JSON value as compact text.
      #|
      #|    Raises `TypeError` or `ValueError` when the value is not JSON, such as a
      #|    NaN or a set.
      #|    """
      #|    out: list[str] = []
      #|    _write(value, out)
      #|    return "".join(out)
      #|
      #|
      #|def object_of(value: JsonValue, *, path: str) -> JsonObject:
      #|    """Give the value as an object, or raise `DecodeError` at `path`."""
      #|    if isinstance(value, dict):
      #|        return value
      #|    raise DecodeError(path=path, message=f"I expected an object; I found {describe(value)}.")
      #|
      #|
      #|def describe(value: JsonValue) -> str:
      #|    """Name the kind of a JSON value, for an error message."""
      #|    if value is None:
      #|        return "null"
      #|    if isinstance(value, bool):
      #|        return "a boolean"
      #|    if isinstance(value, (int, Decimal, float)):
      #|        return f"the number {dumps(value)}"
      #|    if isinstance(value, str):
      #|        return f"the string {dumps(value)}"
      #|    if isinstance(value, list):
      #|        return "an array"
      #|    return "an object"
      #|
      #|
      #|def pointer_get(value: JsonValue, pointer: str) -> tuple[bool, JsonValue]:
      #|    """Resolve an RFC 6901 JSON Pointer.
      #|
      #|    Gives `(True, found)` when the pointer names a value, else `(False, None)`.
      #|    """
      #|    if pointer == "":
      #|        return True, value
      #|    current = value
      #|    for raw in pointer[1:].split("/"):
      #|        token = raw.replace("~1", "/").replace("~0", "~")
      #|        if isinstance(current, dict):
      #|            if token not in current:
      #|                return False, None
      #|            current = current[token]
      #|        elif isinstance(current, list):
      #|            if not token.isdigit() or (len(token) > 1 and token[0] == "0"):
      #|                return False, None
      #|            index = int(token)
      #|            if index >= len(current):
      #|                return False, None
      #|            current = current[index]
      #|        else:
      #|            return False, None
      #|    return True, current
      #|
      #|
      #|def check_pointer(pointer: str) -> str:
      #|    """Give the pointer when it is a valid RFC 6901 JSON Pointer."""
      #|    if pointer != "" and not pointer.startswith("/"):
      #|        raise ValueError(f"I expected a JSON Pointer that starts with /; I found {pointer!r}.")
      #|    index = pointer.find("~")
      #|    while index >= 0:
      #|        if pointer[index + 1 : index + 2] not in ("0", "1"):
      #|            raise ValueError(f"I expected ~0 or ~1 in JSON Pointer {pointer!r}.")
      #|        index = pointer.find("~", index + 1)
      #|    return pointer
      #|
    ),
  ),
  (
    "log.py",
    (
      #|"""The transcript log: one JSON line for each message that a peer sends or receives.
      #|
      #|Each line is `{"dir":"send","message":<message>}` or `{"dir":"recv",...}`,
      #|from the view of the peer that writes it. The message is the exact JSON text
      #|on the wire. `smithy validate rpc transcript --log-preset dir-message` reads it.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|from pathlib import Path
      #|from types import TracebackType
      #|from typing import Literal, TextIO
      #|
      #|from .errors import DecodeError
      #|from .json_codec import dumps, loads
      #|
      #|Direction = Literal["send", "recv"]
      #|
      #|
      #|class TranscriptLog:
      #|    """A dir-message JSONL transcript log in a file."""
      #|
      #|    def __init__(self, stream: TextIO) -> None:
      #|        self._stream = stream
      #|
      #|    @staticmethod
      #|    def open(path: str | Path) -> TranscriptLog:
      #|        """Create or replace the log file at `path`."""
      #|        return TranscriptLog(Path(path).open("w", encoding="utf-8", newline="\n"))
      #|
      #|    def record(self, direction: Direction, text: str) -> None:
      #|        """Write one line for a message. The line is written through at once."""
      #|        self._stream.write(f'{{"dir":"{direction}","message":{_one_line(text)}}}\n')
      #|        self._stream.flush()
      #|
      #|    def close(self) -> None:
      #|        """Close the file."""
      #|        self._stream.close()
      #|
      #|    def __enter__(self) -> TranscriptLog:
      #|        return self
      #|
      #|    def __exit__(
      #|        self,
      #|        kind: type[BaseException] | None,
      #|        error: BaseException | None,
      #|        trace: TracebackType | None,
      #|    ) -> None:
      #|        self.close()
      #|
      #|
      #|def _one_line(text: str) -> str:
      #|    """Give the message text when it is one line of JSON.
      #|
      #|    A message with a line break is written again in compact form, with the same
      #|    values. Text that is not JSON is written as a JSON string.
      #|    """
      #|    try:
      #|        value = loads(text)
      #|    except DecodeError:
      #|        return dumps(text)
      #|    if "\n" in text or "\r" in text:
      #|        return dumps(value)
      #|    return text.strip(" \t")
      #|
    ),
  ),
  (
    "params.py",
    (
      #|"""Params of a request: named, positional, or either."""
      #|
      #|from __future__ import annotations
      #|
      #|from collections.abc import Mapping, Sequence
      #|
      #|from .errors import DecodeError
      #|from .json_codec import JsonValue, describe
      #|
      #|
      #|def named_params(params: JsonValue | None) -> dict[str, JsonValue]:
      #|    """Give named params as an object. Absent params give an empty object.
      #|
      #|    Raises `DecodeError` for positional params or any other value.
      #|    """
      #|    if params is None:
      #|        return {}
      #|    if isinstance(params, dict):
      #|        return params
      #|    raise DecodeError(
      #|        path="/params", message=f"I expected named params (an object); I found {describe(params)}."
      #|    )
      #|
      #|
      #|def positional_params(
      #|    params: JsonValue | None, names: Sequence[str], *, either: bool
      #|) -> dict[str, JsonValue]:
      #|    """Give positional params as an object keyed by `names`, in order.
      #|
      #|    Named params are accepted only when `either` is true. Raises `DecodeError`
      #|    when the array has more items than `names`.
      #|    """
      #|    if params is None:
      #|        return {}
      #|    if isinstance(params, list):
      #|        if len(params) > len(names):
      #|            raise DecodeError(
      #|                path="/params",
      #|                message=(
      #|                    f"I expected at most {len(names)} positional params; I found {len(params)}."
      #|                ),
      #|            )
      #|        return dict(zip(names, params, strict=False))
      #|    if isinstance(params, dict) and either:
      #|        return params
      #|    expected = "positional or named params" if either else "positional params (an array)"
      #|    raise DecodeError(path="/params", message=f"I expected {expected}; I found {describe(params)}.")
      #|
      #|
      #|def to_positional(value: Mapping[str, JsonValue], names: Sequence[str]) -> list[JsonValue]:
      #|    """Give the members of `value` as an array in the order of `names`.
      #|
      #|    Trailing absent members are dropped. An absent member before a present
      #|    member becomes null.
      #|    """
      #|    items: list[JsonValue] = [value.get(name) for name in names]
      #|    last = max((index for index, name in enumerate(names) if name in value), default=-1)
      #|    return items[: last + 1]
      #|
    ),
  ),
  (
    "peer.py",
    (
      #|"""The JSON-RPC 2.0 peer: the dispatcher, the caller and the session checks.
      #|
      #|A peer is symmetric. It answers the requests of the remote peer with its
      #|handlers, and it sends requests and notifications to the remote peer. A
      #|handler runs in its own asyncio task, so it can call back the remote peer
      #|while its call runs, and the modeled cancel notification can cancel it.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|import asyncio
      #|import contextvars
      #|import logging
      #|from collections.abc import Awaitable, Callable
      #|from dataclasses import dataclass, field
      #|from enum import Enum
      #|from typing import Any
      #|
      #|from pydantic import ValidationError
      #|
      #|from .connection import Connection
      #|from .errors import (
      #|    INTERNAL_ERROR,
      #|    INVALID_PARAMS,
      #|    INVALID_REQUEST,
      #|    METHOD_NOT_FOUND,
      #|    PARSE_ERROR,
      #|    DecodeError,
      #|    RpcError,
      #|)
      #|from .ids import RequestId
      #|from .json_codec import JsonValue, describe, dumps, loads
      #|from .log import TranscriptLog
      #|from .session import CancelRule, Session, SessionRules, cancel_target
      #|
      #|_LOG = logging.getLogger(__name__)
      #|
      #|_current_call: contextvars.ContextVar[RequestId | None] = contextvars.ContextVar(
      #|    "smithy_jsonrpc_current_call", default=None
      #|)
      #|
      #|
      #|class MethodKind(Enum):
      #|    """How a method can be called."""
      #|
      #|    REQUEST_ONLY = "request"
      #|    NOTIFICATION_ONLY = "notification"
      #|    REQUEST_OR_NOTIFICATION = "either"
      #|
      #|
      #|class CallContext:
      #|    """The context of one incoming request or notification.
      #|
      #|    `id` is the request ID, or None for a notification. A handler uses `peer`
      #|    to call back the remote peer while its call runs.
      #|    """
      #|
      #|    __slots__ = ("id", "method", "peer")
      #|
      #|    def __init__(self, peer: Peer, method: str, id: RequestId | None) -> None:
      #|        self.peer = peer
      #|        self.method = method
      #|        self.id = id
      #|
      #|    def id_json(self) -> JsonValue:
      #|        """Give the request ID as a JSON value, or None for a notification."""
      #|        return None if self.id is None else self.id.to_json()
      #|
      #|    async def request(
      #|        self, method: str, params: JsonValue | None, *, checked: bool = True
      #|    ) -> JsonValue:
      #|        """Send a request to the remote peer. The same as `Peer.request`."""
      #|        return await self.peer.request(method, params, checked=checked)
      #|
      #|    async def notify(self, method: str, params: JsonValue | None, *, checked: bool = True) -> None:
      #|        """Send a notification to the remote peer. The same as `Peer.notify`."""
      #|        await self.peer.notify(method, params, checked=checked)
      #|
      #|
      #|RequestHandler = Callable[[JsonValue | None, CallContext], Awaitable[JsonValue]]
      #|NotificationHandler = Callable[[JsonValue | None, CallContext], Awaitable[None]]
      #|
      #|
      #|@dataclass(slots=True)
      #|class _Registration:
      #|    kind: MethodKind
      #|    handler: Callable[[JsonValue | None, CallContext], Awaitable[Any]]
      #|    answers: bool
      #|
      #|
      #|@dataclass(slots=True)
      #|class _Outgoing:
      #|    method: str
      #|    accepted: bool
      #|    future: asyncio.Future[JsonValue]
      #|
      #|
      #|@dataclass(slots=True)
      #|class _Incoming:
      #|    method: str
      #|    accepted: bool
      #|    task: asyncio.Task[None] | None = None
      #|    cancel_code: int | None = None
      #|
      #|
      #|@dataclass(slots=True)
      #|class _Reference:
      #|    id_member: str
      #|    position: int | None
      #|
      #|
      #|@dataclass(slots=True)
      #|class _Reply:
      #|    result: JsonValue = None
      #|    error: RpcError | None = None
      #|    extra: dict[str, JsonValue] = field(default_factory=dict[str, JsonValue])
      #|
      #|
      #|class Peer:
      #|    """One end of a JSON-RPC 2.0 session.
      #|
      #|    `self_name` and `remote_name` are the peer names of the protocol. `rules`
      #|    drive the session state. `log` records each message sent and received.
      #|    """
      #|
      #|    def __init__(
      #|        self,
      #|        *,
      #|        self_name: str,
      #|        remote_name: str,
      #|        rules: SessionRules,
      #|        log: TranscriptLog | None = None,
      #|    ) -> None:
      #|        self.self_name = self_name
      #|        self.remote_name = remote_name
      #|        self.rules = rules
      #|        self.log = log
      #|        self.session = Session(rules)
      #|        self._handlers: dict[str, _Registration] = {}
      #|        self._references: dict[str, _Reference] = {}
      #|        self._outgoing: dict[RequestId, _Outgoing] = {}
      #|        self._incoming: dict[RequestId, _Incoming] = {}
      #|        self._tasks: set[asyncio.Task[None]] = set()
      #|        self._next_id = 1
      #|        self._send_lock = asyncio.Lock()
      #|        self._connected = asyncio.Event()
      #|        self._conn: Connection | None = None
      #|        self._closed = False
      #|
      #|    # Registration
      #|
      #|    def on_request(self, method: str, kind: MethodKind, handler: RequestHandler) -> None:
      #|        """Answer requests of `method` with the result of `handler`.
      #|
      #|        When `kind` allows a notification, `handler` also runs for a
      #|        notification, and its result is dropped.
      #|        """
      #|        self._register(method, _Registration(kind, handler, answers=True))
      #|
      #|    def on_notification(self, method: str, kind: MethodKind, handler: NotificationHandler) -> None:
      #|        """Run `handler` for notifications of `method`.
      #|
      #|        When `kind` allows a request, a request gets the result null.
      #|        """
      #|        self._register(method, _Registration(kind, handler, answers=False))
      #|
      #|    def _register(self, method: str, registration: _Registration) -> None:
      #|        if method in self._handlers:
      #|            raise ValueError(f"I already have a handler for method {method}.")
      #|        self._handlers[method] = registration
      #|
      #|    def call_reference(self, method: str, *, id_member: str, position: int | None = None) -> None:
      #|        """Declare that each notification of `method` names an active call of this peer.
      #|
      #|        The ID is in member `id_member` of named params, or at `position` of
      #|        positional params. A notification that names no active call of this
      #|        peer is dropped with a diagnostic on stderr.
      #|        """
      #|        self._references[method] = _Reference(id_member, position)
      #|
      #|    # Calls to the remote peer
      #|
      #|    async def request(
      #|        self, method: str, params: JsonValue | None, *, checked: bool = True
      #|    ) -> JsonValue:
      #|        """Send a request and give its result.
      #|
      #|        Raises `RpcError` for an error reply. When `checked` is true and the
      #|        session refuses the call, raises `RpcError` with the modeled code and
      #|        sends nothing. Raises `ConnectionError` when the connection closes
      #|        first.
      #|        """
      #|        conn = await self._connection()
      #|        loop = asyncio.get_running_loop()
      #|        async with self._send_lock:
      #|            refusal = self.session.check(self.remote_name, method)
      #|            if refusal is not None and checked:
      #|                raise RpcError(refusal.code, refusal.message)
      #|            accepted = refusal is None
      #|            if accepted:
      #|                self.session.accept(self.remote_name, method)
      #|            request_id = RequestId(self._next_id)
      #|            self._next_id += 1
      #|            message: dict[str, JsonValue] = {
      #|                "jsonrpc": "2.0",
      #|                "id": request_id.to_json(),
      #|                "method": method,
      #|            }
      #|            if params is not None:
      #|                message["params"] = params
      #|            text = dumps(message)
      #|            future: asyncio.Future[JsonValue] = loop.create_future()
      #|            self._outgoing[request_id] = _Outgoing(method, accepted, future)
      #|            try:
      #|                await self._write(conn, text, related=_current_call.get())
      #|            except BaseException:
      #|                self._outgoing.pop(request_id, None)
      #|                raise
      #|        return await future
      #|
      #|    async def notify(self, method: str, params: JsonValue | None, *, checked: bool = True) -> None:
      #|        """Send a notification.
      #|
      #|        When `checked` is true and the session refuses it, raises `RpcError`
      #|        with the modeled code and sends nothing.
      #|        """
      #|        conn = await self._connection()
      #|        async with self._send_lock:
      #|            refusal = self.session.check(self.remote_name, method)
      #|            if refusal is not None and checked:
      #|                raise RpcError(refusal.code, refusal.message)
      #|            if refusal is None:
      #|                self.session.accept(self.remote_name, method)
      #|            message: dict[str, JsonValue] = {"jsonrpc": "2.0", "method": method}
      #|            if params is not None:
      #|                message["params"] = params
      #|            await self._write(conn, dumps(message), related=_current_call.get())
      #|
      #|    async def close(self) -> None:
      #|        """Close the connection. `run` then returns."""
      #|        if self._conn is not None:
      #|            await self._conn.close()
      #|
      #|    async def _connection(self) -> Connection:
      #|        if self._closed:
      #|            raise ConnectionError("I cannot send: the connection of the peer is closed.")
      #|        await self._connected.wait()
      #|        if self._conn is None or self._closed:
      #|            raise ConnectionError("I cannot send: the connection of the peer is closed.")
      #|        return self._conn
      #|
      #|    async def _write(self, conn: Connection, text: str, *, related: RequestId | None) -> None:
      #|        if self.log is not None:
      #|            self.log.record("send", text)
      #|        await conn.send(text, related=related)
      #|
      #|    # The read loop
      #|
      #|    async def run(self, conn: Connection) -> None:
      #|        """Read and dispatch messages until the remote peer closes the connection.
      #|
      #|        When it returns, the handlers that still run are cancelled, and the
      #|        calls that wait for a reply raise `ConnectionError`.
      #|        """
      #|        if self._conn is not None:
      #|            raise RuntimeError("I already run this peer on a connection.")
      #|        self._conn = conn
      #|        self._connected.set()
      #|        try:
      #|            while True:
      #|                text = await conn.receive()
      #|                if text is None:
      #|                    break
      #|                if self.log is not None:
      #|                    self.log.record("recv", text)
      #|                await self._dispatch(text)
      #|        finally:
      #|            self._closed = True
      #|            for task in list(self._tasks):
      #|                task.cancel()
      #|            if self._tasks:
      #|                await asyncio.gather(*self._tasks, return_exceptions=True)
      #|            for outgoing in self._outgoing.values():
      #|                if not outgoing.future.done():
      #|                    outgoing.future.set_exception(
      #|                        ConnectionError(
      #|                            f"I lost the connection before the reply to {outgoing.method}."
      #|                        )
      #|                    )
      #|            self._outgoing.clear()
      #|
      #|    async def _dispatch(self, text: str) -> None:
      #|        try:
      #|            value = loads(text)
      #|        except DecodeError as error:
      #|            await self._reply(None, None, _Reply(error=RpcError(PARSE_ERROR, error.message)))
      #|            return
      #|        if isinstance(value, list):
      #|            message = "I do not accept a batch; I received a JSON array."
      #|            await self._reply(None, None, _Reply(error=RpcError(INVALID_REQUEST, message)))
      #|            return
      #|        if not isinstance(value, dict):
      #|            await self._invalid(None, f"I found {describe(value)}")
      #|            return
      #|        if "method" in value:
      #|            await self._incoming_message(value)
      #|        elif "result" in value or "error" in value:
      #|            self._response(value)
      #|        else:
      #|            await self._invalid(
      #|                _usable_id(value), "I found an object with no method, result or error"
      #|            )
      #|
      #|    async def _invalid(self, request_id: RequestId | None, detail: str) -> None:
      #|        message = f"I expected a valid JSON-RPC 2.0 request; {detail}."
      #|        await self._reply(request_id, None, _Reply(error=RpcError(INVALID_REQUEST, message)))
      #|
      #|    async def _incoming_message(self, value: dict[str, JsonValue]) -> None:
      #|        request_id: RequestId | None = None
      #|        if "id" in value:
      #|            try:
      #|                request_id = RequestId.from_json(value["id"])
      #|            except DecodeError:
      #|                await self._invalid(None, f"I found the id {describe(value['id'])}")
      #|                return
      #|        if value.get("jsonrpc") != "2.0":
      #|            await self._invalid(
      #|                request_id, f"I found the jsonrpc member {describe(value.get('jsonrpc'))}"
      #|            )
      #|            return
      #|        method = value["method"]
      #|        if not isinstance(method, str):
      #|            await self._invalid(request_id, f"I found the method {describe(method)}")
      #|            return
      #|        params = value.get("params")
      #|        if "params" in value and not isinstance(params, (dict, list)):
      #|            await self._invalid(request_id, f"I found the params {describe(params)}")
      #|            return
      #|        if request_id is not None and request_id in self._incoming:
      #|            await self._invalid(
      #|                request_id, f"I found the id {request_id}, which an active call still uses"
      #|            )
      #|            return
      #|        registration = self._handlers.get(method)
      #|        cancel_rule = self.rules.cancel_rule(self.self_name, method)
      #|        modeled = self.rules.rule(self.self_name, method) is not None
      #|        if registration is None and not modeled:
      #|            if request_id is not None:
      #|                error = RpcError(METHOD_NOT_FOUND, f"I do not know method {method}.")
      #|                await self._reply(request_id, None, _Reply(error=error))
      #|            else:
      #|                _LOG.warning("I dropped notification %s: I do not know the method.", method)
      #|            return
      #|        refusal = self.session.accept(self.self_name, method)
      #|        if refusal is not None:
      #|            if request_id is not None:
      #|                error = RpcError(refusal.code, refusal.message)
      #|                await self._reply(request_id, None, _Reply(error=error))
      #|            else:
      #|                _LOG.warning("I dropped notification %s: %s", method, refusal.message)
      #|            return
      #|        if cancel_rule is not None:
      #|            self._cancel(cancel_rule, params)
      #|        if registration is None or (
      #|            request_id is not None and registration.kind is MethodKind.NOTIFICATION_ONLY
      #|        ):
      #|            if request_id is None:
      #|                return
      #|            if registration is None:
      #|                error = RpcError(METHOD_NOT_FOUND, f"I do not know method {method}.")
      #|            else:
      #|                error = RpcError(
      #|                    INVALID_REQUEST,
      #|                    f"I expected a notification for method {method}; I received a request.",
      #|                )
      #|            self._incoming[request_id] = _Incoming(method, accepted=True)
      #|            await self._reply(request_id, method, _Reply(error=error))
      #|            return
      #|        if request_id is None and registration.kind is MethodKind.REQUEST_ONLY:
      #|            _LOG.warning("I dropped notification %s: the method needs a request ID.", method)
      #|            return
      #|        if request_id is None and not self._refers_to_active_call(method, params):
      #|            return
      #|        self._start(registration, method, request_id, params)
      #|
      #|    def _refers_to_active_call(self, method: str, params: JsonValue | None) -> bool:
      #|        reference = self._references.get(method)
      #|        if reference is None:
      #|            return True
      #|        target = cancel_target(CancelRule(reference.id_member, reference.position), params)
      #|        if target is not None and target in self._outgoing:
      #|            return True
      #|        _LOG.warning(
      #|            "I dropped notification %s: it names no active call of mine (I found %s).",
      #|            method,
      #|            "no usable ID" if target is None else f"id {target}",
      #|        )
      #|        return False
      #|
      #|    def _cancel(self, rule: CancelRule, params: JsonValue | None) -> None:
      #|        target = cancel_target(rule, params)
      #|        call = None if target is None else self._incoming.get(target)
      #|        if call is None or call.task is None or call.task.done():
      #|            return
      #|        if call.cancel_code is None:
      #|            call.cancel_code = rule.answer_code
      #|            call.task.cancel()
      #|
      #|    def _start(
      #|        self,
      #|        registration: _Registration,
      #|        method: str,
      #|        request_id: RequestId | None,
      #|        params: JsonValue | None,
      #|    ) -> None:
      #|        if request_id is not None:
      #|            incoming = _Incoming(method, accepted=True)
      #|            self._incoming[request_id] = incoming
      #|            task = asyncio.create_task(self._handle(registration, method, request_id, params))
      #|            incoming.task = task
      #|        else:
      #|            task = asyncio.create_task(self._handle(registration, method, None, params))
      #|        self._tasks.add(task)
      #|        task.add_done_callback(self._tasks.discard)
      #|
      #|    async def _handle(
      #|        self,
      #|        registration: _Registration,
      #|        method: str,
      #|        request_id: RequestId | None,
      #|        params: JsonValue | None,
      #|    ) -> None:
      #|        _current_call.set(request_id)
      #|        context = CallContext(self, method, request_id)
      #|        try:
      #|            result: JsonValue = await registration.handler(params, context)
      #|            reply = _Reply(result=result if registration.answers else None)
      #|        except asyncio.CancelledError:
      #|            incoming = None if request_id is None else self._incoming.get(request_id)
      #|            if incoming is None or incoming.cancel_code is None or self._closed:
      #|                raise
      #|            task = asyncio.current_task()
      #|            if task is not None:
      #|                task.uncancel()
      #|            reply = _Reply(error=RpcError(incoming.cancel_code, f"I cancelled {method}."))
      #|        except RpcError as error:
      #|            reply = _Reply(error=error)
      #|        except DecodeError as error:
      #|            reply = _Reply(error=_decode_error(method, error.path, error.message))
      #|        except ValidationError as error:
      #|            path, message = _validation_detail(error)
      #|            reply = _Reply(error=_decode_error(method, path, message))
      #|        except Exception as error:
      #|            _LOG.exception("I could not handle %s.", method)
      #|            reply = _Reply(error=RpcError(INTERNAL_ERROR, f"I could not handle {method}: {error}"))
      #|        if request_id is None:
      #|            if reply.error is not None:
      #|                _LOG.warning("I could not handle notification %s: %s", method, reply.error.message)
      #|            return
      #|        await self._reply(request_id, method, reply)
      #|
      #|    async def _reply(self, request_id: RequestId | None, method: str | None, reply: _Reply) -> None:
      #|        """Send a response. `method` is set when the reply answers an accepted call."""
      #|        text = _response_text(request_id, reply)
      #|        if text is None:
      #|            error = RpcError(INTERNAL_ERROR, f"I could not write the result of {method} as JSON.")
      #|            reply = _Reply(error=error)
      #|            text = _response_text(request_id, reply)
      #|            assert text is not None
      #|        if self._conn is None:
      #|            return
      #|        async with self._send_lock:
      #|            incoming = None if request_id is None else self._incoming.pop(request_id, None)
      #|            if incoming is not None and incoming.accepted and method is not None:
      #|                self.session.settle(
      #|                    self.self_name, method, failed=reply.error is not None, result=reply.result
      #|                )
      #|            if self._closed:
      #|                return
      #|            try:
      #|                await self._write(self._conn, text, related=request_id)
      #|            except (ConnectionError, OSError) as error:
      #|                _LOG.warning("I could not send the reply to %s: %s", method, error)
      #|
      #|    def _response(self, value: dict[str, JsonValue]) -> None:
      #|        raw = value.get("id")
      #|        try:
      #|            request_id = RequestId.from_json(raw)
      #|        except DecodeError:
      #|            _LOG.warning(
      #|                "I received a reply with %s, which matches no call: %s", describe(raw), dumps(value)
      #|            )
      #|            return
      #|        outgoing = self._outgoing.pop(request_id, None)
      #|        if outgoing is None:
      #|            _LOG.warning("I received a reply with id %s, which matches no call.", request_id)
      #|            return
      #|        error = value.get("error")
      #|        failed = error is not None
      #|        if not failed and "result" not in value:
      #|            if not outgoing.future.done():
      #|                outgoing.future.set_exception(
      #|                    RpcError(
      #|                        INTERNAL_ERROR,
      #|                        f"I expected a result or an error in the reply to {outgoing.method}; "
      #|                        "I found neither.",
      #|                    )
      #|                )
      #|            return
      #|        result = None if failed else value.get("result")
      #|        if outgoing.accepted:
      #|            self.session.settle(self.remote_name, outgoing.method, failed=failed, result=result)
      #|        if outgoing.future.done():
      #|            return
      #|        if failed:
      #|            outgoing.future.set_exception(_error_from_json(outgoing.method, error))
      #|        else:
      #|            outgoing.future.set_result(result)
      #|
      #|
      #|def _usable_id(value: dict[str, JsonValue]) -> RequestId | None:
      #|    try:
      #|        return RequestId.from_json(value.get("id"))
      #|    except DecodeError:
      #|        return None
      #|
      #|
      #|def _decode_error(method: str, path: str, message: str) -> RpcError:
      #|    return RpcError(
      #|        INVALID_PARAMS, f"I could not decode {method} params at {path or '/'}: {message}"
      #|    )
      #|
      #|
      #|def _validation_detail(error: ValidationError) -> tuple[str, str]:
      #|    errors = error.errors(include_url=False)
      #|    if not errors:
      #|        return "", str(error)
      #|    first = errors[0]
      #|    path = "".join("/" + str(step).replace("~", "~0").replace("/", "~1") for step in first["loc"])
      #|    return path, f"{first['msg']}."
      #|
      #|
      #|def _error_from_json(method: str, error: JsonValue) -> RpcError:
      #|    if isinstance(error, dict):
      #|        code = error.get("code")
      #|        message = error.get("message")
      #|        if isinstance(code, int) and not isinstance(code, bool) and isinstance(message, str):
      #|            return RpcError(code, message, error.get("data"))
      #|    return RpcError(
      #|        INTERNAL_ERROR,
      #|        f"I expected an error object with an integer code in the reply to {method}; "
      #|        f"I found {describe(error)}.",
      #|    )
      #|
      #|
      #|def _response_text(request_id: RequestId | None, reply: _Reply) -> str | None:
      #|    message: dict[str, JsonValue] = {
      #|        "jsonrpc": "2.0",
      #|        "id": None if request_id is None else request_id.to_json(),
      #|    }
      #|    if reply.error is not None:
      #|        message["error"] = reply.error.to_json()
      #|    else:
      #|        message["result"] = reply.result
      #|    try:
      #|        return dumps(message)
      #|    except (TypeError, ValueError):
      #|        return None
      #|
    ),
  ),
  (
    "py.typed",
    (
      #|
    ),
  ),
  (
    "server.py",
    (
      #|"""The FastAPI integration: `POST /rpc` and `WebSocket /ws` for a peer.
      #|
      #|It needs FastAPI and uvicorn.
      #|
      #|`POST /rpc` follows the Streamable HTTP style:
      #|
      #|- The first post without `Smithy-Session-Id` opens a session with a new peer
      #|  from the peer factory. Each response has the header. A post with an
      #|  unknown session ID gets 404.
      #|- A posted request gets 200 `text/event-stream`. The stream starts with the
      #|  comment `: open`. Each event is `event: message` and `data: <message>`.
      #|  The notifications and requests of the handler of that request come first,
      #|  then the response, then the stream ends.
      #|- A message of the peer that belongs to no open stream goes on the latest
      #|  open stream of the session. When no stream is open, the session keeps it
      #|  for the next stream.
      #|- A posted notification or response gets 202 with an empty body.
      #|- Text that is not JSON, a batch or a value that is not an object gets 200
      #|  `application/json` with the error (-32700 or -32600, ID null). The session
      #|  does not see it.
      #|
      #|`WebSocket /ws` carries one message in each text frame. Each WebSocket
      #|connection has a new peer.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|import asyncio
      #|import contextlib
      #|import sys
      #|import uuid
      #|from collections.abc import AsyncIterator, Callable
      #|from dataclasses import dataclass
      #|
      #|import uvicorn
      #|from fastapi import FastAPI, Request, Response, WebSocket, WebSocketDisconnect
      #|from fastapi.responses import StreamingResponse
      #|
      #|from .connection import SESSION_HEADER
      #|from .errors import INVALID_REQUEST, PARSE_ERROR, DecodeError
      #|from .ids import RequestId
      #|from .json_codec import JsonValue, describe, dumps, loads
      #|from .peer import Peer
      #|
      #|PeerFactory = Callable[[], Peer]
      #|"""Makes a new peer, with its handlers, for each session."""
      #|
      #|
      #|def _is_response_to(text: str, request_id: RequestId) -> bool:
      #|    try:
      #|        value = loads(text)
      #|    except DecodeError:
      #|        return False
      #|    if not isinstance(value, dict) or "method" in value or "id" not in value:
      #|        return False
      #|    try:
      #|        return RequestId.from_json(value["id"]) == request_id
      #|    except DecodeError:
      #|        return False
      #|
      #|
      #|class HttpSessionConnection:
      #|    """The connection of the peer of one HTTP session."""
      #|
      #|    def __init__(self) -> None:
      #|        self._inbox: asyncio.Queue[str | None] = asyncio.Queue()
      #|        self._streams: dict[RequestId, asyncio.Queue[str | None]] = {}
      #|        self._held: list[str] = []
      #|        self._closed = False
      #|
      #|    def is_open(self, request_id: RequestId) -> bool:
      #|        """Whether the stream of the request is open."""
      #|        return request_id in self._streams
      #|
      #|    def open_stream(self, request_id: RequestId) -> asyncio.Queue[str | None]:
      #|        """Open the stream of a posted request. It gets the messages that the session kept."""
      #|        queue: asyncio.Queue[str | None] = asyncio.Queue()
      #|        self._streams[request_id] = queue
      #|        for text in self._held:
      #|            queue.put_nowait(text)
      #|        self._held.clear()
      #|        return queue
      #|
      #|    def deliver(self, text: str) -> None:
      #|        """Give a posted message to the peer."""
      #|        self._inbox.put_nowait(text)
      #|
      #|    async def receive(self) -> str | None:
      #|        if self._closed and self._inbox.empty():
      #|            return None
      #|        return await self._inbox.get()
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        if self._closed:
      #|            raise ConnectionError("I cannot send: the HTTP session is closed.")
      #|        if related is not None and related in self._streams:
      #|            target: RequestId | None = related
      #|        elif self._streams:
      #|            target = next(reversed(self._streams))
      #|        else:
      #|            target = None
      #|        if target is None:
      #|            self._held.append(text)
      #|            return
      #|        queue = self._streams[target]
      #|        queue.put_nowait(text)
      #|        if related == target and _is_response_to(text, target):
      #|            queue.put_nowait(None)
      #|            del self._streams[target]
      #|
      #|    async def close(self) -> None:
      #|        if self._closed:
      #|            return
      #|        self._closed = True
      #|        self._inbox.put_nowait(None)
      #|        for queue in self._streams.values():
      #|            queue.put_nowait(None)
      #|        self._streams.clear()
      #|
      #|
      #|@dataclass(slots=True)
      #|class _Session:
      #|    conn: HttpSessionConnection
      #|    peer: Peer
      #|    task: asyncio.Task[None]
      #|
      #|
      #|class _WebSocketConnection:
      #|    def __init__(self, socket: WebSocket) -> None:
      #|        self._socket = socket
      #|
      #|    async def receive(self) -> str | None:
      #|        try:
      #|            return await self._socket.receive_text()
      #|        except (WebSocketDisconnect, RuntimeError):
      #|            return None
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        try:
      #|            await self._socket.send_text(text)
      #|        except (WebSocketDisconnect, RuntimeError) as error:
      #|            raise ConnectionError(f"I cannot send: the WebSocket closed ({error}).") from error
      #|
      #|    async def close(self) -> None:
      #|        with contextlib.suppress(RuntimeError):
      #|            await self._socket.close()
      #|
      #|
      #|def _json_error(code: int, message: str, request_id: JsonValue = None) -> Response:
      #|    body = dumps({"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}})
      #|    return Response(content=body, media_type="application/json")
      #|
      #|
      #|async def _events(queue: asyncio.Queue[str | None]) -> AsyncIterator[bytes]:
      #|    yield b": open\n\n"
      #|    while True:
      #|        text = await queue.get()
      #|        if text is None:
      #|            return
      #|        yield b"event: message\ndata: " + text.encode("utf-8") + b"\n\n"
      #|
      #|
      #|def create_app(peer_factory: PeerFactory) -> FastAPI:
      #|    """Give a FastAPI app with `POST /rpc` and `WebSocket /ws` for the peers of `peer_factory`."""
      #|    app = FastAPI()
      #|    sessions: dict[str, _Session] = {}
      #|
      #|    @app.post("/rpc")
      #|    async def rpc(request: Request) -> Response:  # pyright: ignore[reportUnusedFunction]
      #|        session_id = request.headers.get(SESSION_HEADER)
      #|        session = None
      #|        if session_id is not None:
      #|            session = sessions.get(session_id)
      #|            if session is None:
      #|                return Response(status_code=404)
      #|        raw = await request.body()
      #|        try:
      #|            text = raw.decode("utf-8")
      #|            value = loads(text)
      #|        except UnicodeDecodeError as error:
      #|            return _json_error(PARSE_ERROR, f"I could not parse the message as JSON: {error}.")
      #|        except DecodeError as error:
      #|            return _json_error(PARSE_ERROR, error.message)
      #|        if isinstance(value, list):
      #|            return _json_error(INVALID_REQUEST, "I do not accept a batch; I received a JSON array.")
      #|        if not isinstance(value, dict):
      #|            return _json_error(
      #|                INVALID_REQUEST,
      #|                f"I expected a valid JSON-RPC 2.0 request; I found {describe(value)}.",
      #|            )
      #|        request_id: RequestId | None = None
      #|        if "method" in value and "id" in value:
      #|            try:
      #|                request_id = RequestId.from_json(value["id"])
      #|            except DecodeError:
      #|                return _json_error(
      #|                    INVALID_REQUEST,
      #|                    "I expected a valid JSON-RPC 2.0 request; "
      #|                    f"I found the id {describe(value['id'])}.",
      #|                )
      #|        if session is None:
      #|            session_id = uuid.uuid4().hex
      #|            conn = HttpSessionConnection()
      #|            peer = peer_factory()
      #|            session = _Session(conn, peer, asyncio.create_task(peer.run(conn)))
      #|            sessions[session_id] = session
      #|        assert session_id is not None
      #|        headers = {SESSION_HEADER: session_id}
      #|        if request_id is None:
      #|            session.conn.deliver(text)
      #|            return Response(status_code=202, headers=headers)
      #|        if session.conn.is_open(request_id):
      #|            return _json_error(
      #|                INVALID_REQUEST,
      #|                f"I expected a valid JSON-RPC 2.0 request; I found the id {request_id}, "
      #|                "which an active call still uses.",
      #|                request_id.to_json(),
      #|            )
      #|        queue = session.conn.open_stream(request_id)
      #|        session.conn.deliver(text)
      #|        return StreamingResponse(
      #|            _events(queue),
      #|            media_type="text/event-stream",
      #|            headers={**headers, "Cache-Control": "no-cache"},
      #|        )
      #|
      #|    @app.websocket("/ws")
      #|    async def ws(socket: WebSocket) -> None:  # pyright: ignore[reportUnusedFunction]
      #|        await socket.accept()
      #|        await peer_factory().run(_WebSocketConnection(socket))
      #|
      #|    return app
      #|
      #|
      #|class RunningServer:
      #|    """A uvicorn server that runs in a task. `port` is the port that it listens on."""
      #|
      #|    def __init__(self, server: uvicorn.Server, task: asyncio.Task[None], port: int) -> None:
      #|        self._server = server
      #|        self._task = task
      #|        self.port = port
      #|
      #|    async def wait(self) -> None:
      #|        """Wait until the server stops."""
      #|        await self._task
      #|
      #|    async def stop(self) -> None:
      #|        """Stop the server and wait until it stops."""
      #|        self._server.should_exit = True
      #|        await self._task
      #|
      #|
      #|async def start_server(
      #|    port: int, peer_factory: PeerFactory, *, host: str = "127.0.0.1"
      #|) -> RunningServer:
      #|    """Start the app of `peer_factory` on `host:port`. Port 0 selects a free port."""
      #|    config = uvicorn.Config(
      #|        create_app(peer_factory),
      #|        host=host,
      #|        port=port,
      #|        log_level="warning",
      #|        access_log=False,
      #|        ws="websockets-sansio",
      #|        lifespan="off",
      #|    )
      #|    server = uvicorn.Server(config)
      #|    task = asyncio.create_task(server.serve())
      #|    while not server.started:
      #|        if task.done():
      #|            await task
      #|            raise OSError(f"I could not start the server on {host}:{port}.")
      #|        await asyncio.sleep(0.01)
      #|    sockets = [sock for listener in server.servers for sock in listener.sockets]
      #|    actual = int(sockets[0].getsockname()[1]) if sockets else port
      #|    return RunningServer(server, task, actual)
      #|
      #|
      #|async def serve(port: int, peer_factory: PeerFactory, *, host: str = "127.0.0.1") -> None:
      #|    """Serve the app of `peer_factory` until the process stops.
      #|
      #|    When the server is ready, I write `listening N` to stderr.
      #|    """
      #|    running = await start_server(port, peer_factory, host=host)
      #|    sys.stderr.write(f"listening {running.port}\n")
      #|    sys.stderr.flush()
      #|    await running.wait()
      #|
    ),
  ),
  (
    "session.py",
    (
      #|"""Session rules and the session state machine.
      #|
      #|The generator renders the `jsonRpcSession`, `jsonRpcLifecycle` and
      #|`jsonRpcCancels` traits of a protocol as one `SessionRules` value. Each peer
      #|keeps one `Session` and applies every message that it sends or receives, with
      #|the semantics of `smithy validate rpc transcript`:
      #|
      #|- A method with a rule for its receiving peer is refused when the state is not
      #|  in its allowed states, or when a capability that it requires is not
      #|  advertised. A refused message changes nothing, and its reply settles nothing.
      #|- An accepted message applies `on_call` first, then its cancellation.
      #|- The reply of an accepted call applies `on_error` for an error and
      #|  `on_success` for a result, from the rule of the peer that answers. A result
      #|  advertises each capability source of the method unless the value at the
      #|  pointer is absent, null or false. A capability is never withdrawn.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|from collections.abc import Iterable, Sequence
      #|from dataclasses import dataclass, field
      #|
      #|from .errors import INVALID_REQUEST, REQUEST_CANCELLED
      #|from .ids import RequestId
      #|from .json_codec import JsonValue, check_pointer, pointer_get
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class CapabilitySource:
      #|    """A capability that the successful result of a method advertises.
      #|
      #|    `pointer` is a JSON Pointer into the result of `method_name`.
      #|    """
      #|
      #|    name: str
      #|    method_name: str
      #|    pointer: str
      #|
      #|    def __post_init__(self) -> None:
      #|        if not self.name:
      #|            raise ValueError("I expected a nonempty capability name; I found an empty name.")
      #|        if not self.method_name:
      #|            raise ValueError(f"I expected a method for capability {self.name}; I found none.")
      #|        check_pointer(self.pointer)
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class CancelRule:
      #|    """How a method cancels a call.
      #|
      #|    `id_member` is the wire name of the ID member in named params. `position`
      #|    is its index in positional params. `code` is the error code that the
      #|    cancelled call answers with.
      #|    """
      #|
      #|    id_member: str
      #|    position: int | None = None
      #|    code: int | None = None
      #|
      #|    def call_id(self, params: JsonValue | None) -> JsonValue | None:
      #|        """Give the raw ID that the params name, or None."""
      #|        if isinstance(params, dict):
      #|            return params.get(self.id_member)
      #|        if isinstance(params, list) and self.position is not None:
      #|            return params[self.position] if self.position < len(params) else None
      #|        return None
      #|
      #|    @property
      #|    def answer_code(self) -> int:
      #|        """The code of the answer to a cancelled call: `code`, else -32800."""
      #|        return REQUEST_CANCELLED if self.code is None else self.code
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class MethodRule:
      #|    """The order rules of one method that `receiver` accepts.
      #|
      #|    `allowed` None means every state. `requires` names capabilities.
      #|    """
      #|
      #|    receiver: str
      #|    method_name: str
      #|    allowed: Sequence[str] | None = None
      #|    on_call: str | None = None
      #|    on_success: str | None = None
      #|    on_error: str | None = None
      #|    requires: Sequence[str] = ()
      #|    cancels: CancelRule | None = None
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class Refusal:
      #|    """Why a session refuses a message, with the code of the error reply."""
      #|
      #|    code: int
      #|    message: str
      #|
      #|
      #|class SessionRules:
      #|    """The session rules of a protocol. The first state is the initial state."""
      #|
      #|    __slots__ = ("_methods", "capabilities", "capability_refusal", "refusals", "states")
      #|
      #|    def __init__(
      #|        self,
      #|        *,
      #|        states: Sequence[str],
      #|        capabilities: Sequence[CapabilitySource] = (),
      #|        methods: Sequence[MethodRule] = (),
      #|        refusals: Iterable[tuple[str, int]] = (),
      #|        capability_refusal: int | None = None,
      #|    ) -> None:
      #|        if not states:
      #|            raise ValueError("I expected at least one session state; I found none.")
      #|        if len(set(states)) != len(states):
      #|            raise ValueError(f"I expected distinct session states; I found {list(states)}.")
      #|        self.states: tuple[str, ...] = tuple(states)
      #|        names = [source.name for source in capabilities]
      #|        if len(set(names)) != len(names):
      #|            raise ValueError(f"I expected distinct capability names; I found {names}.")
      #|        self.capabilities: tuple[CapabilitySource, ...] = tuple(capabilities)
      #|        self._methods: dict[tuple[str, str], MethodRule] = {}
      #|        for rule in methods:
      #|            self._check_rule(rule, set(names))
      #|            key = (rule.receiver, rule.method_name)
      #|            if key in self._methods:
      #|                raise ValueError(
      #|                    f"I expected one rule for method {rule.method_name} of peer {rule.receiver}; "
      #|                    "I found two."
      #|                )
      #|            self._methods[key] = rule
      #|        self.refusals: dict[str, int] = {}
      #|        for state, code in refusals:
      #|            self._check_state(state, "a refusal")
      #|            if state in self.refusals:
      #|                raise ValueError(f"I expected one refusal code for state {state}; I found two.")
      #|            self.refusals[state] = code
      #|        self.capability_refusal = capability_refusal
      #|
      #|    @staticmethod
      #|    def none() -> SessionRules:
      #|        """Rules with one state and no method rules: every message is accepted."""
      #|        return SessionRules(states=["open"])
      #|
      #|    def _check_state(self, state: str, construct: str) -> None:
      #|        if state not in self.states:
      #|            raise ValueError(f"I expected {construct} to name a session state; I found {state!r}.")
      #|
      #|    def _check_rule(self, rule: MethodRule, capabilities: set[str]) -> None:
      #|        construct = f"the rule of method {rule.method_name}"
      #|        for state in rule.allowed or ():
      #|            self._check_state(state, construct)
      #|        if rule.allowed is not None and not rule.allowed:
      #|            raise ValueError(f"I expected {construct} to allow at least one state; I found none.")
      #|        for state in (rule.on_call, rule.on_success, rule.on_error):
      #|            if state is not None:
      #|                self._check_state(state, construct)
      #|        for name in rule.requires:
      #|            if name not in capabilities:
      #|                raise ValueError(
      #|                    f"I expected {construct} to require a known capability; I found {name!r}."
      #|                )
      #|
      #|    def rule(self, receiver: str, method: str) -> MethodRule | None:
      #|        """Give the rule of `method` when `receiver` accepts it, or None."""
      #|        return self._methods.get((receiver, method))
      #|
      #|    def cancel_rule(self, receiver: str, method: str) -> CancelRule | None:
      #|        """Give the cancellation of `method` when `receiver` accepts it, or None."""
      #|        found = self._methods.get((receiver, method))
      #|        return None if found is None else found.cancels
      #|
      #|
      #|@dataclass(slots=True)
      #|class Session:
      #|    """The session state of one peer, driven by `SessionRules`."""
      #|
      #|    rules: SessionRules
      #|    state: str = ""
      #|    advertised: set[str] = field(default_factory=set[str])
      #|
      #|    def __post_init__(self) -> None:
      #|        if not self.state:
      #|            self.state = self.rules.states[0]
      #|
      #|    def check(self, receiver: str, method: str) -> Refusal | None:
      #|        """Give the refusal of a message from the other peer of `receiver`, or None."""
      #|        rule = self.rules.rule(receiver, method)
      #|        if rule is None:
      #|            return None
      #|        if rule.allowed is not None and self.state not in rule.allowed:
      #|            code = self.rules.refusals.get(self.state, INVALID_REQUEST)
      #|            return Refusal(code, f"I refused {method} in state {self.state}.")
      #|        for name in rule.requires:
      #|            if name not in self.advertised:
      #|                code = (
      #|                    INVALID_REQUEST
      #|                    if self.rules.capability_refusal is None
      #|                    else self.rules.capability_refusal
      #|                )
      #|                return Refusal(code, f"I refused {method} because {name} is not advertised.")
      #|        return None
      #|
      #|    def accept(self, receiver: str, method: str) -> Refusal | None:
      #|        """Check a message and, when it is accepted, apply its `on_call` state."""
      #|        refusal = self.check(receiver, method)
      #|        if refusal is None:
      #|            rule = self.rules.rule(receiver, method)
      #|            if rule is not None and rule.on_call is not None:
      #|                self.state = rule.on_call
      #|        return refusal
      #|
      #|    def settle(self, responder: str, method: str, *, failed: bool, result: JsonValue) -> None:
      #|        """Apply the reply of an accepted call that `responder` answers."""
      #|        rule = self.rules.rule(responder, method)
      #|        if rule is not None:
      #|            following = rule.on_error if failed else rule.on_success
      #|            if following is not None:
      #|                self.state = following
      #|        if failed:
      #|            return
      #|        for source in self.rules.capabilities:
      #|            if source.method_name == method:
      #|                found, value = pointer_get(result, source.pointer)
      #|                if found and value is not None and value is not False:
      #|                    self.advertised.add(source.name)
      #|
      #|
      #|def cancel_target(rule: CancelRule, params: JsonValue | None) -> RequestId | None:
      #|    """Give the ID of the call that a cancellation names, or None when it names no usable ID."""
      #|    raw = rule.call_id(params)
      #|    if isinstance(raw, bool) or not isinstance(raw, (int, str)):
      #|        return None
      #|    return RequestId(raw)
      #|
    ),
  ),
  (
    "stdio.py",
    (
      #|"""The stdio transport: Content-Length framing, as in LSP.
      #|
      #|Each message is `Content-Length: N\\r\\n\\r\\n` and then N bytes of UTF-8 JSON.
      #|A reader ignores the headers that it does not know, such as Content-Type.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|import asyncio
      #|import contextlib
      #|import os
      #|import sys
      #|import threading
      #|from collections.abc import Sequence
      #|from typing import BinaryIO
      #|
      #|from .ids import RequestId
      #|
      #|MAX_FRAME_BYTES = 64 * 1024 * 1024
      #|"""The largest message body that a reader accepts."""
      #|
      #|_MAX_HEADER_BYTES = 8192
      #|
      #|
      #|def encode_frame(text: str) -> bytes:
      #|    """Give the framed bytes of one message."""
      #|    body = text.encode("utf-8")
      #|    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body
      #|
      #|
      #|class FramingError(ConnectionError):
      #|    """The byte stream does not hold a valid Content-Length frame."""
      #|
      #|
      #|class _HeaderParser:
      #|    def __init__(self) -> None:
      #|        self.length: int | None = None
      #|        self.size = 0
      #|
      #|    def line(self, raw: bytes) -> bool:
      #|        """Read one header line. Gives true at the blank line that ends the headers."""
      #|        self.size += len(raw)
      #|        if self.size > _MAX_HEADER_BYTES:
      #|            raise FramingError(f"I expected at most {_MAX_HEADER_BYTES} header bytes in a frame.")
      #|        text = raw.decode("ascii", errors="replace").rstrip("\r\n")
      #|        if text == "":
      #|            if self.length is None:
      #|                raise FramingError("I expected a Content-Length header; I found a blank line.")
      #|            return True
      #|        name, separator, value = text.partition(":")
      #|        if not separator:
      #|            raise FramingError(f"I expected a header with a colon; I found {text!r}.")
      #|        if name.strip().lower() == "content-length":
      #|            digits = value.strip()
      #|            if not digits.isdigit():
      #|                raise FramingError(f"I expected a decimal Content-Length; I found {digits!r}.")
      #|            length = int(digits)
      #|            if length > MAX_FRAME_BYTES:
      #|                raise FramingError(
      #|                    f"I expected a Content-Length of at most {MAX_FRAME_BYTES}; I found {length}."
      #|                )
      #|            self.length = length
      #|        return False
      #|
      #|
      #|async def read_frame(reader: asyncio.StreamReader) -> str | None:
      #|    """Read one message from an asyncio stream. Gives None at the end of the stream."""
      #|    parser = _HeaderParser()
      #|    first = True
      #|    while True:
      #|        raw = await reader.readline()
      #|        if raw == b"":
      #|            if first:
      #|                return None
      #|            raise FramingError("I reached the end of the stream inside the headers of a frame.")
      #|        first = False
      #|        if parser.line(raw):
      #|            break
      #|    assert parser.length is not None
      #|    try:
      #|        body = await reader.readexactly(parser.length)
      #|    except asyncio.IncompleteReadError as error:
      #|        raise FramingError(
      #|            f"I expected {parser.length} body bytes; the stream ended after {len(error.partial)}."
      #|        ) from None
      #|    return _decode(body)
      #|
      #|
      #|def read_frame_blocking(stream: BinaryIO) -> str | None:
      #|    """Read one message from a blocking binary stream. Gives None at the end of the stream."""
      #|    parser = _HeaderParser()
      #|    first = True
      #|    while True:
      #|        raw = stream.readline(_MAX_HEADER_BYTES + 1)
      #|        if raw == b"":
      #|            if first:
      #|                return None
      #|            raise FramingError("I reached the end of the stream inside the headers of a frame.")
      #|        first = False
      #|        if parser.line(raw):
      #|            break
      #|    assert parser.length is not None
      #|    chunks: list[bytes] = []
      #|    remaining = parser.length
      #|    while remaining:
      #|        chunk = stream.read(remaining)
      #|        if not chunk:
      #|            raise FramingError(
      #|                f"I expected {parser.length} body bytes; "
      #|                f"the stream ended after {parser.length - remaining}."
      #|            )
      #|        chunks.append(chunk)
      #|        remaining -= len(chunk)
      #|    return _decode(b"".join(chunks))
      #|
      #|
      #|def _decode(body: bytes) -> str:
      #|    try:
      #|        return body.decode("utf-8")
      #|    except UnicodeDecodeError as error:
      #|        raise FramingError(f"I expected a UTF-8 message body: {error}.") from None
      #|
      #|
      #|class StreamConnection:
      #|    """A framed connection on an asyncio stream pair."""
      #|
      #|    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
      #|        self._reader = reader
      #|        self._writer = writer
      #|        self._lock = asyncio.Lock()
      #|        self._closed = False
      #|
      #|    async def receive(self) -> str | None:
      #|        if self._closed:
      #|            return None
      #|        return await read_frame(self._reader)
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        async with self._lock:
      #|            if self._closed:
      #|                raise ConnectionError("I cannot send on a closed stream connection.")
      #|            self._writer.write(encode_frame(text))
      #|            await self._writer.drain()
      #|
      #|    async def close(self) -> None:
      #|        if self._closed:
      #|            return
      #|        self._closed = True
      #|        self._writer.close()
      #|        with contextlib.suppress(ConnectionError, OSError):
      #|            await self._writer.wait_closed()
      #|
      #|
      #|class StdioConnection:
      #|    """A framed connection on the stdin and stdout of this process.
      #|
      #|    A daemon thread reads stdin, so the transport works with pipes, files and
      #|    terminals on every platform. Nothing else may write to stdout.
      #|    """
      #|
      #|    def __init__(self, stdin: BinaryIO | None = None, stdout: BinaryIO | None = None) -> None:
      #|        self._stdin = stdin if stdin is not None else sys.stdin.buffer
      #|        self._stdout = stdout if stdout is not None else sys.stdout.buffer
      #|        self._queue: asyncio.Queue[str | BaseException | None] | None = None
      #|        self._lock = threading.Lock()
      #|        self._closed = False
      #|
      #|    def _start(self) -> asyncio.Queue[str | BaseException | None]:
      #|        if self._queue is not None:
      #|            return self._queue
      #|        loop = asyncio.get_running_loop()
      #|        queue: asyncio.Queue[str | BaseException | None] = asyncio.Queue()
      #|        self._queue = queue
      #|
      #|        def pump() -> None:
      #|            while True:
      #|                try:
      #|                    item: str | BaseException | None = read_frame_blocking(self._stdin)
      #|                except (OSError, ValueError, FramingError) as error:
      #|                    item = error
      #|                try:
      #|                    loop.call_soon_threadsafe(queue.put_nowait, item)
      #|                except RuntimeError:
      #|                    return
      #|                if not isinstance(item, str):
      #|                    return
      #|
      #|        threading.Thread(target=pump, name="stdio-reader", daemon=True).start()
      #|        return queue
      #|
      #|    async def receive(self) -> str | None:
      #|        if self._closed:
      #|            return None
      #|        item = await self._start().get()
      #|        if isinstance(item, BaseException):
      #|            raise item
      #|        return item
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        frame = encode_frame(text)
      #|        with self._lock:
      #|            if self._closed:
      #|                raise ConnectionError("I cannot send on a closed stdio connection.")
      #|            self._stdout.write(frame)
      #|            self._stdout.flush()
      #|
      #|    async def close(self) -> None:
      #|        if self._closed:
      #|            return
      #|        self._closed = True
      #|        with contextlib.suppress(OSError, ValueError):
      #|            self._stdout.flush()
      #|        if self._queue is not None:
      #|            self._queue.put_nowait(None)
      #|
      #|
      #|def stdio_connection() -> StdioConnection:
      #|    """Give the framed connection on stdin and stdout."""
      #|    return StdioConnection()
      #|
      #|
      #|class ProcessConnection(StreamConnection):
      #|    """A framed connection on the stdin and stdout of a child process.
      #|
      #|    The child writes its diagnostics to the stderr of this process.
      #|    """
      #|
      #|    def __init__(self, process: asyncio.subprocess.Process) -> None:
      #|        assert process.stdout is not None and process.stdin is not None
      #|        super().__init__(process.stdout, process.stdin)
      #|        self.process = process
      #|
      #|    exit_wait = 5.0
      #|    """The seconds that `close` waits for the child to exit before it kills the child."""
      #|
      #|    async def close(self) -> None:
      #|        """Close the stdin of the child, then wait for it to exit. Kill it after `exit_wait`."""
      #|        await super().close()
      #|        try:
      #|            await asyncio.wait_for(self.process.wait(), self.exit_wait)
      #|        except TimeoutError:
      #|            with contextlib.suppress(ProcessLookupError):
      #|                self.process.kill()
      #|            await self.process.wait()
      #|
      #|    async def wait(self) -> int:
      #|        """Wait for the child to exit, and give its exit code."""
      #|        return await self.process.wait()
      #|
      #|
      #|async def spawn_stdio(
      #|    argv: Sequence[str], *, cwd: str | os.PathLike[str] | None = None
      #|) -> ProcessConnection:
      #|    """Start a child process and give the framed connection on its stdin and stdout.
      #|
      #|    The child gets the stderr of this process. `cwd` is its working directory.
      #|    """
      #|    if not argv:
      #|        raise ValueError("I expected a command to start; I found an empty argv.")
      #|    process = await asyncio.create_subprocess_exec(
      #|        *argv,
      #|        stdin=asyncio.subprocess.PIPE,
      #|        stdout=asyncio.subprocess.PIPE,
      #|        stderr=None,
      #|        cwd=cwd,
      #|    )
      #|    return ProcessConnection(process)
      #|
    ),
  ),
  (
    "values.py",
    (
      #|"""Exact value types for generated Pydantic models.
      #|
      #|- `BigDecimal` is a `decimal.Decimal` that accepts only a JSON number.
      #|- `BigInteger` is an `int` that accepts only a JSON integer.
      #|- `Blob` is `bytes` that is base64 text on the wire.
      #|- `Timestamp` keeps the JSON value of a timestamp exactly.
      #|"""
      #|
      #|from __future__ import annotations
      #|
      #|import base64
      #|import binascii
      #|import email.utils
      #|import math
      #|from dataclasses import dataclass
      #|from datetime import UTC, datetime
      #|from decimal import Decimal
      #|from enum import Enum
      #|from typing import TYPE_CHECKING, Annotated, Any, cast
      #|
      #|from pydantic import (
      #|    BaseModel,
      #|    BeforeValidator,
      #|    ConfigDict,
      #|    Field,
      #|    GetCoreSchemaHandler,
      #|    PlainSerializer,
      #|)
      #|from pydantic_core import core_schema
      #|
      #|from .errors import DecodeError
      #|from .json_codec import JsonValue, describe
      #|
      #|
      #|def decode_decimal(value: object, *, path: str = "") -> Decimal:
      #|    """Read a JSON number as an exact `Decimal`. A float, a string or a boolean is an error."""
      #|    if isinstance(value, Decimal):
      #|        return value
      #|    if isinstance(value, int) and not isinstance(value, bool):
      #|        return Decimal(value)
      #|    raise DecodeError(path=path, message=f"I expected a JSON number; I found {_name(value)}.")
      #|
      #|
      #|def decode_integer(value: object, *, path: str = "") -> int:
      #|    """Read a JSON integer exactly. A number with a fraction, such as 1.5, is an error."""
      #|    if isinstance(value, int) and not isinstance(value, bool):
      #|        return value
      #|    if isinstance(value, Decimal) and value.is_finite() and value == value.to_integral_value():
      #|        return int(value)
      #|    raise DecodeError(path=path, message=f"I expected a JSON integer; I found {_name(value)}.")
      #|
      #|
      #|def encode_blob(data: bytes) -> str:
      #|    """Give the standard base64 text of the bytes, with padding and no line breaks."""
      #|    return base64.b64encode(data).decode("ascii")
      #|
      #|
      #|def decode_blob(value: object, *, path: str = "") -> bytes:
      #|    """Read standard base64 text. Raises `DecodeError` for other text or values."""
      #|    if isinstance(value, (bytes, bytearray)):
      #|        return bytes(value)
      #|    if not isinstance(value, str):
      #|        raise DecodeError(path=path, message=f"I expected base64 text; I found {_name(value)}.")
      #|    try:
      #|        return base64.b64decode(value.encode("ascii"), validate=True)
      #|    except (binascii.Error, UnicodeEncodeError):
      #|        raise DecodeError(
      #|            path=path, message=f"I expected base64 text; I found {value!r}."
      #|        ) from None
      #|
      #|
      #|def _name(value: object) -> str:
      #|    if value is None or isinstance(value, (bool, int, Decimal, float, str, list, dict)):
      #|        return describe(cast("JsonValue", value))
      #|    return f"a {type(value).__name__}"
      #|
      #|
      #|def _pydantic_value_error(function: Any) -> Any:
      #|    def validate(value: object) -> object:
      #|        try:
      #|            return function(value)
      #|        except DecodeError as error:
      #|            raise ValueError(error.message) from None
      #|
      #|    return validate
      #|
      #|
      #|BigDecimal = Annotated[Decimal, BeforeValidator(_pydantic_value_error(decode_decimal))]
      #|"""A Smithy bigDecimal. The JSON writer keeps its exact text."""
      #|
      #|BigInteger = Annotated[int, BeforeValidator(_pydantic_value_error(decode_integer))]
      #|"""A Smithy bigInteger or long. It is never a float."""
      #|
      #|Blob = Annotated[
      #|    bytes,
      #|    BeforeValidator(_pydantic_value_error(decode_blob)),
      #|    PlainSerializer(encode_blob, return_type=str),
      #|]
      #|"""A Smithy blob: bytes in Python, base64 text in JSON."""
      #|
      #|
      #|class TimestampFormat(Enum):
      #|    """The wire formats of a Smithy timestamp."""
      #|
      #|    EPOCH_SECONDS = "epoch-seconds"
      #|    DATE_TIME = "date-time"
      #|    HTTP_DATE = "http-date"
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class Timestamp:
      #|    """A timestamp that keeps its JSON value: an exact number of epoch seconds, or text.
      #|
      #|    Use `Timestamp.from_json` to read a value in a known format, and `to_json`
      #|    to write it back unchanged.
      #|    """
      #|
      #|    value: int | Decimal | str
      #|
      #|    @staticmethod
      #|    def from_json(
      #|        value: JsonValue,
      #|        *,
      #|        format: TimestampFormat = TimestampFormat.EPOCH_SECONDS,
      #|        path: str = "",
      #|    ) -> Timestamp:
      #|        """Read a timestamp in `format`. Raises `DecodeError` when the value does not match."""
      #|        if format is TimestampFormat.EPOCH_SECONDS:
      #|            if isinstance(value, bool) or not isinstance(value, (int, Decimal)):
      #|                raise DecodeError(
      #|                    path=path,
      #|                    message=f"I expected epoch seconds as a JSON number; I found {_name(value)}.",
      #|                )
      #|            return Timestamp(value)
      #|        if not isinstance(value, str):
      #|            raise DecodeError(
      #|                path=path,
      #|                message=f"I expected a {format.value} timestamp string; I found {_name(value)}.",
      #|            )
      #|        try:
      #|            if format is TimestampFormat.DATE_TIME:
      #|                _parse_date_time(value)
      #|            else:
      #|                email.utils.parsedate_to_datetime(value)
      #|        except (ValueError, TypeError):
      #|            raise DecodeError(
      #|                path=path, message=f"I expected a {format.value} timestamp; I found {value!r}."
      #|            ) from None
      #|        return Timestamp(value)
      #|
      #|    @staticmethod
      #|    def from_datetime(
      #|        moment: datetime, *, format: TimestampFormat = TimestampFormat.EPOCH_SECONDS
      #|    ) -> Timestamp:
      #|        """Make a timestamp in `format` from an aware datetime."""
      #|        if moment.tzinfo is None:
      #|            raise ValueError(f"I expected an aware datetime; I found {moment.isoformat()}.")
      #|        if format is TimestampFormat.EPOCH_SECONDS:
      #|            delta = moment - datetime(1970, 1, 1, tzinfo=UTC)
      #|            micros = (delta.days * 86400 + delta.seconds) * 1_000_000 + delta.microseconds
      #|            seconds = Decimal(micros).scaleb(-6).normalize()
      #|            exponent = seconds.as_tuple().exponent
      #|            if isinstance(exponent, int) and exponent >= 0:
      #|                return Timestamp(int(seconds))
      #|            return Timestamp(seconds)
      #|        if format is TimestampFormat.DATE_TIME:
      #|            return Timestamp(moment.astimezone(UTC).isoformat().replace("+00:00", "Z"))
      #|        return Timestamp(email.utils.format_datetime(moment.astimezone(UTC), usegmt=True))
      #|
      #|    def to_json(self) -> JsonValue:
      #|        """Give the JSON value, unchanged."""
      #|        return self.value
      #|
      #|    def to_datetime(self) -> datetime:
      #|        """Give an aware datetime in UTC. A fraction below a microsecond is lost."""
      #|        if isinstance(self.value, str):
      #|            try:
      #|                return _parse_date_time(self.value)
      #|            except ValueError:
      #|                return email.utils.parsedate_to_datetime(self.value).astimezone(UTC)
      #|        seconds = Decimal(self.value)
      #|        whole = int(seconds.to_integral_value(rounding="ROUND_FLOOR"))
      #|        micros = int(((seconds - whole) * 1_000_000).to_integral_value())
      #|        moment = datetime.fromtimestamp(whole, tz=UTC)
      #|        return moment.replace(microsecond=micros) if micros < 1_000_000 else moment
      #|
      #|    @classmethod
      #|    def __get_pydantic_core_schema__(
      #|        cls, source: object, handler: GetCoreSchemaHandler
      #|    ) -> core_schema.CoreSchema:
      #|        return _timestamp_schema(None)
      #|
      #|
      #|def _parse_date_time(text: str) -> datetime:
      #|    if "T" not in text and "t" not in text:
      #|        raise ValueError(f"I expected a date-time with a T separator; I found {text!r}.")
      #|    moment = datetime.fromisoformat(text)
      #|    if moment.tzinfo is None:
      #|        raise ValueError(f"I expected a date-time with an offset; I found {text!r}.")
      #|    return moment.astimezone(UTC)
      #|
      #|
      #|def _timestamp_schema(format: TimestampFormat | None) -> core_schema.CoreSchema:
      #|    def validate(value: object) -> Timestamp:
      #|        if isinstance(value, Timestamp):
      #|            return value
      #|        chosen = format
      #|        if chosen is None:
      #|            text = isinstance(value, str)
      #|            chosen = TimestampFormat.DATE_TIME if text else TimestampFormat.EPOCH_SECONDS
      #|        try:
      #|            return Timestamp.from_json(value, format=chosen)  # pyright: ignore[reportArgumentType]
      #|        except DecodeError as error:
      #|            raise ValueError(error.message) from None
      #|
      #|    return core_schema.no_info_plain_validator_function(
      #|        validate,
      #|        serialization=core_schema.plain_serializer_function_ser_schema(
      #|            lambda timestamp: timestamp.value  # pyright: ignore[reportUnknownLambdaType, reportUnknownMemberType]
      #|        ),
      #|    )
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class _TimestampAs:
      #|    format: TimestampFormat
      #|
      #|    def __get_pydantic_core_schema__(
      #|        self, source: object, handler: GetCoreSchemaHandler
      #|    ) -> core_schema.CoreSchema:
      #|        return _timestamp_schema(self.format)
      #|
      #|
      #|EpochSecondsTimestamp = Annotated[Timestamp, _TimestampAs(TimestampFormat.EPOCH_SECONDS)]
      #|DateTimeTimestamp = Annotated[Timestamp, _TimestampAs(TimestampFormat.DATE_TIME)]
      #|HttpDateTimestamp = Annotated[Timestamp, _TimestampAs(TimestampFormat.HTTP_DATE)]
      #|
      #|
      #|def to_wire(value: object) -> JsonValue:
      #|    """Convert a Python value, such as a generated model, to a JSON value.
      #|
      #|    A Pydantic model is dumped with its wire names, without the members that
      #|    are None. `Decimal` and `int` stay exact, `bytes` become base64 text, a
      #|    `Timestamp` gives its JSON value, an aware `datetime` gives date-time text,
      #|    an `Enum` gives its value, and a tuple becomes an array. Raises `TypeError`
      #|    for any other value.
      #|    """
      #|    if value is None or isinstance(value, bool):
      #|        return value
      #|    if isinstance(value, Enum):
      #|        return to_wire(value.value)  # pyright: ignore[reportUnknownMemberType]
      #|    if isinstance(value, BaseModel):
      #|        return to_wire(value.model_dump(mode="python", by_alias=True, exclude_none=True))
      #|    if isinstance(value, float):
      #|        return encode_double(value)
      #|    if isinstance(value, (int, Decimal, str)):
      #|        return value
      #|    if isinstance(value, (bytes, bytearray)):
      #|        return encode_blob(bytes(value))
      #|    if isinstance(value, Timestamp):
      #|        return value.value
      #|    if isinstance(value, datetime):
      #|        return Timestamp.from_datetime(value, format=TimestampFormat.DATE_TIME).value
      #|    if isinstance(value, dict):
      #|        out: dict[str, JsonValue] = {}
      #|        for key, item in cast("dict[object, object]", value).items():
      #|            if not isinstance(key, str):
      #|                raise TypeError(f"I expected a string object key; I found {key!r}.")
      #|            out[key] = to_wire(item)
      #|        return out
      #|    if isinstance(value, (list, tuple)):
      #|        return [to_wire(item) for item in cast("list[object]", value)]
      #|    raise TypeError(f"I expected a value that JSON can carry; I found a {type(value).__name__}.")
      #|
      #|
      #|def to_wire_object(value: object) -> dict[str, JsonValue]:
      #|    """Convert a model to a JSON object. Raises `TypeError` when the value is not an object."""
      #|    wire = to_wire(value)
      #|    if not isinstance(wire, dict):
      #|        raise TypeError(f"I expected a value that gives a JSON object; I found {describe(wire)}.")
      #|    return wire
      #|
      #|
      #|_NON_FINITE = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}
      #|
      #|
      #|def decode_double(value: object, *, path: str = "") -> float:
      #|    """Read a JSON number as a `float`. The strings "NaN", "Infinity" and "-Infinity"
      #|    give the non-finite values. Another string or a boolean is an error."""
      #|    if isinstance(value, float):
      #|        return value
      #|    if isinstance(value, (int, Decimal)) and not isinstance(value, bool):
      #|        return float(value)
      #|    if isinstance(value, str) and value in _NON_FINITE:
      #|        return _NON_FINITE[value]
      #|    raise DecodeError(path=path, message=f"I expected a JSON number; I found {_name(value)}.")
      #|
      #|
      #|def encode_double(value: float) -> float | str:
      #|    """Give a finite float unchanged, and a non-finite float as "NaN", "Infinity" or "-Infinity"."""
      #|    if math.isnan(value):
      #|        return "NaN"
      #|    if math.isinf(value):
      #|        return "Infinity" if value > 0 else "-Infinity"
      #|    return value
      #|
      #|
      #|Double = Annotated[
      #|    float,
      #|    BeforeValidator(_pydantic_value_error(decode_double)),
      #|    PlainSerializer(encode_double),
      #|]
      #|"""A Smithy float or double. It accepts a JSON number, or "NaN", "Infinity" and "-Infinity"."""
      #|
      #|Byte = Annotated[
      #|    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**7), le=2**7 - 1)
      #|]
      #|"""A Smithy byte: an integer from -128 to 127."""
      #|
      #|Short = Annotated[
      #|    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**15), le=2**15 - 1)
      #|]
      #|"""A Smithy short: an integer from -32768 to 32767."""
      #|
      #|Integer = Annotated[
      #|    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**31), le=2**31 - 1)
      #|]
      #|"""A Smithy integer: a 32-bit signed integer."""
      #|
      #|Long = Annotated[
      #|    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**63), le=2**63 - 1)
      #|]
      #|"""A Smithy long: a 64-bit signed integer, kept exactly."""
      #|
      #|
      #|def check_document(value: object, *, path: str = "") -> JsonValue:
      #|    """Give the value when it is a JSON value. Raises `DecodeError` at the first other value.
      #|
      #|    The check keeps its own stack, so a deep value does not recurse.
      #|    """
      #|    stack: list[tuple[object, str]] = [(value, path)]
      #|    while stack:
      #|        item, at = stack.pop()
      #|        if item is None or isinstance(item, (bool, int, Decimal, float, str)):
      #|            continue
      #|        if isinstance(item, list):
      #|            for index, inner in enumerate(cast("list[object]", item)):
      #|                stack.append((inner, f"{at}/{index}"))
      #|        elif isinstance(item, dict):
      #|            for key, inner in cast("dict[object, object]", item).items():
      #|                if not isinstance(key, str):
      #|                    raise DecodeError(path=at, message=f"I expected a string key; I found {key!r}.")
      #|                stack.append((inner, f"{at}/{key.replace('~', '~0').replace('/', '~1')}"))
      #|        else:
      #|            raise DecodeError(path=at, message=f"I expected a JSON value; I found {_name(item)}.")
      #|    return cast("JsonValue", value)
      #|
      #|
      #|@dataclass(frozen=True, slots=True)
      #|class _DocumentSchema:
      #|    def __get_pydantic_core_schema__(
      #|        self, source: object, handler: GetCoreSchemaHandler
      #|    ) -> core_schema.CoreSchema:
      #|        return core_schema.no_info_plain_validator_function(
      #|            _pydantic_value_error(check_document),
      #|            serialization=core_schema.plain_serializer_function_ser_schema(
      #|                lambda value: value  # pyright: ignore[reportUnknownLambdaType]
      #|            ),
      #|        )
      #|
      #|
      #|if TYPE_CHECKING:
      #|    Document = JsonValue
      #|    """A Smithy document: any JSON value, kept exactly."""
      #|else:
      #|    # Pydantic must not resolve the recursive alias; the schema checks the value.
      #|    Document = Annotated[object, _DocumentSchema()]
      #|
      #|
      #|class Unit(BaseModel):
      #|    """The value of a union member that targets `smithy.api#Unit`: an empty object."""
      #|
      #|    model_config = ConfigDict(extra="forbid", frozen=True)
      #|
      #|
      #|def union_tag(value: object) -> str | None:
      #|    """Give the member name of a tagged union value, for a Pydantic `Discriminator`.
      #|
      #|    A JSON object gives its one member that is not null. A generated member
      #|    model gives its `union_member` class attribute. Any other value gives None.
      #|    """
      #|    if isinstance(value, dict):
      #|        keys = [
      #|            key for key, item in cast("dict[object, object]", value).items() if item is not None
      #|        ]
      #|        if len(keys) == 1 and isinstance(keys[0], str):
      #|            return keys[0]
      #|        return None
      #|    tag = getattr(type(value), "union_member", None)
      #|    return tag if isinstance(tag, str) else None
      #|
    ),
  ),
  (
    "ws_client.py",
    (
      #|"""The WebSocket client transport: one message in each text frame. It needs `websockets`."""
      #|
      #|from __future__ import annotations
      #|
      #|from websockets.asyncio.client import ClientConnection, connect
      #|from websockets.exceptions import ConnectionClosed
      #|
      #|from .ids import RequestId
      #|from .stdio import MAX_FRAME_BYTES
      #|
      #|
      #|class WsConnection:
      #|    """A connection to a JSON-RPC peer at a WebSocket endpoint."""
      #|
      #|    def __init__(self, socket: ClientConnection) -> None:
      #|        self._socket = socket
      #|
      #|    async def receive(self) -> str | None:
      #|        try:
      #|            message = await self._socket.recv()
      #|        except ConnectionClosed:
      #|            return None
      #|        return message if isinstance(message, str) else message.decode("utf-8")
      #|
      #|    async def send(self, text: str, *, related: RequestId | None = None) -> None:
      #|        try:
      #|            await self._socket.send(text)
      #|        except ConnectionClosed as error:
      #|            raise ConnectionError(f"I cannot send: the WebSocket closed ({error}).") from error
      #|
      #|    async def close(self) -> None:
      #|        await self._socket.close()
      #|
      #|
      #|async def ws_connect(url: str) -> WsConnection:
      #|    """Open a WebSocket connection to `url`, such as `ws://127.0.0.1:8080/ws`."""
      #|    if not (url.startswith("ws://") or url.startswith("wss://")):
      #|        raise ValueError(f"I expected a ws:// or wss:// URL; I found {url!r}.")
      #|    socket = await connect(url, max_size=MAX_FRAME_BYTES)
      #|    return WsConnection(socket)
      #|
    ),
  ),
]

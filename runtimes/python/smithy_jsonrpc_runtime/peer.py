"""The JSON-RPC 2.0 peer: the dispatcher, the caller and the session checks.

A peer is symmetric. It answers the requests of the remote peer with its
handlers, and it sends requests and notifications to the remote peer. A
handler runs in its own asyncio task, so it can call back the remote peer
while its call runs, and the modeled cancel notification can cancel it.
"""

from __future__ import annotations

import asyncio
import contextvars
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from pydantic import ValidationError

from .connection import Connection
from .errors import (
    INTERNAL_ERROR,
    INVALID_PARAMS,
    INVALID_REQUEST,
    METHOD_NOT_FOUND,
    PARSE_ERROR,
    DecodeError,
    RpcError,
)
from .ids import RequestId
from .json_codec import JsonValue, describe, dumps, loads
from .log import TranscriptLog
from .session import CancelRule, Session, SessionRules, cancel_target

_LOG = logging.getLogger(__name__)

_current_call: contextvars.ContextVar[RequestId | None] = contextvars.ContextVar(
    "smithy_jsonrpc_current_call", default=None
)


class MethodKind(Enum):
    """How a method can be called."""

    REQUEST_ONLY = "request"
    NOTIFICATION_ONLY = "notification"
    REQUEST_OR_NOTIFICATION = "either"


class CallContext:
    """The context of one incoming request or notification.

    `id` is the request ID, or None for a notification. A handler uses `peer`
    to call back the remote peer while its call runs.
    """

    __slots__ = ("id", "method", "peer")

    def __init__(self, peer: Peer, method: str, id: RequestId | None) -> None:
        self.peer = peer
        self.method = method
        self.id = id

    def id_json(self) -> JsonValue:
        """Give the request ID as a JSON value, or None for a notification."""
        return None if self.id is None else self.id.to_json()

    async def request(
        self, method: str, params: JsonValue | None, *, checked: bool = True
    ) -> JsonValue:
        """Send a request to the remote peer. The same as `Peer.request`."""
        return await self.peer.request(method, params, checked=checked)

    async def notify(self, method: str, params: JsonValue | None, *, checked: bool = True) -> None:
        """Send a notification to the remote peer. The same as `Peer.notify`."""
        await self.peer.notify(method, params, checked=checked)


RequestHandler = Callable[[JsonValue | None, CallContext], Awaitable[JsonValue]]
NotificationHandler = Callable[[JsonValue | None, CallContext], Awaitable[None]]


@dataclass(slots=True)
class _Registration:
    kind: MethodKind
    handler: Callable[[JsonValue | None, CallContext], Awaitable[Any]]
    answers: bool


@dataclass(slots=True)
class _Outgoing:
    method: str
    accepted: bool
    future: asyncio.Future[JsonValue]


@dataclass(slots=True)
class _Incoming:
    method: str
    accepted: bool
    task: asyncio.Task[None] | None = None
    cancel_code: int | None = None
    started: bool = False


@dataclass(slots=True)
class _Reference:
    id_member: str
    position: int | None


@dataclass(slots=True)
class _Reply:
    result: JsonValue = None
    error: RpcError | None = None
    extra: dict[str, JsonValue] = field(default_factory=dict[str, JsonValue])


class Peer:
    """One end of a JSON-RPC 2.0 session.

    `self_name` and `remote_name` are the peer names of the protocol. `rules`
    drive the session state. `log` records each message sent and received.
    """

    def __init__(
        self,
        *,
        self_name: str,
        remote_name: str,
        rules: SessionRules,
        log: TranscriptLog | None = None,
    ) -> None:
        self.self_name = self_name
        self.remote_name = remote_name
        self.rules = rules
        self.log = log
        self.session = Session(rules)
        self._handlers: dict[str, _Registration] = {}
        self._references: dict[str, _Reference] = {}
        self._outgoing: dict[RequestId, _Outgoing] = {}
        self._incoming: dict[RequestId, _Incoming] = {}
        self._tasks: set[asyncio.Task[None]] = set()
        self._next_id = 1
        self._send_lock = asyncio.Lock()
        self._connected = asyncio.Event()
        self._conn: Connection | None = None
        self._closed = False

    # Registration

    def on_request(self, method: str, kind: MethodKind, handler: RequestHandler) -> None:
        """Answer requests of `method` with the result of `handler`.

        When `kind` allows a notification, `handler` also runs for a
        notification, and its result is dropped.
        """
        self._register(method, _Registration(kind, handler, answers=True))

    def on_notification(self, method: str, kind: MethodKind, handler: NotificationHandler) -> None:
        """Run `handler` for notifications of `method`.

        When `kind` allows a request, a request gets the result null.
        """
        self._register(method, _Registration(kind, handler, answers=False))

    def _register(self, method: str, registration: _Registration) -> None:
        if method in self._handlers:
            raise ValueError(f"I already have a handler for method {method}.")
        self._handlers[method] = registration

    def call_reference(self, method: str, *, id_member: str, position: int | None = None) -> None:
        """Declare that each notification of `method` names an active call of this peer.

        The ID is in member `id_member` of named params, or at `position` of
        positional params. A notification that names no active call of this
        peer is dropped with a diagnostic on stderr.
        """
        self._references[method] = _Reference(id_member, position)

    # Calls to the remote peer

    async def request(
        self, method: str, params: JsonValue | None, *, checked: bool = True
    ) -> JsonValue:
        """Send a request and give its result.

        Raises `RpcError` for an error reply. When `checked` is true and the
        session refuses the call, raises `RpcError` with the modeled code and
        sends nothing. Raises `ConnectionError` when the connection closes
        first.
        """
        conn = await self._connection()
        loop = asyncio.get_running_loop()
        async with self._send_lock:
            refusal = self.session.check(self.remote_name, method)
            if refusal is not None and checked:
                raise RpcError(refusal.code, refusal.message)
            accepted = refusal is None
            if accepted:
                self.session.accept(self.remote_name, method)
            request_id = RequestId(self._next_id)
            self._next_id += 1
            message: dict[str, JsonValue] = {
                "jsonrpc": "2.0",
                "id": request_id.to_json(),
                "method": method,
            }
            if params is not None:
                message["params"] = params
            text = dumps(message)
            future: asyncio.Future[JsonValue] = loop.create_future()
            self._outgoing[request_id] = _Outgoing(method, accepted, future)
            try:
                await self._write(conn, text, related=_current_call.get())
            except BaseException:
                self._outgoing.pop(request_id, None)
                raise
        return await future

    async def notify(self, method: str, params: JsonValue | None, *, checked: bool = True) -> None:
        """Send a notification.

        When `checked` is true and the session refuses it, raises `RpcError`
        with the modeled code and sends nothing.
        """
        conn = await self._connection()
        async with self._send_lock:
            refusal = self.session.check(self.remote_name, method)
            if refusal is not None and checked:
                raise RpcError(refusal.code, refusal.message)
            if refusal is None:
                self.session.accept(self.remote_name, method)
            message: dict[str, JsonValue] = {"jsonrpc": "2.0", "method": method}
            if params is not None:
                message["params"] = params
            await self._write(conn, dumps(message), related=_current_call.get())

    async def close(self) -> None:
        """Close the connection. `run` then returns."""
        if self._conn is not None:
            await self._conn.close()

    async def _connection(self) -> Connection:
        if self._closed:
            raise ConnectionError("I cannot send: the connection of the peer is closed.")
        await self._connected.wait()
        if self._conn is None or self._closed:
            raise ConnectionError("I cannot send: the connection of the peer is closed.")
        return self._conn

    async def _write(self, conn: Connection, text: str, *, related: RequestId | None) -> None:
        if self.log is not None:
            self.log.record("send", text)
        await conn.send(text, related=related)

    # The read loop

    async def run(self, conn: Connection) -> None:
        """Read and dispatch messages until the remote peer closes the connection.

        When it returns, the handlers that still run are cancelled, and the
        calls that wait for a reply raise `ConnectionError`.
        """
        if self._conn is not None:
            raise RuntimeError("I already run this peer on a connection.")
        self._conn = conn
        self._connected.set()
        try:
            while True:
                text = await conn.receive()
                if text is None:
                    break
                if self.log is not None:
                    self.log.record("recv", text)
                await self._dispatch(text)
        finally:
            self._closed = True
            for task in list(self._tasks):
                task.cancel()
            if self._tasks:
                await asyncio.gather(*self._tasks, return_exceptions=True)
            for outgoing in self._outgoing.values():
                if not outgoing.future.done():
                    outgoing.future.set_exception(
                        ConnectionError(
                            f"I lost the connection before the reply to {outgoing.method}."
                        )
                    )
            self._outgoing.clear()

    async def _dispatch(self, text: str) -> None:
        try:
            value = loads(text)
        except DecodeError as error:
            await self._reply(None, None, _Reply(error=RpcError(PARSE_ERROR, error.message)))
            return
        if isinstance(value, list):
            message = "I do not accept a batch; I received a JSON array."
            await self._reply(None, None, _Reply(error=RpcError(INVALID_REQUEST, message)))
            return
        if not isinstance(value, dict):
            await self._invalid(None, f"I found {describe(value)}")
            return
        if "method" in value:
            await self._incoming_message(value)
        elif "result" in value or "error" in value:
            self._response(value)
        else:
            await self._invalid(
                _usable_id(value), "I found an object with no method, result or error"
            )

    async def _invalid(self, request_id: RequestId | None, detail: str) -> None:
        message = f"I expected a valid JSON-RPC 2.0 request; {detail}."
        await self._reply(request_id, None, _Reply(error=RpcError(INVALID_REQUEST, message)))

    async def _incoming_message(self, value: dict[str, JsonValue]) -> None:
        request_id: RequestId | None = None
        if "id" in value:
            try:
                request_id = RequestId.from_json(value["id"])
            except DecodeError:
                await self._invalid(None, f"I found the id {describe(value['id'])}")
                return
        if value.get("jsonrpc") != "2.0":
            await self._invalid(
                request_id, f"I found the jsonrpc member {describe(value.get('jsonrpc'))}"
            )
            return
        method = value["method"]
        if not isinstance(method, str):
            await self._invalid(request_id, f"I found the method {describe(method)}")
            return
        params = value.get("params")
        if "params" in value and not isinstance(params, (dict, list)):
            await self._invalid(request_id, f"I found the params {describe(params)}")
            return
        if request_id is not None and request_id in self._incoming:
            await self._invalid(
                request_id, f"I found the id {request_id}, which an active call still uses"
            )
            return
        registration = self._handlers.get(method)
        cancel_rule = self.rules.cancel_rule(self.self_name, method)
        modeled = self.rules.rule(self.self_name, method) is not None
        if registration is None and not modeled:
            if request_id is not None:
                error = RpcError(METHOD_NOT_FOUND, f"I do not know method {method}.")
                await self._reply(request_id, None, _Reply(error=error))
            else:
                _LOG.warning("I dropped notification %s: I do not know the method.", method)
            return
        refusal = self.session.accept(self.self_name, method)
        if refusal is not None:
            if request_id is not None:
                error = RpcError(refusal.code, refusal.message)
                await self._reply(request_id, None, _Reply(error=error))
            else:
                _LOG.warning("I dropped notification %s: %s", method, refusal.message)
            return
        if cancel_rule is not None:
            self._cancel(cancel_rule, params)
        if registration is None or (
            request_id is not None and registration.kind is MethodKind.NOTIFICATION_ONLY
        ):
            if request_id is None:
                return
            if registration is None:
                error = RpcError(METHOD_NOT_FOUND, f"I do not know method {method}.")
            else:
                error = RpcError(
                    INVALID_REQUEST,
                    f"I expected a notification for method {method}; I received a request.",
                )
            self._incoming[request_id] = _Incoming(method, accepted=True)
            await self._reply(request_id, method, _Reply(error=error))
            return
        if request_id is None and registration.kind is MethodKind.REQUEST_ONLY:
            _LOG.warning("I dropped notification %s: the method needs a request ID.", method)
            return
        if request_id is None and not self._refers_to_active_call(method, params):
            return
        self._start(registration, method, request_id, params)

    def _refers_to_active_call(self, method: str, params: JsonValue | None) -> bool:
        reference = self._references.get(method)
        if reference is None:
            return True
        target = cancel_target(CancelRule(reference.id_member, reference.position), params)
        if target is not None and target in self._outgoing:
            return True
        _LOG.warning(
            "I dropped notification %s: it names no active call of mine (I found %s).",
            method,
            "no usable ID" if target is None else f"id {target}",
        )
        return False

    def _cancel(self, rule: CancelRule, params: JsonValue | None) -> None:
        target = cancel_target(rule, params)
        call = None if target is None else self._incoming.get(target)
        if call is None or call.task is None or call.task.done():
            return
        if call.cancel_code is None:
            call.cancel_code = rule.answer_code
            # A task that has not started gets the code when it starts. A
            # cancel before the first step would skip its handler of the
            # cancellation, and the call would get no reply.
            if call.started:
                call.task.cancel()

    def _start(
        self,
        registration: _Registration,
        method: str,
        request_id: RequestId | None,
        params: JsonValue | None,
    ) -> None:
        if request_id is not None:
            incoming = _Incoming(method, accepted=True)
            self._incoming[request_id] = incoming
            task = asyncio.create_task(self._handle(registration, method, request_id, params))
            incoming.task = task
        else:
            task = asyncio.create_task(self._handle(registration, method, None, params))
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def _handle(
        self,
        registration: _Registration,
        method: str,
        request_id: RequestId | None,
        params: JsonValue | None,
    ) -> None:
        _current_call.set(request_id)
        context = CallContext(self, method, request_id)
        incoming = None if request_id is None else self._incoming.get(request_id)
        if incoming is not None:
            incoming.started = True
            if incoming.cancel_code is not None:
                error = RpcError(incoming.cancel_code, f"I cancelled {method}.")
                await self._reply(request_id, method, _Reply(error=error))
                return
        try:
            result: JsonValue = await registration.handler(params, context)
            reply = _Reply(result=result if registration.answers else None)
        except asyncio.CancelledError:
            incoming = None if request_id is None else self._incoming.get(request_id)
            if incoming is None or incoming.cancel_code is None or self._closed:
                raise
            task = asyncio.current_task()
            if task is not None:
                task.uncancel()
            reply = _Reply(error=RpcError(incoming.cancel_code, f"I cancelled {method}."))
        except RpcError as error:
            reply = _Reply(error=error)
        except DecodeError as error:
            reply = _Reply(error=_decode_error(method, error.path, error.message))
        except ValidationError as error:
            path, message = _validation_detail(error)
            reply = _Reply(error=_decode_error(method, path, message))
        except Exception as error:
            _LOG.exception("I could not handle %s.", method)
            reply = _Reply(error=RpcError(INTERNAL_ERROR, f"I could not handle {method}: {error}"))
        if request_id is None:
            if reply.error is not None:
                _LOG.warning("I could not handle notification %s: %s", method, reply.error.message)
            return
        await self._reply(request_id, method, reply)

    async def _reply(self, request_id: RequestId | None, method: str | None, reply: _Reply) -> None:
        """Send a response. `method` is set when the reply answers an accepted call."""
        text = _response_text(request_id, reply)
        if text is None:
            error = RpcError(INTERNAL_ERROR, f"I could not write the result of {method} as JSON.")
            reply = _Reply(error=error)
            text = _response_text(request_id, reply)
            assert text is not None
        if self._conn is None:
            return
        async with self._send_lock:
            incoming = None if request_id is None else self._incoming.pop(request_id, None)
            if incoming is not None and incoming.accepted and method is not None:
                self.session.settle(
                    self.self_name, method, failed=reply.error is not None, result=reply.result
                )
            if self._closed:
                return
            try:
                await self._write(self._conn, text, related=request_id)
            except (ConnectionError, OSError) as error:
                _LOG.warning("I could not send the reply to %s: %s", method, error)

    def _response(self, value: dict[str, JsonValue]) -> None:
        raw = value.get("id")
        try:
            request_id = RequestId.from_json(raw)
        except DecodeError:
            _LOG.warning(
                "I received a reply with %s, which matches no call: %s", describe(raw), dumps(value)
            )
            return
        outgoing = self._outgoing.pop(request_id, None)
        if outgoing is None:
            _LOG.warning("I received a reply with id %s, which matches no call.", request_id)
            return
        error = value.get("error")
        failed = error is not None
        if not failed and "result" not in value:
            if not outgoing.future.done():
                outgoing.future.set_exception(
                    RpcError(
                        INTERNAL_ERROR,
                        f"I expected a result or an error in the reply to {outgoing.method}; "
                        "I found neither.",
                    )
                )
            return
        result = None if failed else value.get("result")
        if outgoing.accepted:
            self.session.settle(self.remote_name, outgoing.method, failed=failed, result=result)
        if outgoing.future.done():
            return
        if failed:
            outgoing.future.set_exception(_error_from_json(outgoing.method, error))
        else:
            outgoing.future.set_result(result)


def _usable_id(value: dict[str, JsonValue]) -> RequestId | None:
    try:
        return RequestId.from_json(value.get("id"))
    except DecodeError:
        return None


def _decode_error(method: str, path: str, message: str) -> RpcError:
    return RpcError(
        INVALID_PARAMS, f"I could not decode {method} params at {path or '/'}: {message}"
    )


def _validation_detail(error: ValidationError) -> tuple[str, str]:
    errors = error.errors(include_url=False)
    if not errors:
        return "", str(error)
    first = errors[0]
    path = "".join("/" + str(step).replace("~", "~0").replace("/", "~1") for step in first["loc"])
    return path, f"{first['msg']}."


def _error_from_json(method: str, error: JsonValue) -> RpcError:
    if isinstance(error, dict):
        code = error.get("code")
        message = error.get("message")
        if isinstance(code, int) and not isinstance(code, bool) and isinstance(message, str):
            return RpcError(code, message, error.get("data"))
    return RpcError(
        INTERNAL_ERROR,
        f"I expected an error object with an integer code in the reply to {method}; "
        f"I found {describe(error)}.",
    )


def _response_text(request_id: RequestId | None, reply: _Reply) -> str | None:
    message: dict[str, JsonValue] = {
        "jsonrpc": "2.0",
        "id": None if request_id is None else request_id.to_json(),
    }
    if reply.error is not None:
        message["error"] = reply.error.to_json()
    else:
        message["result"] = reply.result
    try:
        return dumps(message)
    except (TypeError, ValueError):
        return None

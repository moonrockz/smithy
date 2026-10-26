"""The FastAPI integration: `POST /rpc` and `WebSocket /ws` for a peer.

It needs FastAPI and uvicorn.

`POST /rpc` follows the Streamable HTTP style:

- The first post without `Smithy-Session-Id` opens a session with a new peer
  from the peer factory. Each response has the header. A post with an
  unknown session ID gets 404.
- A posted request gets 200 `text/event-stream`. The stream starts with the
  comment `: open`. Each event is `event: message` and `data: <message>`.
  The notifications and requests of the handler of that request come first,
  then the response, then the stream ends.
- A message of the peer that belongs to no open stream goes on the latest
  open stream of the session. When no stream is open, the session keeps it
  for the next stream.
- A posted notification or response gets 202 with an empty body.
- Text that is not JSON, a batch or a value that is not an object gets 200
  `application/json` with the error (-32700 or -32600, ID null). The session
  does not see it.

`WebSocket /ws` carries one message in each text frame. Each WebSocket
connection has a new peer.
"""

from __future__ import annotations

import asyncio
import contextlib
import sys
import uuid
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass

import uvicorn
from fastapi import FastAPI, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse

from .connection import SESSION_HEADER
from .errors import INVALID_REQUEST, PARSE_ERROR, DecodeError
from .ids import RequestId
from .json_codec import JsonValue, describe, dumps, loads
from .peer import Peer

PeerFactory = Callable[[], Peer]
"""Makes a new peer, with its handlers, for each session."""


def _is_response_to(text: str, request_id: RequestId) -> bool:
    try:
        value = loads(text)
    except DecodeError:
        return False
    if not isinstance(value, dict) or "method" in value or "id" not in value:
        return False
    try:
        return RequestId.from_json(value["id"]) == request_id
    except DecodeError:
        return False


class HttpSessionConnection:
    """The connection of the peer of one HTTP session."""

    def __init__(self) -> None:
        self._inbox: asyncio.Queue[str | None] = asyncio.Queue()
        self._streams: dict[RequestId, asyncio.Queue[str | None]] = {}
        self._held: list[str] = []
        self._closed = False

    def is_open(self, request_id: RequestId) -> bool:
        """Whether the stream of the request is open."""
        return request_id in self._streams

    def open_stream(self, request_id: RequestId) -> asyncio.Queue[str | None]:
        """Open the stream of a posted request. It gets the messages that the session kept."""
        queue: asyncio.Queue[str | None] = asyncio.Queue()
        self._streams[request_id] = queue
        for text in self._held:
            queue.put_nowait(text)
        self._held.clear()
        return queue

    def deliver(self, text: str) -> None:
        """Give a posted message to the peer."""
        self._inbox.put_nowait(text)

    async def receive(self) -> str | None:
        if self._closed and self._inbox.empty():
            return None
        return await self._inbox.get()

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        if self._closed:
            raise ConnectionError("I cannot send: the HTTP session is closed.")
        if related is not None and related in self._streams:
            target: RequestId | None = related
        elif self._streams:
            target = next(reversed(self._streams))
        else:
            target = None
        if target is None:
            self._held.append(text)
            return
        queue = self._streams[target]
        queue.put_nowait(text)
        if related == target and _is_response_to(text, target):
            queue.put_nowait(None)
            del self._streams[target]

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._inbox.put_nowait(None)
        for queue in self._streams.values():
            queue.put_nowait(None)
        self._streams.clear()


@dataclass(slots=True)
class _Session:
    conn: HttpSessionConnection
    peer: Peer
    task: asyncio.Task[None]


class _WebSocketConnection:
    def __init__(self, socket: WebSocket) -> None:
        self._socket = socket

    async def receive(self) -> str | None:
        try:
            return await self._socket.receive_text()
        except (WebSocketDisconnect, RuntimeError):
            return None

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        try:
            await self._socket.send_text(text)
        except (WebSocketDisconnect, RuntimeError) as error:
            raise ConnectionError(f"I cannot send: the WebSocket closed ({error}).") from error

    async def close(self) -> None:
        with contextlib.suppress(RuntimeError):
            await self._socket.close()


def _json_error(code: int, message: str, request_id: JsonValue = None) -> Response:
    body = dumps({"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}})
    return Response(content=body, media_type="application/json")


async def _events(queue: asyncio.Queue[str | None]) -> AsyncIterator[bytes]:
    yield b": open\n\n"
    while True:
        text = await queue.get()
        if text is None:
            return
        yield b"event: message\ndata: " + text.encode("utf-8") + b"\n\n"


def create_app(peer_factory: PeerFactory) -> FastAPI:
    """Give a FastAPI app with `POST /rpc` and `WebSocket /ws` for the peers of `peer_factory`."""
    app = FastAPI()
    sessions: dict[str, _Session] = {}

    @app.post("/rpc")
    async def rpc(request: Request) -> Response:  # pyright: ignore[reportUnusedFunction]
        session_id = request.headers.get(SESSION_HEADER)
        session = None
        if session_id is not None:
            session = sessions.get(session_id)
            if session is None:
                return Response(status_code=404)
        raw = await request.body()
        try:
            text = raw.decode("utf-8")
            value = loads(text)
        except UnicodeDecodeError as error:
            return _json_error(PARSE_ERROR, f"I could not parse the message as JSON: {error}.")
        except DecodeError as error:
            return _json_error(PARSE_ERROR, error.message)
        if isinstance(value, list):
            return _json_error(INVALID_REQUEST, "I do not accept a batch; I received a JSON array.")
        if not isinstance(value, dict):
            return _json_error(
                INVALID_REQUEST,
                f"I expected a valid JSON-RPC 2.0 request; I found {describe(value)}.",
            )
        request_id: RequestId | None = None
        if "method" in value and "id" in value:
            try:
                request_id = RequestId.from_json(value["id"])
            except DecodeError:
                return _json_error(
                    INVALID_REQUEST,
                    "I expected a valid JSON-RPC 2.0 request; "
                    f"I found the id {describe(value['id'])}.",
                )
        if session is None:
            session_id = uuid.uuid4().hex
            conn = HttpSessionConnection()
            peer = peer_factory()
            session = _Session(conn, peer, asyncio.create_task(peer.run(conn)))
            sessions[session_id] = session
        assert session_id is not None
        headers = {SESSION_HEADER: session_id}
        if request_id is None:
            session.conn.deliver(text)
            return Response(status_code=202, headers=headers)
        if session.conn.is_open(request_id):
            return _json_error(
                INVALID_REQUEST,
                f"I expected a valid JSON-RPC 2.0 request; I found the id {request_id}, "
                "which an active call still uses.",
                request_id.to_json(),
            )
        queue = session.conn.open_stream(request_id)
        session.conn.deliver(text)
        return StreamingResponse(
            _events(queue),
            media_type="text/event-stream",
            headers={**headers, "Cache-Control": "no-cache"},
        )

    @app.websocket("/ws")
    async def ws(socket: WebSocket) -> None:  # pyright: ignore[reportUnusedFunction]
        await socket.accept()
        await peer_factory().run(_WebSocketConnection(socket))

    return app


class RunningServer:
    """A uvicorn server that runs in a task. `port` is the port that it listens on."""

    def __init__(self, server: uvicorn.Server, task: asyncio.Task[None], port: int) -> None:
        self._server = server
        self._task = task
        self.port = port

    async def wait(self) -> None:
        """Wait until the server stops."""
        await self._task

    async def stop(self) -> None:
        """Stop the server and wait until it stops."""
        self._server.should_exit = True
        await self._task


async def start_server(
    port: int, peer_factory: PeerFactory, *, host: str = "127.0.0.1"
) -> RunningServer:
    """Start the app of `peer_factory` on `host:port`. Port 0 selects a free port."""
    config = uvicorn.Config(
        create_app(peer_factory),
        host=host,
        port=port,
        log_level="warning",
        access_log=False,
        ws="websockets-sansio",
        lifespan="off",
    )
    server = uvicorn.Server(config)
    task = asyncio.create_task(server.serve())
    while not server.started:
        if task.done():
            await task
            raise OSError(f"I could not start the server on {host}:{port}.")
        await asyncio.sleep(0.01)
    sockets = [sock for listener in server.servers for sock in listener.sockets]
    actual = int(sockets[0].getsockname()[1]) if sockets else port
    return RunningServer(server, task, actual)


async def serve(port: int, peer_factory: PeerFactory, *, host: str = "127.0.0.1") -> None:
    """Serve the app of `peer_factory` until the process stops.

    When the server is ready, I write `listening N` to stderr.
    """
    running = await start_server(port, peer_factory, host=host)
    sys.stderr.write(f"listening {running.port}\n")
    sys.stderr.flush()
    await running.wait()

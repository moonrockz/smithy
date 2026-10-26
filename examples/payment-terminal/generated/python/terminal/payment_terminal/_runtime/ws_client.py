"""The WebSocket client transport: one message in each text frame. It needs `websockets`."""

from __future__ import annotations

from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed

from .ids import RequestId
from .stdio import MAX_FRAME_BYTES


class WsConnection:
    """A connection to a JSON-RPC peer at a WebSocket endpoint."""

    def __init__(self, socket: ClientConnection) -> None:
        self._socket = socket

    async def receive(self) -> str | None:
        try:
            message = await self._socket.recv()
        except ConnectionClosed:
            return None
        return message if isinstance(message, str) else message.decode("utf-8")

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        try:
            await self._socket.send(text)
        except ConnectionClosed as error:
            raise ConnectionError(f"I cannot send: the WebSocket closed ({error}).") from error

    async def close(self) -> None:
        await self._socket.close()


async def ws_connect(url: str) -> WsConnection:
    """Open a WebSocket connection to `url`, such as `ws://127.0.0.1:8080/ws`."""
    if not (url.startswith("ws://") or url.startswith("wss://")):
        raise ValueError(f"I expected a ws:// or wss:// URL; I found {url!r}.")
    socket = await connect(url, max_size=MAX_FRAME_BYTES)
    return WsConnection(socket)

"""The connection contract of a peer, and an in-memory connection pair."""

from __future__ import annotations

import asyncio
from typing import Protocol

from .ids import RequestId

SESSION_HEADER = "Smithy-Session-Id"
"""The HTTP header that ties the posts of one session together."""


class Connection(Protocol):
    """A transport that carries one JSON-RPC message per `send` and `receive`."""

    async def receive(self) -> str | None:
        """Give the text of the next message, or None when the remote peer closed."""
        ...

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        """Send the text of one message.

        `related` is the ID of the incoming call that this message belongs to:
        the call that a response answers, or the call whose handler sends a
        callback or a notification. An HTTP server uses it to put the message
        on the stream of that call.
        """
        ...

    async def close(self) -> None:
        """Close the connection. Later `receive` calls give None."""
        ...


class MemoryConnection:
    """One end of an in-memory connection pair, for tests."""

    def __init__(self, inbox: asyncio.Queue[str | None], outbox: asyncio.Queue[str | None]) -> None:
        self._inbox = inbox
        self._outbox = outbox
        self._closed = False
        self.sent: list[tuple[str, RequestId | None]] = []

    async def receive(self) -> str | None:
        if self._closed and self._inbox.empty():
            return None
        return await self._inbox.get()

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        if self._closed:
            raise ConnectionError("I cannot send on a closed memory connection.")
        self.sent.append((text, related))
        await self._outbox.put(text)

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        await self._outbox.put(None)
        await self._inbox.put(None)


def memory_pair() -> tuple[MemoryConnection, MemoryConnection]:
    """Give two connected in-memory ends: what one end sends, the other receives."""
    left: asyncio.Queue[str | None] = asyncio.Queue()
    right: asyncio.Queue[str | None] = asyncio.Queue()
    return MemoryConnection(left, right), MemoryConnection(right, left)

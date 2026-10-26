"""The HTTP client transport, in the Streamable HTTP style. It needs `httpx`.

- The client posts each message to the endpoint, such as `http://127.0.0.1:N/rpc`,
  on a new connection. It posts the next message only after the response
  headers of the last post arrive, so the server receives the messages in order.
- The server answers a request with `text/event-stream`: each event carries one
  message. The stream ends after the response to the request. The client also
  accepts a response as `application/json`.
- The server answers a notification or a response with 202.
- The server sets `Smithy-Session-Id` on its responses. The client sends it on
  each later post.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator

import httpx

from .connection import SESSION_HEADER, CallLost
from .errors import DecodeError
from .ids import RequestId
from .json_codec import loads

_LOG = logging.getLogger(__name__)

MAX_EVENT_BYTES = 16 * 1024 * 1024
"""The most bytes of one event-stream line, of the joined data of one event,
and of one JSON response body. It is the input limit of the message validator,
so a larger message could not pass a transcript check."""


class StreamLimitError(ConnectionError):
    """A response of the server is larger than the limit of the client."""


async def read_events(
    chunks: AsyncIterator[bytes], *, limit: int = MAX_EVENT_BYTES
) -> AsyncIterator[str]:
    """Give the data of each event of an event stream.

    The reader keeps at most `limit` bytes of one line and of the data of one
    event, so a server that holds an event open cannot grow the memory of the
    client without bound.
    """
    data: list[str] = []
    data_bytes = 0
    pending = bytearray()

    def handle(raw: bytes) -> str | None:
        nonlocal data_bytes
        line = raw.decode("utf-8", errors="replace").removesuffix("\r")
        if line == "":
            if not data:
                return None
            event = "\n".join(data)
            data.clear()
            data_bytes = 0
            return event
        if line.startswith(":"):
            return None
        name, _, value = line.partition(":")
        if name == "data":
            data_bytes += len(raw) + 1
            if data_bytes > limit:
                raise StreamLimitError(
                    "I expected the data of one event-stream event to be at most "
                    f"{limit} bytes, found more."
                )
            data.append(value.removeprefix(" "))
        return None

    async for chunk in chunks:
        start = 0
        while (end := chunk.find(b"\n", start)) >= 0:
            pending += chunk[start:end]
            event = handle(bytes(pending))
            pending.clear()
            if event is not None:
                yield event
            start = end + 1
        pending += chunk[start:]
        if len(pending) > limit:
            raise StreamLimitError(
                f"I expected an event-stream line of at most {limit} bytes, found more."
            )
    if pending:
        event = handle(bytes(pending))
        if event is not None:
            yield event
    if data:
        yield "\n".join(data)


async def read_body(chunks: AsyncIterator[bytes], *, limit: int = MAX_EVENT_BYTES) -> str:
    """Read a JSON response body of at most `limit` bytes."""
    body = bytearray()
    async for chunk in chunks:
        body += chunk
        if len(body) > limit:
            raise StreamLimitError(
                f"I expected a JSON response body of at most {limit} bytes, found more."
            )
    return body.decode("utf-8")


class HttpClientConnection:
    """A connection to a JSON-RPC peer at an HTTP endpoint."""

    def __init__(
        self, url: str, client: httpx.AsyncClient | None = None, *, limit: int = MAX_EVENT_BYTES
    ) -> None:
        self.url = url
        self._limit = limit
        self.session_id: str | None = None
        self._client = (
            client
            if client is not None
            else httpx.AsyncClient(
                timeout=httpx.Timeout(None, connect=10.0),
                limits=httpx.Limits(max_keepalive_connections=0),
            )
        )
        self._inbox: asyncio.Queue[str | CallLost | None] = asyncio.Queue()
        self._order = asyncio.Lock()
        self._readers: set[asyncio.Task[None]] = set()
        self._closed = False
        self._shut = False

    async def receive(self) -> str | None:
        if self._closed and self._inbox.empty():
            return None
        item = await self._inbox.get()
        if isinstance(item, CallLost):
            raise item
        return item

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        async with self._order:
            if self._closed:
                raise ConnectionError(f"I cannot post to {self.url}: the connection is closed.")
            headers = {
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
            }
            if self.session_id is not None:
                headers[SESSION_HEADER] = self.session_id
            request = self._client.build_request(
                "POST", self.url, content=text.encode("utf-8"), headers=headers
            )
            try:
                response = await self._client.send(request, stream=True)
            except httpx.HTTPError as error:
                raise ConnectionError(f"I could not post to {self.url}: {error}") from error
            found = response.headers.get(SESSION_HEADER)
            if found is not None and self.session_id is None:
                self.session_id = found
            status = response.status_code
            if status == 202:
                await response.aclose()
                return
            if status != 200:
                await response.aclose()
                if status == 404:
                    raise ConnectionError(
                        f"I posted to {self.url} with session {self.session_id}; "
                        "the server does not know the session (404)."
                    )
                raise ConnectionError(
                    f"I expected status 200 or 202 from {self.url}; I received {status}."
                )
            kind = response.headers.get("content-type", "")
            if kind.startswith("text/event-stream"):
                task = asyncio.create_task(self._read_events(response, _request_id(text)))
                self._readers.add(task)
                task.add_done_callback(self._readers.discard)
                return
            try:
                body = await read_body(response.aiter_bytes(), limit=self._limit)
            finally:
                await response.aclose()
            if body.strip():
                self._inbox.put_nowait(body)

    async def _read_events(self, response: httpx.Response, request_id: RequestId | None) -> None:
        """Read the events of the stream of a request.

        When the stream ends before the response to the request, the peer
        first dispatches the messages that the stream delivered. Then it gets
        `CallLost` and fails that call. The connection stays open.
        """
        data: list[str] = []
        answered = request_id is None
        problem = "the stream ended before the response"

        def deliver() -> None:
            nonlocal answered
            message = "\n".join(data)
            data.clear()
            if not answered and _answers(message, request_id):
                answered = True
            self._inbox.put_nowait(message)

        try:
            async for event in read_events(response.aiter_bytes(), limit=self._limit):
                data.append(event)
                deliver()
        except (httpx.HTTPError, StreamLimitError) as error:
            problem = f"the stream failed: {error}"
        finally:
            await response.aclose()
        if not answered and request_id is not None and not self._closed:
            _LOG.warning(
                "I lost the event stream of request %s from %s: %s.", request_id, self.url, problem
            )
            self._inbox.put_nowait(CallLost(request_id, problem))

    async def close(self) -> None:
        if self._shut:
            return
        self._shut = True
        self._closed = True
        for task in list(self._readers):
            task.cancel()
        for task in list(self._readers):
            with contextlib.suppress(asyncio.CancelledError):
                await task
        self._inbox.put_nowait(None)
        await self._client.aclose()


def _request_id(text: str) -> RequestId | None:
    """The ID of a request message, or None for any other message."""
    try:
        value = loads(text)
    except DecodeError:
        return None
    if not isinstance(value, dict) or "method" not in value or "id" not in value:
        return None
    try:
        return RequestId.from_json(value["id"])
    except DecodeError:
        return None


def _answers(text: str, request_id: RequestId | None) -> bool:
    """Whether a message is the response to the request."""
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


async def http_connect(url: str) -> HttpClientConnection:
    """Give a connection to the JSON-RPC endpoint at `url`, such as `http://127.0.0.1:8080/rpc`.

    The first post opens the session.
    """
    if not (url.startswith("http://") or url.startswith("https://")):
        raise ValueError(f"I expected an http:// or https:// URL; I found {url!r}.")
    return HttpClientConnection(url)

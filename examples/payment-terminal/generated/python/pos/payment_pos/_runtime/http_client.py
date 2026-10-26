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

import httpx

from .connection import SESSION_HEADER
from .ids import RequestId

_LOG = logging.getLogger(__name__)


class HttpClientConnection:
    """A connection to a JSON-RPC peer at an HTTP endpoint."""

    def __init__(self, url: str, client: httpx.AsyncClient | None = None) -> None:
        self.url = url
        self.session_id: str | None = None
        self._client = (
            client
            if client is not None
            else httpx.AsyncClient(
                timeout=httpx.Timeout(None, connect=10.0),
                limits=httpx.Limits(max_keepalive_connections=0),
            )
        )
        self._inbox: asyncio.Queue[str | None] = asyncio.Queue()
        self._order = asyncio.Lock()
        self._readers: set[asyncio.Task[None]] = set()
        self._closed = False

    async def receive(self) -> str | None:
        if self._closed and self._inbox.empty():
            return None
        return await self._inbox.get()

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
                task = asyncio.create_task(self._read_events(response))
                self._readers.add(task)
                task.add_done_callback(self._readers.discard)
                return
            try:
                body = (await response.aread()).decode("utf-8")
            finally:
                await response.aclose()
            if body.strip():
                self._inbox.put_nowait(body)

    async def _read_events(self, response: httpx.Response) -> None:
        data: list[str] = []
        try:
            async for raw in response.aiter_lines():
                line = raw.rstrip("\r\n")
                if line == "":
                    if data:
                        self._inbox.put_nowait("\n".join(data))
                        data = []
                    continue
                if line.startswith(":"):
                    continue
                name, _, value = line.partition(":")
                if name == "data":
                    data.append(value.removeprefix(" "))
            if data:
                self._inbox.put_nowait("\n".join(data))
        except httpx.HTTPError as error:
            _LOG.warning("I lost an event stream from %s: %s", self.url, error)
        finally:
            await response.aclose()

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        for task in list(self._readers):
            task.cancel()
        for task in list(self._readers):
            with contextlib.suppress(asyncio.CancelledError):
                await task
        self._inbox.put_nowait(None)
        await self._client.aclose()


async def http_connect(url: str) -> HttpClientConnection:
    """Give a connection to the JSON-RPC endpoint at `url`, such as `http://127.0.0.1:8080/rpc`.

    The first post opens the session.
    """
    if not (url.startswith("http://") or url.startswith("https://")):
        raise ValueError(f"I expected an http:// or https:// URL; I found {url!r}.")
    return HttpClientConnection(url)

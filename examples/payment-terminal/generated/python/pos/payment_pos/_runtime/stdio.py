"""The stdio transport: Content-Length framing, as in LSP.

Each message is `Content-Length: N\\r\\n\\r\\n` and then N bytes of UTF-8 JSON.
A reader ignores the headers that it does not know, such as Content-Type.
"""

from __future__ import annotations

import asyncio
import contextlib
import os
import sys
import threading
from collections.abc import Sequence
from typing import BinaryIO

from .ids import RequestId

MAX_FRAME_BYTES = 64 * 1024 * 1024
"""The largest message body that a reader accepts."""

_MAX_HEADER_BYTES = 8192


def encode_frame(text: str) -> bytes:
    """Give the framed bytes of one message."""
    body = text.encode("utf-8")
    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body


class FramingError(ConnectionError):
    """The byte stream does not hold a valid Content-Length frame."""


class _HeaderParser:
    def __init__(self) -> None:
        self.length: int | None = None
        self.size = 0

    def line(self, raw: bytes) -> bool:
        """Read one header line. Gives true at the blank line that ends the headers."""
        self.size += len(raw)
        if self.size > _MAX_HEADER_BYTES:
            raise FramingError(f"I expected at most {_MAX_HEADER_BYTES} header bytes in a frame.")
        text = raw.decode("ascii", errors="replace").rstrip("\r\n")
        if text == "":
            if self.length is None:
                raise FramingError("I expected a Content-Length header; I found a blank line.")
            return True
        name, separator, value = text.partition(":")
        if not separator:
            raise FramingError(f"I expected a header with a colon; I found {text!r}.")
        if name.strip().lower() == "content-length":
            digits = value.strip()
            if not digits.isdigit():
                raise FramingError(f"I expected a decimal Content-Length; I found {digits!r}.")
            length = int(digits)
            if length > MAX_FRAME_BYTES:
                raise FramingError(
                    f"I expected a Content-Length of at most {MAX_FRAME_BYTES}; I found {length}."
                )
            self.length = length
        return False


async def read_frame(reader: asyncio.StreamReader) -> str | None:
    """Read one message from an asyncio stream. Gives None at the end of the stream."""
    parser = _HeaderParser()
    first = True
    while True:
        raw = await reader.readline()
        if raw == b"":
            if first:
                return None
            raise FramingError("I reached the end of the stream inside the headers of a frame.")
        first = False
        if parser.line(raw):
            break
    assert parser.length is not None
    try:
        body = await reader.readexactly(parser.length)
    except asyncio.IncompleteReadError as error:
        raise FramingError(
            f"I expected {parser.length} body bytes; the stream ended after {len(error.partial)}."
        ) from None
    return _decode(body)


def read_frame_blocking(stream: BinaryIO) -> str | None:
    """Read one message from a blocking binary stream. Gives None at the end of the stream."""
    parser = _HeaderParser()
    first = True
    while True:
        raw = stream.readline(_MAX_HEADER_BYTES + 1)
        if raw == b"":
            if first:
                return None
            raise FramingError("I reached the end of the stream inside the headers of a frame.")
        first = False
        if parser.line(raw):
            break
    assert parser.length is not None
    chunks: list[bytes] = []
    remaining = parser.length
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            raise FramingError(
                f"I expected {parser.length} body bytes; "
                f"the stream ended after {parser.length - remaining}."
            )
        chunks.append(chunk)
        remaining -= len(chunk)
    return _decode(b"".join(chunks))


def _decode(body: bytes) -> str:
    try:
        return body.decode("utf-8")
    except UnicodeDecodeError as error:
        raise FramingError(f"I expected a UTF-8 message body: {error}.") from None


class StreamConnection:
    """A framed connection on an asyncio stream pair."""

    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self._reader = reader
        self._writer = writer
        self._lock = asyncio.Lock()
        self._closed = False

    async def receive(self) -> str | None:
        if self._closed:
            return None
        return await read_frame(self._reader)

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        async with self._lock:
            if self._closed:
                raise ConnectionError("I cannot send on a closed stream connection.")
            self._writer.write(encode_frame(text))
            await self._writer.drain()

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._writer.close()
        with contextlib.suppress(ConnectionError, OSError):
            await self._writer.wait_closed()


class StdioConnection:
    """A framed connection on the stdin and stdout of this process.

    A daemon thread reads stdin, so the transport works with pipes, files and
    terminals on every platform. Nothing else may write to stdout.
    """

    def __init__(self, stdin: BinaryIO | None = None, stdout: BinaryIO | None = None) -> None:
        self._stdin = stdin if stdin is not None else sys.stdin.buffer
        self._stdout = stdout if stdout is not None else sys.stdout.buffer
        self._queue: asyncio.Queue[str | BaseException | None] | None = None
        self._lock = threading.Lock()
        self._closed = False

    def _start(self) -> asyncio.Queue[str | BaseException | None]:
        if self._queue is not None:
            return self._queue
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[str | BaseException | None] = asyncio.Queue()
        self._queue = queue

        def pump() -> None:
            while True:
                try:
                    item: str | BaseException | None = read_frame_blocking(self._stdin)
                except (OSError, ValueError, FramingError) as error:
                    item = error
                try:
                    loop.call_soon_threadsafe(queue.put_nowait, item)
                except RuntimeError:
                    return
                if not isinstance(item, str):
                    return

        threading.Thread(target=pump, name="stdio-reader", daemon=True).start()
        return queue

    async def receive(self) -> str | None:
        if self._closed:
            return None
        item = await self._start().get()
        if isinstance(item, BaseException):
            raise item
        return item

    async def send(self, text: str, *, related: RequestId | None = None) -> None:
        frame = encode_frame(text)
        with self._lock:
            if self._closed:
                raise ConnectionError("I cannot send on a closed stdio connection.")
            self._stdout.write(frame)
            self._stdout.flush()

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        with contextlib.suppress(OSError, ValueError):
            self._stdout.flush()
        if self._queue is not None:
            self._queue.put_nowait(None)


def stdio_connection() -> StdioConnection:
    """Give the framed connection on stdin and stdout."""
    return StdioConnection()


class ProcessConnection(StreamConnection):
    """A framed connection on the stdin and stdout of a child process.

    The child writes its diagnostics to the stderr of this process.
    """

    def __init__(self, process: asyncio.subprocess.Process) -> None:
        assert process.stdout is not None and process.stdin is not None
        super().__init__(process.stdout, process.stdin)
        self.process = process

    exit_wait = 5.0
    """The seconds that `close` waits for the child to exit before it kills the child."""

    async def close(self) -> None:
        """Close the stdin of the child, then wait for it to exit. Kill it after `exit_wait`."""
        await super().close()
        try:
            await asyncio.wait_for(self.process.wait(), self.exit_wait)
        except TimeoutError:
            with contextlib.suppress(ProcessLookupError):
                self.process.kill()
            await self.process.wait()

    async def wait(self) -> int:
        """Wait for the child to exit, and give its exit code."""
        return await self.process.wait()


async def spawn_stdio(
    argv: Sequence[str], *, cwd: str | os.PathLike[str] | None = None
) -> ProcessConnection:
    """Start a child process and give the framed connection on its stdin and stdout.

    The child gets the stderr of this process. `cwd` is its working directory.
    """
    if not argv:
        raise ValueError("I expected a command to start; I found an empty argv.")
    process = await asyncio.create_subprocess_exec(
        *argv,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=None,
        cwd=cwd,
    )
    return ProcessConnection(process)

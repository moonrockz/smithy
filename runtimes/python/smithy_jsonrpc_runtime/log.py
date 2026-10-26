"""The transcript log: one JSON line for each message that a peer sends or receives.

Each line is `{"dir":"send","message":<message>}` or `{"dir":"recv",...}`,
from the view of the peer that writes it. The message is the exact JSON text
on the wire. `smithy validate rpc transcript --log-preset dir-message` reads it.
"""

from __future__ import annotations

from pathlib import Path
from types import TracebackType
from typing import Literal, TextIO

from .errors import DecodeError
from .json_codec import dumps, loads

Direction = Literal["send", "recv"]


class TranscriptLog:
    """A dir-message JSONL transcript log in a file."""

    def __init__(self, stream: TextIO) -> None:
        self._stream = stream

    @staticmethod
    def open(path: str | Path) -> TranscriptLog:
        """Create or replace the log file at `path`."""
        return TranscriptLog(Path(path).open("w", encoding="utf-8", newline="\n"))

    def record(self, direction: Direction, text: str) -> None:
        """Write one line for a message. The line is written through at once."""
        self._stream.write(f'{{"dir":"{direction}","message":{_one_line(text)}}}\n')
        self._stream.flush()

    def close(self) -> None:
        """Close the file."""
        self._stream.close()

    def __enter__(self) -> TranscriptLog:
        return self

    def __exit__(
        self,
        kind: type[BaseException] | None,
        error: BaseException | None,
        trace: TracebackType | None,
    ) -> None:
        self.close()


def _one_line(text: str) -> str:
    """Give the message text when it is one line of JSON.

    A message with a line break is written again in compact form, with the same
    values. Text that is not JSON is written as a JSON string.
    """
    try:
        value = loads(text)
    except DecodeError:
        return dumps(text)
    if "\n" in text or "\r" in text:
        return dumps(value)
    return text.strip(" \t")

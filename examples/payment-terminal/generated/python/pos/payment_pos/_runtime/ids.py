"""JSON-RPC request IDs."""

from __future__ import annotations

from dataclasses import dataclass

from .errors import DecodeError
from .json_codec import JsonValue, describe, dumps


@dataclass(frozen=True, slots=True)
class RequestId:
    """A request ID: a string or an integer, kept exactly.

    The string "1" and the integer 1 are different IDs.
    """

    value: int | str

    def __post_init__(self) -> None:
        if isinstance(self.value, bool) or not isinstance(self.value, (int, str)):  # pyright: ignore[reportUnnecessaryIsInstance]
            raise TypeError(f"I expected a string or integer request ID; I found {self.value!r}.")

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, RequestId):
            return NotImplemented
        return type(self.value) is type(other.value) and self.value == other.value

    def __hash__(self) -> int:
        return hash((type(self.value).__name__, self.value))

    def to_json(self) -> JsonValue:
        """Give the ID as a JSON value."""
        return self.value

    @staticmethod
    def from_json(value: JsonValue, *, path: str = "/id") -> RequestId:
        """Read an ID. Raises `DecodeError` for any value except a string or an integer."""
        if isinstance(value, bool) or not isinstance(value, (int, str)):
            raise DecodeError(
                path=path,
                message=f"I expected a string or integer request ID; I found {describe(value)}.",
            )
        return RequestId(value)

    def __str__(self) -> str:
        return dumps(self.value)

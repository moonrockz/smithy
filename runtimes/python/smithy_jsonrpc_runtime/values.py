"""Exact value types for generated Pydantic models.

- `BigDecimal` is a `decimal.Decimal` that accepts only a JSON number.
- `BigInteger` is an `int` that accepts only a JSON integer.
- `Blob` is `bytes` that is base64 text on the wire.
- `Timestamp` keeps the JSON value of a timestamp exactly.
"""

from __future__ import annotations

import base64
import binascii
import email.utils
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from enum import Enum
from typing import Annotated, Any, cast

from pydantic import BeforeValidator, GetCoreSchemaHandler, PlainSerializer
from pydantic_core import core_schema

from .errors import DecodeError
from .json_codec import JsonValue, describe


def decode_decimal(value: object, *, path: str = "") -> Decimal:
    """Read a JSON number as an exact `Decimal`. A float, a string or a boolean is an error."""
    if isinstance(value, Decimal):
        return value
    if isinstance(value, int) and not isinstance(value, bool):
        return Decimal(value)
    raise DecodeError(path=path, message=f"I expected a JSON number; I found {_name(value)}.")


def decode_integer(value: object, *, path: str = "") -> int:
    """Read a JSON integer exactly. A number with a fraction, such as 1.5, is an error."""
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, Decimal) and value.is_finite() and value == value.to_integral_value():
        return int(value)
    raise DecodeError(path=path, message=f"I expected a JSON integer; I found {_name(value)}.")


def encode_blob(data: bytes) -> str:
    """Give the standard base64 text of the bytes, with padding and no line breaks."""
    return base64.b64encode(data).decode("ascii")


def decode_blob(value: object, *, path: str = "") -> bytes:
    """Read standard base64 text. Raises `DecodeError` for other text or values."""
    if isinstance(value, (bytes, bytearray)):
        return bytes(value)
    if not isinstance(value, str):
        raise DecodeError(path=path, message=f"I expected base64 text; I found {_name(value)}.")
    try:
        return base64.b64decode(value.encode("ascii"), validate=True)
    except (binascii.Error, UnicodeEncodeError):
        raise DecodeError(
            path=path, message=f"I expected base64 text; I found {value!r}."
        ) from None


def _name(value: object) -> str:
    if value is None or isinstance(value, (bool, int, Decimal, float, str, list, dict)):
        return describe(cast("JsonValue", value))
    return f"a {type(value).__name__}"


def _pydantic_value_error(function: Any) -> Any:
    def validate(value: object) -> object:
        try:
            return function(value)
        except DecodeError as error:
            raise ValueError(error.message) from None

    return validate


BigDecimal = Annotated[Decimal, BeforeValidator(_pydantic_value_error(decode_decimal))]
"""A Smithy bigDecimal. The JSON writer keeps its exact text."""

BigInteger = Annotated[int, BeforeValidator(_pydantic_value_error(decode_integer))]
"""A Smithy bigInteger or long. It is never a float."""

Blob = Annotated[
    bytes,
    BeforeValidator(_pydantic_value_error(decode_blob)),
    PlainSerializer(encode_blob, return_type=str),
]
"""A Smithy blob: bytes in Python, base64 text in JSON."""


class TimestampFormat(Enum):
    """The wire formats of a Smithy timestamp."""

    EPOCH_SECONDS = "epoch-seconds"
    DATE_TIME = "date-time"
    HTTP_DATE = "http-date"


@dataclass(frozen=True, slots=True)
class Timestamp:
    """A timestamp that keeps its JSON value: an exact number of epoch seconds, or text.

    Use `Timestamp.from_json` to read a value in a known format, and `to_json`
    to write it back unchanged.
    """

    value: int | Decimal | str

    @staticmethod
    def from_json(
        value: JsonValue,
        *,
        format: TimestampFormat = TimestampFormat.EPOCH_SECONDS,
        path: str = "",
    ) -> Timestamp:
        """Read a timestamp in `format`. Raises `DecodeError` when the value does not match."""
        if format is TimestampFormat.EPOCH_SECONDS:
            if isinstance(value, bool) or not isinstance(value, (int, Decimal)):
                raise DecodeError(
                    path=path,
                    message=f"I expected epoch seconds as a JSON number; I found {_name(value)}.",
                )
            return Timestamp(value)
        if not isinstance(value, str):
            raise DecodeError(
                path=path,
                message=f"I expected a {format.value} timestamp string; I found {_name(value)}.",
            )
        try:
            if format is TimestampFormat.DATE_TIME:
                _parse_date_time(value)
            else:
                email.utils.parsedate_to_datetime(value)
        except (ValueError, TypeError):
            raise DecodeError(
                path=path, message=f"I expected a {format.value} timestamp; I found {value!r}."
            ) from None
        return Timestamp(value)

    @staticmethod
    def from_datetime(
        moment: datetime, *, format: TimestampFormat = TimestampFormat.EPOCH_SECONDS
    ) -> Timestamp:
        """Make a timestamp in `format` from an aware datetime."""
        if moment.tzinfo is None:
            raise ValueError(f"I expected an aware datetime; I found {moment.isoformat()}.")
        if format is TimestampFormat.EPOCH_SECONDS:
            delta = moment - datetime(1970, 1, 1, tzinfo=UTC)
            micros = (delta.days * 86400 + delta.seconds) * 1_000_000 + delta.microseconds
            seconds = Decimal(micros).scaleb(-6).normalize()
            exponent = seconds.as_tuple().exponent
            if isinstance(exponent, int) and exponent >= 0:
                return Timestamp(int(seconds))
            return Timestamp(seconds)
        if format is TimestampFormat.DATE_TIME:
            return Timestamp(moment.astimezone(UTC).isoformat().replace("+00:00", "Z"))
        return Timestamp(email.utils.format_datetime(moment.astimezone(UTC), usegmt=True))

    def to_json(self) -> JsonValue:
        """Give the JSON value, unchanged."""
        return self.value

    def to_datetime(self) -> datetime:
        """Give an aware datetime in UTC. A fraction below a microsecond is lost."""
        if isinstance(self.value, str):
            try:
                return _parse_date_time(self.value)
            except ValueError:
                return email.utils.parsedate_to_datetime(self.value).astimezone(UTC)
        seconds = Decimal(self.value)
        whole = int(seconds.to_integral_value(rounding="ROUND_FLOOR"))
        micros = int(((seconds - whole) * 1_000_000).to_integral_value())
        moment = datetime.fromtimestamp(whole, tz=UTC)
        return moment.replace(microsecond=micros) if micros < 1_000_000 else moment

    @classmethod
    def __get_pydantic_core_schema__(
        cls, source: object, handler: GetCoreSchemaHandler
    ) -> core_schema.CoreSchema:
        return _timestamp_schema(None)


def _parse_date_time(text: str) -> datetime:
    if "T" not in text and "t" not in text:
        raise ValueError(f"I expected a date-time with a T separator; I found {text!r}.")
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        raise ValueError(f"I expected a date-time with an offset; I found {text!r}.")
    return moment.astimezone(UTC)


def _timestamp_schema(format: TimestampFormat | None) -> core_schema.CoreSchema:
    def validate(value: object) -> Timestamp:
        if isinstance(value, Timestamp):
            return value
        chosen = format
        if chosen is None:
            text = isinstance(value, str)
            chosen = TimestampFormat.DATE_TIME if text else TimestampFormat.EPOCH_SECONDS
        try:
            return Timestamp.from_json(value, format=chosen)  # pyright: ignore[reportArgumentType]
        except DecodeError as error:
            raise ValueError(error.message) from None

    return core_schema.no_info_plain_validator_function(
        validate,
        serialization=core_schema.plain_serializer_function_ser_schema(
            lambda timestamp: timestamp.value  # pyright: ignore[reportUnknownLambdaType, reportUnknownMemberType]
        ),
    )


@dataclass(frozen=True, slots=True)
class _TimestampAs:
    format: TimestampFormat

    def __get_pydantic_core_schema__(
        self, source: object, handler: GetCoreSchemaHandler
    ) -> core_schema.CoreSchema:
        return _timestamp_schema(self.format)


EpochSecondsTimestamp = Annotated[Timestamp, _TimestampAs(TimestampFormat.EPOCH_SECONDS)]
DateTimeTimestamp = Annotated[Timestamp, _TimestampAs(TimestampFormat.DATE_TIME)]
HttpDateTimestamp = Annotated[Timestamp, _TimestampAs(TimestampFormat.HTTP_DATE)]


def to_wire(value: object) -> JsonValue:
    """Convert a Python value, such as a `model_dump(mode="python")` result, to a JSON value.

    `Decimal` and `int` stay exact, `bytes` become base64 text, a `Timestamp`
    gives its JSON value, an aware `datetime` gives date-time text, an `Enum`
    gives its value, and a tuple becomes an array. Raises `TypeError` for any
    other value.
    """
    if value is None or isinstance(value, (bool, int, Decimal, str)):
        return value
    if isinstance(value, float):
        return value
    if isinstance(value, (bytes, bytearray)):
        return encode_blob(bytes(value))
    if isinstance(value, Timestamp):
        return value.value
    if isinstance(value, datetime):
        return Timestamp.from_datetime(value, format=TimestampFormat.DATE_TIME).value
    if isinstance(value, Enum):
        return to_wire(value.value)  # pyright: ignore[reportUnknownMemberType]
    if isinstance(value, dict):
        out: dict[str, JsonValue] = {}
        for key, item in cast("dict[object, object]", value).items():
            if not isinstance(key, str):
                raise TypeError(f"I expected a string object key; I found {key!r}.")
            out[key] = to_wire(item)
        return out
    if isinstance(value, (list, tuple)):
        return [to_wire(item) for item in cast("list[object]", value)]
    raise TypeError(f"I expected a value that JSON can carry; I found a {type(value).__name__}.")

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
import math
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from enum import Enum
from typing import TYPE_CHECKING, Annotated, Any, cast, get_args

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    GetCoreSchemaHandler,
    PlainSerializer,
)
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
    """Convert a Python value, such as a generated model, to a JSON value.

    A Pydantic model gives an object with its wire names. A member that is
    None is absent, but a required member and a document member that was set
    keep their null. `Decimal` and `int` stay exact, `bytes` become base64 text, a
    `Timestamp` gives its JSON value, an aware `datetime` gives date-time text,
    an `Enum` gives its value, and a tuple becomes an array. Raises `TypeError`
    for any other value.
    """
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, Enum):
        return to_wire(value.value)  # pyright: ignore[reportUnknownMemberType]
    if isinstance(value, BaseModel):
        return _model_to_wire(value)
    if isinstance(value, float):
        return encode_double(value)
    if isinstance(value, (int, Decimal, str)):
        return value
    if isinstance(value, (bytes, bytearray)):
        return encode_blob(bytes(value))
    if isinstance(value, Timestamp):
        return value.value
    if isinstance(value, datetime):
        return Timestamp.from_datetime(value, format=TimestampFormat.DATE_TIME).value
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


def _is_document(annotation: object) -> bool:
    """Whether an annotation is `Document` or `Document | None`."""
    if any(isinstance(item, _DocumentSchema) for item in getattr(annotation, "__metadata__", ())):
        return True
    return any(
        isinstance(item, _DocumentSchema)
        for arg in get_args(annotation)
        for item in getattr(arg, "__metadata__", ())
    )


def _model_to_wire(model: BaseModel) -> dict[str, JsonValue]:
    out: dict[str, JsonValue] = {}
    fields_set = model.model_fields_set
    for name, info in type(model).model_fields.items():
        item = getattr(model, name)
        key = info.serialization_alias or info.alias or name
        if item is None:
            if info.is_required() or (
                name in fields_set
                and (
                    _is_document(info.annotation)
                    or any(isinstance(meta, _DocumentSchema) for meta in info.metadata)
                )
            ):
                out[key] = None
            continue
        out[key] = to_wire(item)
    return out


def to_wire_object(value: object) -> dict[str, JsonValue]:
    """Convert a model to a JSON object. Raises `TypeError` when the value is not an object."""
    wire = to_wire(value)
    if not isinstance(wire, dict):
        raise TypeError(f"I expected a value that gives a JSON object; I found {describe(wire)}.")
    return wire


_NON_FINITE = {"NaN": math.nan, "Infinity": math.inf, "-Infinity": -math.inf}


def decode_double(value: object, *, path: str = "") -> float:
    """Read a JSON number as a `float`. The strings "NaN", "Infinity" and "-Infinity"
    give the non-finite values. Another string or a boolean is an error."""
    if isinstance(value, float):
        return value
    if isinstance(value, (int, Decimal)) and not isinstance(value, bool):
        return float(value)
    if isinstance(value, str) and value in _NON_FINITE:
        return _NON_FINITE[value]
    raise DecodeError(path=path, message=f"I expected a JSON number; I found {_name(value)}.")


def encode_double(value: float) -> float | str:
    """Give a finite float unchanged, and a non-finite float as "NaN", "Infinity" or "-Infinity"."""
    if math.isnan(value):
        return "NaN"
    if math.isinf(value):
        return "Infinity" if value > 0 else "-Infinity"
    return value


Double = Annotated[
    float,
    BeforeValidator(_pydantic_value_error(decode_double)),
    PlainSerializer(encode_double),
]
"""A Smithy float or double. It accepts a JSON number, or "NaN", "Infinity" and "-Infinity"."""

Byte = Annotated[
    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**7), le=2**7 - 1)
]
"""A Smithy byte: an integer from -128 to 127."""

Short = Annotated[
    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**15), le=2**15 - 1)
]
"""A Smithy short: an integer from -32768 to 32767."""

Integer = Annotated[
    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**31), le=2**31 - 1)
]
"""A Smithy integer: a 32-bit signed integer."""

Long = Annotated[
    int, BeforeValidator(_pydantic_value_error(decode_integer)), Field(ge=-(2**63), le=2**63 - 1)
]
"""A Smithy long: a 64-bit signed integer, kept exactly."""


def check_document(value: object, *, path: str = "") -> JsonValue:
    """Give the value when it is a JSON value. Raises `DecodeError` at the first other value.

    The check keeps its own stack, so a deep value does not recurse.
    """
    stack: list[tuple[object, str]] = [(value, path)]
    while stack:
        item, at = stack.pop()
        if item is None or isinstance(item, (bool, int, Decimal, float, str)):
            continue
        if isinstance(item, list):
            for index, inner in enumerate(cast("list[object]", item)):
                stack.append((inner, f"{at}/{index}"))
        elif isinstance(item, dict):
            for key, inner in cast("dict[object, object]", item).items():
                if not isinstance(key, str):
                    raise DecodeError(path=at, message=f"I expected a string key; I found {key!r}.")
                stack.append((inner, f"{at}/{key.replace('~', '~0').replace('/', '~1')}"))
        else:
            raise DecodeError(path=at, message=f"I expected a JSON value; I found {_name(item)}.")
    return cast("JsonValue", value)


@dataclass(frozen=True, slots=True)
class _DocumentSchema:
    def __get_pydantic_core_schema__(
        self, source: object, handler: GetCoreSchemaHandler
    ) -> core_schema.CoreSchema:
        return core_schema.no_info_plain_validator_function(
            _pydantic_value_error(check_document),
            serialization=core_schema.plain_serializer_function_ser_schema(
                lambda value: value  # pyright: ignore[reportUnknownLambdaType]
            ),
        )


if TYPE_CHECKING:
    Document = JsonValue
    """A Smithy document: any JSON value, kept exactly."""
else:
    # Pydantic must not resolve the recursive alias; the schema checks the value.
    Document = Annotated[object, _DocumentSchema()]


class Unit(BaseModel):
    """The value of a union member that targets `smithy.api#Unit`: an empty object."""

    model_config = ConfigDict(extra="forbid", frozen=True)


def union_tag(value: object) -> str | None:
    """Give the member name of a tagged union value, for a Pydantic `Discriminator`.

    A JSON object gives its one member that is not null. A generated member
    model gives its `union_member` class attribute. Any other value gives None.
    """
    if isinstance(value, dict):
        keys = [
            key for key, item in cast("dict[object, object]", value).items() if item is not None
        ]
        if len(keys) == 1 and isinstance(keys[0], str):
            return keys[0]
        return None
    tag = getattr(type(value), "union_member", None)
    return tag if isinstance(tag, str) else None

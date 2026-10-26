"""Exact JSON reading and writing.

The reader gives `int` for each integer number and `decimal.Decimal` for each
number with a fraction or an exponent. A number never goes through `float`.
The writer writes a `Decimal` as a JSON number with its exact text, so
`Decimal("20.00")` stays `20.00`. The writer is compact and keeps non-ASCII
text as UTF-8.
"""

from __future__ import annotations

import json
import math
from decimal import Decimal
from typing import TypeAlias, Union, cast

from .errors import DecodeError

JsonValue: TypeAlias = Union[  # noqa: UP007
    bool, int, Decimal, float, str, list["JsonValue"], dict[str, "JsonValue"], None
]
"""A JSON value. An object is a `dict`, an array is a `list`."""

JsonObject: TypeAlias = dict[str, JsonValue]


def _reject_constant(name: str) -> JsonValue:
    raise ValueError(f"I expected a JSON number; I found {name}.")


def loads(text: str) -> JsonValue:
    """Parse JSON text exactly.

    Raises `DecodeError` with the path "" when the text is not JSON.
    """
    try:
        value: JsonValue = json.loads(
            text,
            parse_float=Decimal,
            parse_int=int,
            parse_constant=_reject_constant,
        )
    except (ValueError, RecursionError) as error:
        message = f"I could not parse the message as JSON: {error}."
        raise DecodeError(path="", message=message) from None
    return value


def _number_text(value: Decimal) -> str:
    if not value.is_finite():
        raise ValueError(f"I expected a finite decimal number; I found {value}.")
    return str(value)


def _write(value: object, out: list[str]) -> None:
    if value is None:
        out.append("null")
    elif value is True:
        out.append("true")
    elif value is False:
        out.append("false")
    elif isinstance(value, str):
        out.append(json.dumps(value, ensure_ascii=False))
    elif isinstance(value, int):
        out.append(int.__repr__(value))
    elif isinstance(value, Decimal):
        out.append(_number_text(value))
    elif isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"I expected a finite number; I found {value!r}.")
        out.append(float.__repr__(value))
    elif isinstance(value, dict):
        out.append("{")
        first = True
        for key, item in cast("dict[object, object]", value).items():
            if not isinstance(key, str):
                raise TypeError(f"I expected a string object key; I found {key!r}.")
            if not first:
                out.append(",")
            first = False
            out.append(json.dumps(key, ensure_ascii=False))
            out.append(":")
            _write(item, out)
        out.append("}")
    elif isinstance(value, (list, tuple)):
        out.append("[")
        for index, item in enumerate(cast("list[object]", value)):
            if index:
                out.append(",")
            _write(item, out)
        out.append("]")
    else:
        raise TypeError(f"I expected a JSON value; I found a {type(value).__name__}.")


def dumps(value: JsonValue) -> str:
    """Write a JSON value as compact text.

    Raises `TypeError` or `ValueError` when the value is not JSON, such as a
    NaN or a set.
    """
    out: list[str] = []
    _write(value, out)
    return "".join(out)


def object_of(value: JsonValue, *, path: str) -> JsonObject:
    """Give the value as an object, or raise `DecodeError` at `path`."""
    if isinstance(value, dict):
        return value
    raise DecodeError(path=path, message=f"I expected an object; I found {describe(value)}.")


def describe(value: JsonValue) -> str:
    """Name the kind of a JSON value, for an error message."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "a boolean"
    if isinstance(value, (int, Decimal, float)):
        return f"the number {dumps(value)}"
    if isinstance(value, str):
        return f"the string {dumps(value)}"
    if isinstance(value, list):
        return "an array"
    return "an object"


def pointer_get(value: JsonValue, pointer: str) -> tuple[bool, JsonValue]:
    """Resolve an RFC 6901 JSON Pointer.

    Gives `(True, found)` when the pointer names a value, else `(False, None)`.
    """
    if pointer == "":
        return True, value
    current = value
    for raw in pointer[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict):
            if token not in current:
                return False, None
            current = current[token]
        elif isinstance(current, list):
            if not token.isdigit() or (len(token) > 1 and token[0] == "0"):
                return False, None
            index = int(token)
            if index >= len(current):
                return False, None
            current = current[index]
        else:
            return False, None
    return True, current


def check_pointer(pointer: str) -> str:
    """Give the pointer when it is a valid RFC 6901 JSON Pointer."""
    if pointer != "" and not pointer.startswith("/"):
        raise ValueError(f"I expected a JSON Pointer that starts with /; I found {pointer!r}.")
    index = pointer.find("~")
    while index >= 0:
        if pointer[index + 1 : index + 2] not in ("0", "1"):
            raise ValueError(f"I expected ~0 or ~1 in JSON Pointer {pointer!r}.")
        index = pointer.find("~", index + 1)
    return pointer

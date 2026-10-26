"""Params of a request: named, positional, or either."""

from __future__ import annotations

from collections.abc import Mapping, Sequence

from .errors import DecodeError
from .json_codec import JsonValue, describe


def named_params(params: JsonValue | None) -> dict[str, JsonValue]:
    """Give named params as an object. Absent params give an empty object.

    Raises `DecodeError` for positional params or any other value.
    """
    if params is None:
        return {}
    if isinstance(params, dict):
        return params
    raise DecodeError(
        path="/params", message=f"I expected named params (an object); I found {describe(params)}."
    )


def positional_params(
    params: JsonValue | None, names: Sequence[str], *, either: bool
) -> dict[str, JsonValue]:
    """Give positional params as an object keyed by `names`, in order.

    Named params are accepted only when `either` is true. Raises `DecodeError`
    when the array has more items than `names`.
    """
    if params is None:
        return {}
    if isinstance(params, list):
        if len(params) > len(names):
            raise DecodeError(
                path="/params",
                message=(
                    f"I expected at most {len(names)} positional params; I found {len(params)}."
                ),
            )
        return dict(zip(names, params, strict=False))
    if isinstance(params, dict) and either:
        return params
    expected = "positional or named params" if either else "positional params (an array)"
    raise DecodeError(path="/params", message=f"I expected {expected}; I found {describe(params)}.")


def to_positional(value: Mapping[str, JsonValue], names: Sequence[str]) -> list[JsonValue]:
    """Give the members of `value` as an array in the order of `names`.

    Trailing absent members are dropped. An absent member before a present
    member becomes null.
    """
    items: list[JsonValue] = [value.get(name) for name in names]
    last = max((index for index, name in enumerate(names) if name in value), default=-1)
    return items[: last + 1]

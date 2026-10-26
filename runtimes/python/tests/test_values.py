from __future__ import annotations

import math
from datetime import UTC, datetime
from decimal import Decimal

import pytest
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from smithy_jsonrpc_runtime import (
    BigDecimal,
    BigInteger,
    Blob,
    Byte,
    DateTimeTimestamp,
    DecodeError,
    Document,
    Double,
    Integer,
    Long,
    RequestId,
    Short,
    Timestamp,
    TimestampFormat,
    json_codec,
    to_wire,
)


def test_parse_keeps_decimals_and_integers_exact() -> None:
    value = json_codec.loads('{"a":20.00,"b":12345678901234567.17,"c":9007199254740993}')
    assert value == {
        "a": Decimal("20.00"),
        "b": Decimal("12345678901234567.17"),
        "c": 9007199254740993,
    }
    assert isinstance(value, dict)
    assert str(value["a"]) == "20.00"
    assert type(value["c"]) is int


def test_write_keeps_exact_decimal_text() -> None:
    text = '{"amount":20.00,"big":12345678901234567.17,"n":9007199254740993,"s":"é\\n"}'
    assert json_codec.dumps(json_codec.loads(text)) == text


def test_write_is_compact_for_nested_values() -> None:
    value: json_codec.JsonValue = {"a": [1, True, None, {"b": Decimal("0.10")}], "c": 1.5}
    assert json_codec.dumps(value) == '{"a":[1,true,null,{"b":0.10}],"c":1.5}'


@pytest.mark.parametrize("text", ["NaN", "[Infinity]", "{", "", '{"a":-Infinity}'])
def test_parse_rejects_non_json(text: str) -> None:
    with pytest.raises(DecodeError):
        json_codec.loads(text)


def test_write_rejects_nan_and_unknown_types() -> None:
    with pytest.raises(ValueError, match="finite"):
        json_codec.dumps(Decimal("NaN"))
    with pytest.raises(TypeError, match="set"):
        json_codec.dumps({1, 2})  # pyright: ignore[reportArgumentType]


def test_pointer_resolves_rfc_6901_tokens() -> None:
    value = json_codec.loads('{"capabilities":{"payment":true},"a/b":[0,{"~":1}]}')
    assert json_codec.pointer_get(value, "/capabilities/payment") == (True, True)
    assert json_codec.pointer_get(value, "/a~1b/1/~0") == (True, 1)
    assert json_codec.pointer_get(value, "/missing") == (False, None)
    assert json_codec.pointer_get(value, "/a~1b/01") == (False, None)
    assert json_codec.pointer_get(value, "") == (True, value)
    with pytest.raises(ValueError, match="starts with /"):
        json_codec.check_pointer("capabilities")


def test_request_ids_keep_type_and_value() -> None:
    assert RequestId.from_json(7) == RequestId(7)
    assert RequestId.from_json("7") != RequestId(7)
    assert len({RequestId(1), RequestId("1")}) == 2
    assert RequestId(12345678901234567890).to_json() == 12345678901234567890
    assert str(RequestId("a")) == '"a"'
    bad_ids: list[json_codec.JsonValue] = [True, None, Decimal("1.5"), [1]]
    for bad in bad_ids:
        with pytest.raises(DecodeError, match="string or integer request ID"):
            RequestId.from_json(bad)


class Money(BaseModel):
    model_config = ConfigDict(extra="ignore", populate_by_name=True, frozen=True)
    amount: BigDecimal
    count: BigInteger = 0
    signature: Blob = b""
    created_at: DateTimeTimestamp | None = Field(default=None, alias="createdAt")
    since: Timestamp | None = None


def test_pydantic_models_keep_exact_values() -> None:
    wire = json_codec.loads(
        '{"amount":12345678901234567.17,"count":12345678901234567890,'
        '"signature":"dGVzdC1zaWduYXR1cmU=","createdAt":"2026-10-25T10:00:00Z",'
        '"since":1792922400.5,"extra":1}'
    )
    money = Money.model_validate(wire)
    assert money.amount == Decimal("12345678901234567.17")
    assert money.count == 12345678901234567890
    assert money.signature == b"test-signature"
    assert money.created_at == Timestamp("2026-10-25T10:00:00Z")
    assert money.since == Timestamp(Decimal("1792922400.5"))
    dumped = money.model_dump(mode="python", by_alias=True, exclude_none=True)
    assert json_codec.dumps(dumped) == (
        '{"amount":12345678901234567.17,"count":12345678901234567890,'
        '"signature":"dGVzdC1zaWduYXR1cmU=","createdAt":"2026-10-25T10:00:00Z",'
        '"since":1792922400.5}'
    )


@pytest.mark.parametrize(
    "wire",
    [
        '{"amount":"20.00"}',
        '{"amount":true}',
        '{"amount":1,"count":1.5}',
        '{"amount":1,"signature":"not base64!"}',
        '{"amount":1,"createdAt":1}',
        '{"amount":1,"createdAt":"yesterday"}',
    ],
)
def test_pydantic_models_reject_inexact_values(wire: str) -> None:
    with pytest.raises(ValidationError):
        Money.model_validate(json_codec.loads(wire))


def test_timestamps_convert_to_datetimes() -> None:
    moment = datetime(2026, 10, 25, 10, 0, 0, 500000, tzinfo=UTC)
    epoch = Timestamp.from_datetime(moment)
    assert epoch.value == Decimal("1792922400.5")
    assert epoch.to_datetime() == moment
    assert Timestamp.from_datetime(moment.replace(microsecond=0)).value == 1792922400
    text = Timestamp.from_datetime(moment, format=TimestampFormat.DATE_TIME)
    assert text.value == "2026-10-25T10:00:00.500000Z"
    http = Timestamp.from_datetime(moment.replace(microsecond=0), format=TimestampFormat.HTTP_DATE)
    assert http.value == "Sun, 25 Oct 2026 10:00:00 GMT"
    assert http.to_datetime() == moment.replace(microsecond=0)
    parsed = Timestamp.from_json(http.value, format=TimestampFormat.HTTP_DATE)
    assert parsed == http
    with pytest.raises(DecodeError, match="epoch seconds"):
        Timestamp.from_json("1", format=TimestampFormat.EPOCH_SECONDS, path="/since")


class Sized(BaseModel):
    model_config = ConfigDict(frozen=True)
    small: Byte = 0
    medium: Short = 0
    whole: Integer = 0
    big: Long = 0
    ratio: Double = 0.0


def test_integer_ranges_follow_smithy() -> None:
    edge = Sized.model_validate(
        {"small": -128, "medium": 32767, "whole": -(2**31), "big": 2**63 - 1}
    )
    assert (edge.small, edge.medium, edge.whole, edge.big) == (-128, 32767, -(2**31), 2**63 - 1)
    for wire in (
        {"small": 128},
        {"medium": -32769},
        {"whole": 2**31},
        {"big": 2**63},
        {"small": "1"},
    ):
        with pytest.raises(ValidationError):
            Sized.model_validate(wire)


def test_non_finite_doubles_use_the_strings_of_the_validator() -> None:
    nan = Sized.model_validate({"ratio": "NaN"})
    assert math.isnan(nan.ratio)
    infinite = Sized.model_validate({"ratio": "Infinity"})
    assert infinite.ratio == math.inf
    for value, text in ((nan, "NaN"), (infinite, "Infinity")):
        wire = to_wire(value)
        assert isinstance(wire, dict) and wire["ratio"] == text
    negative = Sized(ratio=-math.inf)
    assert json_codec.dumps(to_wire(negative)).endswith('"ratio":"-Infinity"}')
    assert to_wire(math.nan) == "NaN"
    with pytest.raises(ValidationError):
        Sized.model_validate({"ratio": "nan"})


class WithDocument(BaseModel):
    model_config = ConfigDict(frozen=True)
    value: Document
    extra: Document | None = None
    note: str | None = None


def test_to_wire_keeps_a_present_null_and_drops_absent_members() -> None:
    assert to_wire(WithDocument(value=None)) == {"value": None}
    assert to_wire(WithDocument(value=1, extra=None)) == {"value": 1, "extra": None}
    assert to_wire(WithDocument(value=1, note=None)) == {"value": 1}
    assert to_wire(WithDocument.model_validate({"value": None, "note": None})) == {"value": None}

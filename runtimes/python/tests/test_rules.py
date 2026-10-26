from __future__ import annotations

from decimal import Decimal
from enum import Enum

import pytest
from pydantic import BaseModel, ConfigDict, ValidationError

from smithy_jsonrpc_runtime import (
    CapabilitySource,
    DecodeError,
    Document,
    Double,
    MethodRule,
    ModeledError,
    RpcError,
    Session,
    SessionRules,
    Timestamp,
    Unit,
    modeled_error,
    named_params,
    positional_params,
    to_positional,
    to_wire,
    to_wire_object,
    union_tag,
)

from .payment import session_rules


def test_rules_reject_unknown_names() -> None:
    with pytest.raises(ValueError, match="at least one session state"):
        SessionRules(states=[])
    with pytest.raises(ValueError, match="name a session state; I found 'nowhere'"):
        SessionRules(states=["a"], methods=[MethodRule("p", "m", allowed=["nowhere"])])
    with pytest.raises(ValueError, match="require a known capability; I found 'pay'"):
        SessionRules(states=["a"], methods=[MethodRule("p", "m", requires=["pay"])])
    with pytest.raises(ValueError, match="starts with /"):
        CapabilitySource("pay", "init", "capabilities")
    with pytest.raises(ValueError, match="one refusal code for state a"):
        SessionRules(states=["a"], refusals=[("a", 1), ("a", 2)])


def test_session_settles_like_the_validator() -> None:
    session = Session(session_rules())
    assert session.state == "starting"
    refusal = session.accept("terminal", "payment.status")
    assert refusal is not None and refusal.code == 1007
    assert session.accept("terminal", "terminal.initialize") is None
    session.settle(
        "terminal",
        "terminal.initialize",
        failed=False,
        result={"capabilities": {"payment": True, "tips": False, "pin": None}},
    )
    assert session.state == "initializing"
    assert session.advertised == {"payment"}
    assert session.accept("terminal", "terminal.initialized") is None
    assert session.state == "ready"
    assert session.accept("terminal", "payment.start") is None
    assert session.state == "paying"
    refusal = session.check("pos", "pos.confirmTip")
    assert refusal is not None and refusal.code == 1008
    session.settle("terminal", "payment.start", failed=True, result=None)
    assert session.state == "ready"
    assert session.accept("terminal", "test.unmodeled") is None
    assert SessionRules.none().states == ("open",)


def test_params_helpers() -> None:
    assert named_params(None) == {}
    assert named_params({"a": 1}) == {"a": 1}
    with pytest.raises(DecodeError, match="named params"):
        named_params([1])
    assert positional_params([1, 2], ["a", "b", "c"], either=False) == {"a": 1, "b": 2}
    assert positional_params({"a": 1}, ["a"], either=True) == {"a": 1}
    with pytest.raises(DecodeError, match="positional params"):
        positional_params({"a": 1}, ["a"], either=False)
    with pytest.raises(DecodeError, match="at most 1 positional params; I found 2"):
        positional_params([1, 2], ["a"], either=True)
    assert to_positional({"a": 1, "c": 3}, ["a", "b", "c", "d"]) == [1, None, 3]
    assert to_positional({}, ["a"]) == []


class Holder(BaseModel):
    model_config = ConfigDict(frozen=True)
    doc: Document = None
    ratio: Double = 0.0


class Phase(Enum):
    INSERT_CARD = "insertCard"


def test_to_wire_converts_python_dumps() -> None:
    value = {
        "amount": Decimal("20.00"),
        "big": 12345678901234567890,
        "blob": b"test-signature",
        "since": Timestamp(1792922400),
        "phase": Phase.INSERT_CARD,
        "items": ({"x": None},),
    }
    assert to_wire(value) == {
        "amount": Decimal("20.00"),
        "big": 12345678901234567890,
        "blob": "dGVzdC1zaWduYXR1cmU=",
        "since": 1792922400,
        "phase": "insertCard",
        "items": [{"x": None}],
    }
    with pytest.raises(TypeError, match="set"):
        to_wire({1})


def test_generator_support_types() -> None:
    held = Holder.model_validate({"doc": {"a": [Decimal("1.10"), None]}, "ratio": Decimal("0.5")})
    assert held.doc == {"a": [Decimal("1.10"), None]}
    assert held.ratio == 0.5
    assert to_wire_object(held) == {"doc": {"a": [Decimal("1.10"), None]}, "ratio": 0.5}
    with pytest.raises(ValidationError):
        Holder.model_validate({"ratio": "0.5"})
    with pytest.raises(ValidationError):
        Holder.model_validate({"doc": {1, 2}})
    assert to_wire(Unit()) == {}
    assert union_tag({"chip": {}, "swipe": None}) == "chip"
    assert union_tag({"chip": {}, "swipe": {}}) is None
    assert union_tag(3) is None

    class Declined(ModeledError):
        code = 1001

    def decode(data: object) -> ModeledError:
        if data != "test decline":
            raise ValueError("I expected the test reason.")
        return Declined("CardDeclined")

    found = modeled_error(RpcError(1001, "x", "test decline"), {1001: decode})
    assert isinstance(found, Declined) and found.to_rpc_error().code == 1001
    other = RpcError(1001, "x", "other")
    assert modeled_error(other, {1001: decode}) is other
    unknown = RpcError(7, "x")
    assert modeled_error(unknown, {1001: decode}) is unknown
    with pytest.raises(TypeError, match="JSON object"):
        to_wire_object(3)

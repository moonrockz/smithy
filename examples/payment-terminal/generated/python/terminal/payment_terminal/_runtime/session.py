"""Session rules and the session state machine.

The generator renders the `jsonRpcSession`, `jsonRpcLifecycle` and
`jsonRpcCancels` traits of a protocol as one `SessionRules` value. Each peer
keeps one `Session` and applies every message that it sends or receives, with
the semantics of `smithy validate rpc transcript`:

- A method with a rule for its receiving peer is refused when the state is not
  in its allowed states, or when a capability that it requires is not
  advertised. A refused message changes nothing, and its reply settles nothing.
- An accepted message applies `on_call` first, then its cancellation.
- The reply of an accepted call applies `on_error` for an error and
  `on_success` for a result, from the rule of the peer that answers. A result
  advertises each capability source of the method unless the value at the
  pointer is absent, null or false. A capability is never withdrawn.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field

from .errors import INVALID_REQUEST, REQUEST_CANCELLED
from .ids import RequestId
from .json_codec import JsonValue, check_pointer, pointer_get


@dataclass(frozen=True, slots=True)
class CapabilitySource:
    """A capability that the successful result of a method advertises.

    `pointer` is a JSON Pointer into the result of `method_name`.
    """

    name: str
    method_name: str
    pointer: str

    def __post_init__(self) -> None:
        if not self.name:
            raise ValueError("I expected a nonempty capability name; I found an empty name.")
        if not self.method_name:
            raise ValueError(f"I expected a method for capability {self.name}; I found none.")
        check_pointer(self.pointer)


@dataclass(frozen=True, slots=True)
class CancelRule:
    """How a method cancels a call.

    `id_member` is the wire name of the ID member in named params. `position`
    is its index in positional params. `code` is the error code that the
    cancelled call answers with.
    """

    id_member: str
    position: int | None = None
    code: int | None = None

    def call_id(self, params: JsonValue | None) -> JsonValue | None:
        """Give the raw ID that the params name, or None."""
        if isinstance(params, dict):
            return params.get(self.id_member)
        if isinstance(params, list) and self.position is not None:
            return params[self.position] if self.position < len(params) else None
        return None

    @property
    def answer_code(self) -> int:
        """The code of the answer to a cancelled call: `code`, else -32800."""
        return REQUEST_CANCELLED if self.code is None else self.code


@dataclass(frozen=True, slots=True)
class MethodRule:
    """The order rules of one method that `receiver` accepts.

    `allowed` None means every state. `requires` names capabilities.
    """

    receiver: str
    method_name: str
    allowed: Sequence[str] | None = None
    on_call: str | None = None
    on_success: str | None = None
    on_error: str | None = None
    requires: Sequence[str] = ()
    cancels: CancelRule | None = None


@dataclass(frozen=True, slots=True)
class Refusal:
    """Why a session refuses a message, with the code of the error reply."""

    code: int
    message: str


class SessionRules:
    """The session rules of a protocol. The first state is the initial state."""

    __slots__ = ("_methods", "capabilities", "capability_refusal", "refusals", "states")

    def __init__(
        self,
        *,
        states: Sequence[str],
        capabilities: Sequence[CapabilitySource] = (),
        methods: Sequence[MethodRule] = (),
        refusals: Iterable[tuple[str, int]] = (),
        capability_refusal: int | None = None,
    ) -> None:
        if not states:
            raise ValueError("I expected at least one session state; I found none.")
        if len(set(states)) != len(states):
            raise ValueError(f"I expected distinct session states; I found {list(states)}.")
        self.states: tuple[str, ...] = tuple(states)
        names = [source.name for source in capabilities]
        if len(set(names)) != len(names):
            raise ValueError(f"I expected distinct capability names; I found {names}.")
        self.capabilities: tuple[CapabilitySource, ...] = tuple(capabilities)
        self._methods: dict[tuple[str, str], MethodRule] = {}
        for rule in methods:
            self._check_rule(rule, set(names))
            key = (rule.receiver, rule.method_name)
            if key in self._methods:
                raise ValueError(
                    f"I expected one rule for method {rule.method_name} of peer {rule.receiver}; "
                    "I found two."
                )
            self._methods[key] = rule
        self.refusals: dict[str, int] = {}
        for state, code in refusals:
            self._check_state(state, "a refusal")
            if state in self.refusals:
                raise ValueError(f"I expected one refusal code for state {state}; I found two.")
            self.refusals[state] = code
        self.capability_refusal = capability_refusal

    @staticmethod
    def none() -> SessionRules:
        """Rules with one state and no method rules: every message is accepted."""
        return SessionRules(states=["open"])

    def _check_state(self, state: str, construct: str) -> None:
        if state not in self.states:
            raise ValueError(f"I expected {construct} to name a session state; I found {state!r}.")

    def _check_rule(self, rule: MethodRule, capabilities: set[str]) -> None:
        construct = f"the rule of method {rule.method_name}"
        for state in rule.allowed or ():
            self._check_state(state, construct)
        if rule.allowed is not None and not rule.allowed:
            raise ValueError(f"I expected {construct} to allow at least one state; I found none.")
        for state in (rule.on_call, rule.on_success, rule.on_error):
            if state is not None:
                self._check_state(state, construct)
        for name in rule.requires:
            if name not in capabilities:
                raise ValueError(
                    f"I expected {construct} to require a known capability; I found {name!r}."
                )

    def rule(self, receiver: str, method: str) -> MethodRule | None:
        """Give the rule of `method` when `receiver` accepts it, or None."""
        return self._methods.get((receiver, method))

    def cancel_rule(self, receiver: str, method: str) -> CancelRule | None:
        """Give the cancellation of `method` when `receiver` accepts it, or None."""
        found = self._methods.get((receiver, method))
        return None if found is None else found.cancels


@dataclass(slots=True)
class Session:
    """The session state of one peer, driven by `SessionRules`."""

    rules: SessionRules
    state: str = ""
    advertised: set[str] = field(default_factory=set[str])

    def __post_init__(self) -> None:
        if not self.state:
            self.state = self.rules.states[0]

    def check(self, receiver: str, method: str) -> Refusal | None:
        """Give the refusal of a message from the other peer of `receiver`, or None."""
        rule = self.rules.rule(receiver, method)
        if rule is None:
            return None
        if rule.allowed is not None and self.state not in rule.allowed:
            code = self.rules.refusals.get(self.state, INVALID_REQUEST)
            return Refusal(code, f"I refused {method} in state {self.state}.")
        for name in rule.requires:
            if name not in self.advertised:
                code = (
                    INVALID_REQUEST
                    if self.rules.capability_refusal is None
                    else self.rules.capability_refusal
                )
                return Refusal(code, f"I refused {method} because {name} is not advertised.")
        return None

    def accept(self, receiver: str, method: str) -> Refusal | None:
        """Check a message and, when it is accepted, apply its `on_call` state."""
        refusal = self.check(receiver, method)
        if refusal is None:
            rule = self.rules.rule(receiver, method)
            if rule is not None and rule.on_call is not None:
                self.state = rule.on_call
        return refusal

    def settle(self, responder: str, method: str, *, failed: bool, result: JsonValue) -> None:
        """Apply the reply of an accepted call that `responder` answers."""
        rule = self.rules.rule(responder, method)
        if rule is not None:
            following = rule.on_error if failed else rule.on_success
            if following is not None:
                self.state = following
        if failed:
            return
        for source in self.rules.capabilities:
            if source.method_name == method:
                found, value = pointer_get(result, source.pointer)
                if found and value is not None and value is not False:
                    self.advertised.add(source.name)


def cancel_target(rule: CancelRule, params: JsonValue | None) -> RequestId | None:
    """Give the ID of the call that a cancellation names, or None when it names no usable ID."""
    raw = rule.call_id(params)
    if isinstance(raw, bool) or not isinstance(raw, (int, str)):
        return None
    return RequestId(raw)

"""A hand-written payment terminal and POS on the runtime, like the sample model.

The rules copy the `jsonRpcSession` and `jsonRpcLifecycle` traits of
examples/payment-terminal/model.smithy.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from decimal import Decimal

from smithy_jsonrpc_runtime import (
    CallContext,
    CancelRule,
    CapabilitySource,
    JsonValue,
    MemoryConnection,
    MethodKind,
    MethodRule,
    Peer,
    RpcError,
    SessionRules,
    TranscriptLog,
    encode_blob,
    memory_pair,
    named_params,
)

CAPABILITIES = [
    "payment",
    "swipe",
    "chip",
    "contactless",
    "pin",
    "tips",
    "signature",
    "progress",
    "cancellation",
]


def session_rules() -> SessionRules:
    t, p = "terminal", "pos"
    return SessionRules(
        states=["starting", "initializing", "ready", "paying", "stopping", "stopped"],
        capabilities=[
            CapabilitySource(name, "terminal.initialize", f"/capabilities/{name}")
            for name in CAPABILITIES
        ],
        methods=[
            MethodRule(t, "terminal.initialize", allowed=["starting"], on_success="initializing"),
            MethodRule(t, "terminal.initialized", allowed=["initializing"], on_call="ready"),
            MethodRule(
                t,
                "payment.start",
                allowed=["ready"],
                on_call="paying",
                on_success="ready",
                on_error="ready",
                requires=["payment"],
            ),
            MethodRule(t, "payment.status", allowed=["ready", "paying"]),
            MethodRule(t, "payment.refund", allowed=["ready"]),
            MethodRule(t, "payment.void", allowed=["ready"]),
            MethodRule(t, "terminal.shutdown", allowed=["ready"], on_success="stopping"),
            MethodRule(t, "terminal.exit", allowed=["stopping"], on_call="stopped"),
            MethodRule(
                t,
                "$/cancelRequest",
                allowed=["paying"],
                requires=["cancellation"],
                cancels=CancelRule("id", code=-32800),
            ),
            MethodRule(p, "payment.progress", allowed=["paying"], requires=["progress"]),
            MethodRule(p, "pos.confirmTip", allowed=["paying"], requires=["tips"]),
            MethodRule(p, "pos.requestSignature", allowed=["paying"], requires=["signature"]),
            MethodRule(p, "pos.display", allowed=["ready", "paying"]),
        ],
        refusals=[(state, 1007) for state in ("starting", "initializing", "stopping", "stopped")],
        capability_refusal=1008,
    )


def usd(amount: str) -> dict[str, JsonValue]:
    return {"amount": Decimal(amount), "currency": "USD"}


@dataclass
class Terminal:
    """The terminal handlers, with the rules of the sample by the cents of the amount."""

    peer: Peer
    payments: dict[str, Decimal] = field(default_factory=dict[str, Decimal])
    cancelled: list[str] = field(default_factory=list[str])
    exited: asyncio.Event = field(default_factory=asyncio.Event)

    def register(self) -> None:
        peer = self.peer
        peer.on_request("terminal.initialize", MethodKind.REQUEST_ONLY, self.initialize)
        peer.on_notification("terminal.initialized", MethodKind.NOTIFICATION_ONLY, self.nothing)
        peer.on_request("terminal.ping", MethodKind.REQUEST_ONLY, self.null)
        peer.on_request("payment.start", MethodKind.REQUEST_ONLY, self.start)
        peer.on_request("payment.status", MethodKind.REQUEST_ONLY, self.status)
        peer.on_request("payment.refund", MethodKind.REQUEST_ONLY, self.refund)
        peer.on_request("payment.void", MethodKind.REQUEST_ONLY, self.void)
        peer.on_request("terminal.shutdown", MethodKind.REQUEST_ONLY, self.null)
        peer.on_notification("terminal.exit", MethodKind.NOTIFICATION_ONLY, self.exit)

    async def initialize(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        pos_name = named_params(params).get("posName")
        if isinstance(pos_name, str) and pos_name.endswith("(no payment)"):
            capabilities: dict[str, JsonValue] = {"payment": False}
        else:
            capabilities = dict.fromkeys(CAPABILITIES, True)
        return {"protocolVersion": "1", "terminalId": "test-terminal", "capabilities": capabilities}

    async def nothing(self, params: JsonValue | None, ctx: CallContext) -> None:
        return None

    async def null(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        return None

    async def exit(self, params: JsonValue | None, ctx: CallContext) -> None:
        self.exited.set()

    async def start(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        args = named_params(params)
        payment_id = args["paymentId"]
        money = args["amount"]
        assert isinstance(payment_id, str) and isinstance(money, dict)
        amount = money["amount"]
        assert isinstance(amount, Decimal)
        cents = str(amount).rpartition(".")[2]
        progress = ctx.id_json()
        if cents == "13":
            raise RpcError(1001, "I declined the test card.", "test decline")
        await ctx.notify("payment.progress", {"requestId": progress, "phase": "insertCard"})
        if cents == "17":
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                self.cancelled.append(payment_id)
                raise
        await ctx.notify("payment.progress", {"requestId": progress, "phase": "enterPin"})
        accepted = await ctx.request(
            "pos.confirmTip", {"paymentId": payment_id, "amount": usd("2.50")}
        )
        signature = await ctx.request(
            "pos.requestSignature", {"paymentId": payment_id, "prompt": "Sign the test receipt"}
        )
        assert accepted is True and signature == encode_blob(b"test-signature")
        await ctx.notify("pos.display", {"message": "I am checking the test payment."})
        await ctx.notify("payment.progress", {"requestId": progress, "phase": "authorizing"})
        self.payments[payment_id] = amount
        return {"paymentId": payment_id, "outcome": {"approved": {"authorizationCode": "TEST-OK"}}}

    def _stored(self, params: JsonValue | None) -> tuple[str, Decimal]:
        payment_id = named_params(params).get("paymentId")
        assert isinstance(payment_id, str)
        if payment_id not in self.payments:
            raise RpcError(1005, "I found no test payment.", {"paymentId": payment_id})
        return payment_id, self.payments[payment_id]

    async def status(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        self._stored(params)
        return {"approved": {"authorizationCode": "TEST-OK"}}

    async def refund(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        payment_id, stored = self._stored(params)
        money = named_params(params)["amount"]
        assert isinstance(money, dict)
        amount = money["amount"]
        assert isinstance(amount, Decimal)
        if amount > stored:
            raise RpcError(
                1006,
                "I cannot refund more than the payment.",
                {"paymentId": payment_id, "maximum": usd(str(stored))},
            )
        return {"refundId": "test-refund", "amount": money}

    async def void(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        payment_id, _ = self._stored(params)
        del self.payments[payment_id]
        return None


@dataclass
class Pos:
    """The POS handlers. `cancel_on_progress` cancels a call on its first progress."""

    peer: Peer
    progress: list[tuple[JsonValue, JsonValue]] = field(
        default_factory=list[tuple[JsonValue, JsonValue]]
    )
    displayed: list[str] = field(default_factory=list[str])
    cancel_on_progress: bool = False
    changed: asyncio.Condition = field(default_factory=asyncio.Condition)

    async def wait_progress(self, count: int) -> None:
        """Wait until the POS has received `count` progress notifications."""
        async with self.changed:
            await asyncio.wait_for(self.changed.wait_for(lambda: len(self.progress) >= count), 5)

    def register(self) -> None:
        peer = self.peer
        peer.on_notification("payment.progress", MethodKind.NOTIFICATION_ONLY, self.on_progress)
        peer.call_reference("payment.progress", id_member="requestId")
        peer.on_request("pos.confirmTip", MethodKind.REQUEST_ONLY, self.confirm_tip)
        peer.on_request("pos.requestSignature", MethodKind.REQUEST_ONLY, self.signature)
        peer.on_notification("pos.display", MethodKind.NOTIFICATION_ONLY, self.display)

    async def on_progress(self, params: JsonValue | None, ctx: CallContext) -> None:
        args = named_params(params)
        self.progress.append((args.get("requestId"), args.get("phase")))
        async with self.changed:
            self.changed.notify_all()
        if self.cancel_on_progress and len(self.progress) == 1:
            await ctx.notify("$/cancelRequest", {"id": args.get("requestId")})

    async def confirm_tip(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        return True

    async def signature(self, params: JsonValue | None, ctx: CallContext) -> JsonValue:
        return encode_blob(b"test-signature")

    async def display(self, params: JsonValue | None, ctx: CallContext) -> None:
        message = named_params(params).get("message")
        assert isinstance(message, str)
        self.displayed.append(message)


@dataclass
class Pair:
    pos: Pos
    terminal: Terminal
    pos_conn: MemoryConnection
    terminal_conn: MemoryConnection


@asynccontextmanager
async def running_pair(
    *, pos_log: TranscriptLog | None = None, terminal_log: TranscriptLog | None = None
) -> AsyncGenerator[Pair, None]:
    """Run a POS peer and a terminal peer over an in-memory connection pair."""
    pos_conn, terminal_conn = memory_pair()
    pos = Pos(Peer(self_name="pos", remote_name="terminal", rules=session_rules(), log=pos_log))
    terminal = Terminal(
        Peer(self_name="terminal", remote_name="pos", rules=session_rules(), log=terminal_log)
    )
    pos.register()
    terminal.register()
    tasks = [
        asyncio.create_task(pos.peer.run(pos_conn)),
        asyncio.create_task(terminal.peer.run(terminal_conn)),
    ]
    try:
        yield Pair(pos, terminal, pos_conn, terminal_conn)
    finally:
        await pos_conn.close()
        await asyncio.wait_for(asyncio.gather(*tasks), 5)

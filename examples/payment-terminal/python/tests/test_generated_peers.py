"""The generated POS and terminal peers talk to each other over an in-memory connection."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from decimal import Decimal

import pytest
from payment_pos import models as pm
from payment_pos import new_peer as new_pos_peer
from payment_pos._runtime import CallContext as PosContext
from payment_pos._runtime import RpcError as PosRpcError
from payment_pos.client import PaymentTerminalClient
from payment_pos.errors import CardDeclined, RefundExceedsAmount
from payment_pos.handler import register_point_of_sale
from payment_terminal import errors as te
from payment_terminal import models as tm
from payment_terminal import new_peer as new_terminal_peer
from payment_terminal._runtime import CallContext
from payment_terminal.client import PointOfSaleClient
from payment_terminal.handler import register_payment_terminal

CARD = pm.TestCard(masked_number="**** 4242")


class Link:
    """One end of an in-memory connection. Each generated package has its own runtime
    copy, so this end accepts the request ID type of both copies."""

    def __init__(self, inbox: asyncio.Queue[str | None], outbox: asyncio.Queue[str | None]) -> None:
        self.inbox = inbox
        self.outbox = outbox

    async def receive(self) -> str | None:
        return await self.inbox.get()

    async def send(self, text: str, *, related: object = None) -> None:
        await self.outbox.put(text)

    async def close(self) -> None:
        await self.outbox.put(None)
        await self.inbox.put(None)


def link_pair() -> tuple[Link, Link]:
    left: asyncio.Queue[str | None] = asyncio.Queue()
    right: asyncio.Queue[str | None] = asyncio.Queue()
    return Link(left, right), Link(right, left)


def usd(amount: str) -> pm.Money:
    return pm.Money(amount=Decimal(amount), currency=pm.Currency.USD)


def start(payment_id: str, amount: str) -> pm.StartPaymentInput:
    return pm.StartPaymentInput(
        payment_id=payment_id, amount=usd(amount), entry=pm.EntryMethodChip(chip=CARD)
    )


@dataclass
class Terminal:
    """A terminal handler with a few rules of the sample."""

    payments: dict[str, tm.Money] = field(default_factory=dict[str, tm.Money])

    async def initialize(
        self, input: tm.InitializeInput, context: CallContext
    ) -> tm.InitializeOutput:
        payment = not input.pos_name.endswith("(no payment)")
        capabilities = tm.Capabilities(
            payment=payment, tips=True, signature=True, progress=True, cancellation=True
        )
        return tm.InitializeOutput(
            protocol_version=tm.ProtocolVersion.V1,
            terminal_id="test-terminal",
            capabilities=capabilities,
        )

    async def initialized(self, context: CallContext) -> None:
        return None

    async def ping(self, context: CallContext) -> None:
        return None

    async def shutdown(self, context: CallContext) -> None:
        return None

    async def exit(self, context: CallContext) -> None:
        return None

    async def start_payment(
        self, input: tm.StartPaymentInput, context: CallContext
    ) -> tm.PaymentOutput:
        pos = PointOfSaleClient(context.peer)
        request_id = context.id_json()
        cents = str(input.amount.amount).rpartition(".")[2]
        if cents == "13":
            raise te.CardDeclined(te.CardDeclinedData(reason="test decline"))
        await pos.payment_progress(
            tm.PaymentProgressInput(request_id=request_id, phase=tm.PaymentPhase.INSERT_CARD)
        )
        if cents == "17":
            await asyncio.Event().wait()
        tip = tm.Money(amount=Decimal("2.50"), currency=tm.Currency.USD)
        accepted = await pos.confirm_tip(
            tm.ConfirmTipInput(payment_id=input.payment_id, amount=tip)
        )
        signature = await pos.request_signature(
            tm.RequestSignatureInput(payment_id=input.payment_id, prompt="Sign the test receipt")
        )
        assert accepted is True and signature == b"test-signature"
        await pos.display(tm.DisplayInput(message="I am checking the test payment."))
        self.payments[input.payment_id] = input.amount
        outcome = tm.PaymentOutcomeApproved(approved=tm.Approved(authorization_code="TEST-OK"))
        return tm.PaymentOutput(payment_id=input.payment_id, outcome=outcome)

    async def payment_status(
        self, input: tm.PaymentIdInput, context: CallContext
    ) -> tm.PaymentOutcome:
        self._stored(input.payment_id)
        return tm.PaymentOutcomeApproved(approved=tm.Approved(authorization_code="TEST-OK"))

    def _stored(self, payment_id: str) -> tm.Money:
        if payment_id not in self.payments:
            raise te.PaymentNotFound(te.PaymentNotFoundData(payment_id=payment_id))
        return self.payments[payment_id]

    async def refund_payment(self, input: tm.RefundInput, context: CallContext) -> tm.RefundOutput:
        stored = self._stored(input.payment_id)
        if input.amount.amount > stored.amount:
            data = te.RefundExceedsAmountData(payment_id=input.payment_id, maximum=stored)
            raise te.RefundExceedsAmount(data)
        return tm.RefundOutput(refund_id="test-refund", amount=input.amount)

    async def void_payment(self, input: tm.PaymentIdInput, context: CallContext) -> None:
        self._stored(input.payment_id)
        del self.payments[input.payment_id]

    async def get_receipt(self, input: tm.PaymentIdInput, context: CallContext) -> tm.Receipt:
        stored = self._stored(input.payment_id)
        return tm.Receipt(
            payment_id=input.payment_id,
            merchant=tm.Merchant(name="Test Shop"),
            lines=[tm.ReceiptLine(label="Test item", amount=stored)],
            total=stored,
        )

    async def list_transactions(
        self, input: tm.ListTransactionsInput, context: CallContext
    ) -> tm.ListTransactionsOutput:
        return tm.ListTransactionsOutput(transactions=[])


@dataclass
class Pos:
    """A POS handler. With `cancel`, it cancels the call on its first progress."""

    client: PaymentTerminalClient
    cancel: bool = False
    phases: list[pm.PaymentPhase] = field(default_factory=list[pm.PaymentPhase])
    displayed: list[str] = field(default_factory=list[str])

    async def payment_progress(self, input: pm.PaymentProgressInput, context: PosContext) -> None:
        self.phases.append(input.phase)
        if self.cancel and len(self.phases) == 1:
            await self.client.cancel_request(pm.CancelRequestInput(id=input.request_id))

    async def confirm_tip(self, input: pm.ConfirmTipInput, context: PosContext) -> bool:
        assert str(input.amount.amount) == "2.50"
        return True

    async def display(self, input: pm.DisplayInput, context: PosContext) -> None:
        self.displayed.append(input.message)

    async def request_signature(
        self, input: pm.RequestSignatureInput, context: PosContext
    ) -> bytes:
        return b"test-signature"


@asynccontextmanager
async def running() -> AsyncGenerator[tuple[PaymentTerminalClient, Pos], None]:
    pos_conn, terminal_conn = link_pair()
    pos_peer = new_pos_peer()
    terminal_peer = new_terminal_peer()
    client = PaymentTerminalClient(pos_peer)
    pos = Pos(client)
    register_point_of_sale(pos_peer, pos)
    register_payment_terminal(terminal_peer, Terminal())
    tasks = [
        asyncio.create_task(pos_peer.run(pos_conn)),
        asyncio.create_task(terminal_peer.run(terminal_conn)),
    ]
    try:
        yield client, pos
    finally:
        await pos_conn.close()
        await asyncio.wait_for(asyncio.gather(*tasks), 5)


async def initialize(client: PaymentTerminalClient, name: str = "test checkout") -> None:
    await client.initialize(
        pm.InitializeInput(protocol_version=pm.ProtocolVersion.V1, pos_name=name)
    )
    await client.initialized()


async def test_payment_with_callbacks_and_exact_decimals() -> None:
    async with running() as (client, pos):
        await client.ping()
        await initialize(client)
        result = await client.start_payment(start("test-1", "12345678901234567.00"))
        assert isinstance(result.outcome, pm.PaymentOutcomeApproved)
        assert result.outcome.approved.authorization_code == "TEST-OK"
        assert pos.phases == [pm.PaymentPhase.INSERT_CARD]
        assert pos.displayed == ["I am checking the test payment."]
        status = await client.payment_status(pm.PaymentIdInput(payment_id="test-1"))
        assert isinstance(status, pm.PaymentOutcomeApproved)
        receipt = await client.get_receipt(pm.PaymentIdInput(payment_id="test-1"))
        assert str(receipt.total.amount) == "12345678901234567.00"
        refund = await client.refund_payment(
            pm.RefundInput(payment_id="test-1", amount=usd("2.50"))
        )
        assert str(refund.amount.amount) == "2.50"
        with pytest.raises(RefundExceedsAmount) as exceeded:
            await client.refund_payment(
                pm.RefundInput(payment_id="test-1", amount=usd("12345678901234568.00"))
            )
        assert str(exceeded.value.data.maximum.amount) == "12345678901234567.00"
        await client.void_payment(pm.PaymentIdInput(payment_id="test-1"))
        await client.shutdown()
        await client.exit()


async def test_modeled_error_and_refusals() -> None:
    async with running() as (client, _):
        with pytest.raises(PosRpcError) as refused:
            await client.payment_status(pm.PaymentIdInput(payment_id="test-1"))
        assert refused.value.code == 1007
        await initialize(client, "test checkout (no payment)")
        with pytest.raises(PosRpcError) as local:
            await client.start_payment(start("test-1", "20.00"))
        assert local.value.code == 1008
        with pytest.raises(PosRpcError) as remote:
            await client.start_payment(start("test-1", "20.00"), checked=False)
        assert remote.value.code == 1008
    async with running() as (client, _):
        await initialize(client)
        with pytest.raises(CardDeclined) as declined:
            await client.start_payment(start("test-13", "1.13"))
        assert declined.value.data.reason == "test decline"


async def test_cancel_during_a_long_payment() -> None:
    async with running() as (client, pos):
        pos.cancel = True
        await initialize(client)
        with pytest.raises(PosRpcError) as cancelled:
            await asyncio.wait_for(client.start_payment(start("test-cancel", "1.17")), 5)
        assert cancelled.value.code == -32800
        await client.shutdown()

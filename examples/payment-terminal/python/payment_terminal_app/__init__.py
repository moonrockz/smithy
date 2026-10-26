"""The sample payment terminal.

Its rules depend only on the input, so every language gives the same messages.
All card values are masked test data. The MoonBit sample in
`examples/payment-terminal/moonbit/sample/terminal.mbt` has the same rules.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from decimal import Context, Decimal

from payment_terminal import errors, models
from payment_terminal._runtime import CallContext, Timestamp
from payment_terminal.client import PointOfSaleClient

CREATED_AT = 1792886400
"""The `createdAt` value of each transaction, in epoch seconds."""


def usd(text: str) -> models.Money:
    return models.Money(amount=Decimal(text), currency=models.Currency.USD)


def cents(amount: Decimal) -> str:
    """The cents of an amount with the point, such as `.13` for `1.13`, or ""."""
    text = str(amount)
    at = text.rfind(".")
    return text[at:] if at >= 0 else ""


def add_exact(a: Decimal, b: Decimal) -> Decimal:
    """The exact sum of two decimals. The result has the larger number of fraction digits."""
    digits = len(a.as_tuple().digits) + len(b.as_tuple().digits) + 2
    return Context(prec=digits).add(a, b)


@dataclass
class StoredPayment:
    """A payment that the terminal approved, kept for status, receipt, refund and void."""

    amount: models.Money
    outcome: models.PaymentOutcome


@dataclass
class Terminal:
    """The handler of the sample terminal. Each session has its own terminal."""

    payments: dict[str, StoredPayment] = field(default_factory=dict[str, StoredPayment])
    order: list[str] = field(default_factory=list[str])

    def stored(self, payment_id: str) -> StoredPayment:
        payment = self.payments.get(payment_id)
        if payment is None:
            raise errors.PaymentNotFound(errors.PaymentNotFoundData(payment_id=payment_id))
        return payment

    async def initialize(
        self, input: models.InitializeInput, context: CallContext
    ) -> models.InitializeOutput:
        if input.pos_name.endswith("(no payment)"):
            capabilities = models.Capabilities(payment=False)
        else:
            capabilities = models.Capabilities(
                payment=True,
                swipe=True,
                chip=True,
                contactless=True,
                pin=True,
                tips=True,
                signature=True,
                progress=True,
                cancellation=True,
            )
        return models.InitializeOutput(
            protocol_version=models.ProtocolVersion.V1,
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
        self, input: models.StartPaymentInput, context: CallContext
    ) -> models.PaymentOutput:
        pos = PointOfSaleClient(context.peer)
        payment_id = input.payment_id

        async def progress(phase: models.PaymentPhase) -> None:
            await pos.payment_progress(
                models.PaymentProgressInput(request_id=context.id_json(), phase=phase)
            )

        match cents(input.amount.amount):
            case ".13":
                raise errors.CardDeclined(errors.CardDeclinedData(reason="test decline"))
            case ".14":
                raise errors.CardRemoved()
            case ".15":
                raise errors.TerminalBusy(errors.TerminalBusyData(retry_after_seconds=1))
            case ".16":
                raise errors.Timeout()
            case ".17":
                # Wait for the POS to cancel the call. The runtime answers it.
                await progress(models.PaymentPhase.INSERT_CARD)
                await asyncio.sleep(60)
                raise errors.Timeout()
            case ".21":
                outcome: models.PaymentOutcome = models.PaymentOutcomeDeclined(
                    declined=models.Declined(reason="test decline")
                )
                return models.PaymentOutput(payment_id=payment_id, outcome=outcome)
            case ".22":
                outcome = models.PaymentOutcomePartiallyApproved(
                    partially_approved=models.PartiallyApproved(authorized_amount=usd("1.00"))
                )
                return models.PaymentOutput(payment_id=payment_id, outcome=outcome)
            case _:
                await progress(models.PaymentPhase.INSERT_CARD)
                await progress(models.PaymentPhase.ENTER_PIN)
                await pos.confirm_tip(
                    models.ConfirmTipInput(payment_id=payment_id, amount=usd("2.50"))
                )
                await pos.request_signature(
                    models.RequestSignatureInput(
                        payment_id=payment_id, prompt="Sign the test receipt"
                    )
                )
                await pos.display(models.DisplayInput(message="I am checking the test payment."))
                await progress(models.PaymentPhase.AUTHORIZING)
                outcome = models.PaymentOutcomeApproved(
                    approved=models.Approved(authorization_code="TEST-OK")
                )
                if payment_id not in self.payments:
                    self.order.append(payment_id)
                self.payments[payment_id] = StoredPayment(input.amount, outcome)
                return models.PaymentOutput(payment_id=payment_id, outcome=outcome)

    async def payment_status(
        self, input: models.PaymentIdInput, context: CallContext
    ) -> models.PaymentOutcome:
        return self.stored(input.payment_id).outcome

    async def refund_payment(
        self, input: models.RefundInput, context: CallContext
    ) -> models.RefundOutput:
        stored = self.stored(input.payment_id)
        if input.amount.amount > stored.amount.amount:
            raise errors.RefundExceedsAmount(
                errors.RefundExceedsAmountData(payment_id=input.payment_id, maximum=stored.amount)
            )
        return models.RefundOutput(refund_id="test-refund", amount=input.amount)

    async def void_payment(self, input: models.PaymentIdInput, context: CallContext) -> None:
        self.stored(input.payment_id)
        del self.payments[input.payment_id]

    async def get_receipt(
        self, input: models.PaymentIdInput, context: CallContext
    ) -> models.Receipt:
        stored = self.stored(input.payment_id)
        tip = usd("2.50")
        total = models.Money(
            amount=add_exact(stored.amount.amount, tip.amount), currency=stored.amount.currency
        )
        return models.Receipt(
            payment_id=input.payment_id,
            merchant=models.Merchant(name="Test shop", address="Test street"),
            lines=[
                models.ReceiptLine(label="Test item", amount=stored.amount),
                models.ReceiptLine(label="Test tip", amount=tip),
            ],
            total=total,
            customer_copy=True,
        )

    async def list_transactions(
        self, input: models.ListTransactionsInput, context: CallContext
    ) -> models.ListTransactionsOutput:
        if input.next_token is not None:
            return models.ListTransactionsOutput(transactions=[])
        transactions = [
            models.Transaction(
                payment_id=payment_id,
                created_at=Timestamp(CREATED_AT),
                amount=self.payments[payment_id].amount,
                labels={"checkout": "test", "card": "**** 4242"},
            )
            for payment_id in self.order
            if payment_id in self.payments
        ]
        return models.ListTransactionsOutput(transactions=transactions, next_token="test-page-2")

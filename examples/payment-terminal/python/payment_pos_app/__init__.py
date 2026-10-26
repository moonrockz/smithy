"""The sample POS and its scenarios.

Each language runs the same steps and the same checks. The MoonBit sample in
`examples/payment-terminal/moonbit/sample/pos.mbt` is the reference.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from decimal import Decimal

from payment_pos import errors, models
from payment_pos._runtime import CallContext, RpcError, Timestamp
from payment_pos.client import PaymentTerminalClient

SCENARIOS = ("payment", "errors", "cancellation", "refusals")


class ScenarioError(Exception):
    """A failed check of a scenario."""


def check(condition: bool, message: str) -> None:
    if not condition:
        raise ScenarioError(message)


class Pos:
    """The POS side of a scenario: it answers the terminal's callbacks and, in the
    cancellation scenario, cancels the payment on its first progress."""

    def __init__(self, scenario: str) -> None:
        self.scenario = scenario
        self.cancel_sent = False
        self.phases: list[str] = []
        self.messages: list[str] = []

    async def payment_progress(
        self, input: models.PaymentProgressInput, context: CallContext
    ) -> None:
        self.phases.append(input.phase.value)
        if self.scenario == "cancellation" and not self.cancel_sent:
            self.cancel_sent = True
            client = PaymentTerminalClient(context.peer)
            await client.cancel_request(models.CancelRequestInput(id=input.request_id))

    async def confirm_tip(self, input: models.ConfirmTipInput, context: CallContext) -> bool:
        return True

    async def request_signature(
        self, input: models.RequestSignatureInput, context: CallContext
    ) -> bytes:
        return b"test-signature"

    async def display(self, input: models.DisplayInput, context: CallContext) -> None:
        self.messages.append(input.message)


def usd(text: str) -> models.Money:
    return models.Money(amount=Decimal(text), currency=models.Currency.USD)


CARD = models.TestCard(masked_number="**** 4242")


def start(payment_id: str, amount: str, entry: models.EntryMethod) -> models.StartPaymentInput:
    return models.StartPaymentInput(payment_id=payment_id, amount=usd(amount), entry=entry)


async def initialize(client: PaymentTerminalClient, pos_name: str) -> models.InitializeOutput:
    output = await client.initialize(
        models.InitializeInput(protocol_version=models.ProtocolVersion.V1, pos_name=pos_name)
    )
    await client.initialized()
    return output


async def finish(client: PaymentTerminalClient) -> None:
    await client.shutdown()
    await client.exit()


async def refused_code(body: Callable[[], Awaitable[object]]) -> int | None:
    """Run `body` and give the code of the `RpcError` that it raises."""
    try:
        await body()
    except RpcError as error:
        return error.code
    except Exception:
        return None
    return None


async def run_scenario(pos: Pos, client: PaymentTerminalClient) -> None:
    """Run the scenario of `pos` with the client of a connected POS peer."""
    match pos.scenario:
        case "payment":
            await payment(pos, client)
        case "errors":
            await errors_scenario(client)
        case "cancellation":
            await cancellation(pos, client)
        case "refusals":
            await refusals(client)
        case other:
            raise ScenarioError(f"I do not know the scenario `{other}`.")


async def payment(pos: Pos, client: PaymentTerminalClient) -> None:
    await client.ping()
    output = await initialize(client, "test checkout")
    check(output.capabilities.payment is True, "I expected payment.")
    paid = await client.start_payment(start("test-1", "20.00", models.EntryMethodChip(chip=CARD)))
    check(
        isinstance(paid.outcome, models.PaymentOutcomeApproved)
        and paid.outcome.approved.authorization_code == "TEST-OK",
        f"I expected an approved payment, found {paid.outcome!r}.",
    )
    check(
        pos.phases == ["insertCard", "enterPin", "authorizing"],
        f"I expected three progress phases, found {', '.join(pos.phases)}.",
    )
    check(
        pos.messages == ["I am checking the test payment."],
        f"I expected one display message, found {', '.join(pos.messages)}.",
    )
    status = await client.payment_status(models.PaymentIdInput(payment_id="test-1"))
    check(isinstance(status, models.PaymentOutcomeApproved), "I expected the approved status.")
    receipt = await client.get_receipt(models.PaymentIdInput(payment_id="test-1"))
    lines = [f"{line.label}={line.amount.amount}" for line in receipt.lines]
    check(
        receipt.payment_id == "test-1"
        and receipt.merchant.name == "Test shop"
        and receipt.merchant.address == "Test street"
        and lines == ["Test item=20.00", "Test tip=2.50"]
        and str(receipt.total.amount) == "22.50"
        and receipt.customer_copy is True,
        "I expected the receipt of test-1 with 20.00 and 2.50 and the total 22.50, "
        f"found {', '.join(lines)} and the total {receipt.total.amount}.",
    )
    first = await client.list_transactions(models.ListTransactionsInput(since=Timestamp(0)))
    check(first.next_token == "test-page-2", "I expected the next page token.")
    second = await client.list_transactions(models.ListTransactionsInput(next_token="test-page-2"))
    check(not second.transactions, "I expected an empty second page.")
    refund = await client.refund_payment(
        models.RefundInput(payment_id="test-1", amount=usd("2.50"))
    )
    check(
        str(refund.amount.amount) == "2.50",
        f"I expected the exact refund amount 2.50, found {refund.amount.amount}.",
    )
    await client.void_payment(models.PaymentIdInput(payment_id="test-1"))
    await finish(client)


async def errors_scenario(client: PaymentTerminalClient) -> None:
    await initialize(client, "test checkout")

    async def expect_error(
        amount: str,
        entry: models.EntryMethod,
        what: str,
        matches: Callable[[Exception], bool],
    ) -> None:
        try:
            result = await client.start_payment(start("test-error", amount, entry))
        except Exception as error:
            check(matches(error), f"I expected {what} for {amount}, found {error!r}.")
            return
        raise ScenarioError(f"I expected {what} for {amount}, found {result!r}.")

    await expect_error(
        "1.13",
        models.EntryMethodSwipe(swipe=CARD),
        "CardDeclined",
        lambda e: isinstance(e, errors.CardDeclined) and e.data.reason == "test decline",
    )
    await expect_error(
        "1.14",
        models.EntryMethodContactless(contactless=CARD),
        "CardRemoved",
        lambda e: isinstance(e, errors.CardRemoved),
    )
    await expect_error(
        "1.15",
        models.EntryMethodManualEntry(manual_entry=CARD),
        "TerminalBusy",
        lambda e: isinstance(e, errors.TerminalBusy) and e.data.retry_after_seconds == 1,
    )
    await expect_error(
        "1.16",
        models.EntryMethodChip(chip=CARD),
        "Timeout",
        lambda e: isinstance(e, errors.Timeout),
    )
    declined = await client.start_payment(
        start("test-declined", "1.21", models.EntryMethodChip(chip=CARD))
    )
    check(
        isinstance(declined.outcome, models.PaymentOutcomeDeclined)
        and declined.outcome.declined.reason == "test decline",
        "I expected a declined outcome.",
    )
    partial = await client.start_payment(
        start("test-partial", "1.22", models.EntryMethodChip(chip=CARD))
    )
    if not isinstance(partial.outcome, models.PaymentOutcomePartiallyApproved):
        raise ScenarioError("I expected a partially approved outcome.")
    authorized = partial.outcome.partially_approved.authorized_amount.amount
    check(str(authorized) == "1.00", "I expected the authorized amount 1.00.")
    big = await client.start_payment(
        start("test-big", "12345678901234567.00", models.EntryMethodChip(chip=CARD))
    )
    check(
        isinstance(big.outcome, models.PaymentOutcomeApproved),
        "I expected the big payment approved.",
    )
    maximum_text = ""
    try:
        await client.refund_payment(
            models.RefundInput(payment_id="test-big", amount=usd("12345678901234568.00"))
        )
    except errors.RefundExceedsAmount as error:
        maximum_text = str(error.data.maximum.amount)
    except Exception as error:
        raise ScenarioError("I expected RefundExceedsAmount for test-big.") from error
    check(
        maximum_text == "12345678901234567.00",
        f"I expected the exact maximum 12345678901234567.00, found `{maximum_text}`.",
    )
    missing = ""
    try:
        await client.void_payment(models.PaymentIdInput(payment_id="test-missing"))
    except errors.PaymentNotFound as error:
        missing = error.data.payment_id
    except Exception as error:
        raise ScenarioError("I expected PaymentNotFound for test-missing.") from error
    check(missing == "test-missing", "I expected PaymentNotFound.")
    await finish(client)


async def cancellation(pos: Pos, client: PaymentTerminalClient) -> None:
    await initialize(client, "test checkout")
    code = await refused_code(
        lambda: client.start_payment(
            start("test-cancel", "12345678901234567.17", models.EntryMethodChip(chip=CARD))
        )
    )
    check(code == -32800, f"I expected the cancel code -32800, found {code or 'no error'}.")
    check(pos.cancel_sent, "I expected that the POS sent a cancel.")
    await finish(client)


async def refusals(client: PaymentTerminalClient) -> None:
    def status(checked: bool) -> Callable[[], Awaitable[object]]:
        return lambda: client.payment_status(
            models.PaymentIdInput(payment_id="test-1"), checked=checked
        )

    def pay(checked: bool) -> Callable[[], Awaitable[object]]:
        return lambda: client.start_payment(
            start("test-1", "20.00", models.EntryMethodChip(chip=CARD)), checked=checked
        )

    check(
        await refused_code(status(True)) == 1007,
        "I expected a local state refusal before initialize.",
    )
    check(
        await refused_code(status(False)) == 1007,
        "I expected the terminal to refuse payment.status before initialize.",
    )
    output = await initialize(client, "test checkout (no payment)")
    check(output.capabilities.payment is False, "I expected payment to be off.")
    check(await refused_code(pay(True)) == 1008, "I expected a local capability refusal.")
    check(
        await refused_code(pay(False)) == 1008,
        "I expected the terminal to refuse payment.start without the capability.",
    )
    await client.shutdown()
    check(
        await refused_code(status(True)) == 1007,
        "I expected a local state refusal after shutdown.",
    )
    check(
        await refused_code(status(False)) == 1007,
        "I expected the terminal to refuse payment.status after shutdown.",
    )
    await client.exit()


def describe(error: BaseException) -> str:
    """A short text for an error of a scenario."""
    if isinstance(error, ScenarioError):
        return str(error)
    if isinstance(error, RpcError):
        return f"error {error.code}: {error.message}"
    return f"an unexpected error: {error!r}"

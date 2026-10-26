from __future__ import annotations

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from decimal import Decimal
from pathlib import Path

import pytest
from pydantic import BaseModel

from smithy_jsonrpc_runtime import (
    BigDecimal,
    CallContext,
    DecodeError,
    JsonValue,
    MemoryConnection,
    MethodKind,
    Peer,
    RpcError,
    TranscriptLog,
    json_codec,
    memory_pair,
)

from .payment import Terminal, running_pair, session_rules, usd

INIT: JsonValue = {"protocolVersion": "1", "posName": "test checkout"}
CHIP: JsonValue = {"chip": {"maskedNumber": "**** 4242"}}


def start_params(payment_id: str, amount: str, entry: JsonValue = CHIP) -> JsonValue:
    return {"paymentId": payment_id, "amount": usd(amount), "entry": entry}


async def test_payment_flow_with_callbacks_and_exact_decimals(tmp_path: Path) -> None:
    log_path = tmp_path / "pos.jsonl"
    with TranscriptLog.open(log_path) as log:
        async with running_pair(pos_log=log) as pair:
            pos = pair.pos.peer
            assert await pos.request("terminal.ping", None) is None
            init = await pos.request("terminal.initialize", INIT)
            assert isinstance(init, dict) and init["terminalId"] == "test-terminal"
            await pos.notify("terminal.initialized", None)
            result = await pos.request("payment.start", start_params("test-1", "20.00"))
            assert result == {
                "paymentId": "test-1",
                "outcome": {"approved": {"authorizationCode": "TEST-OK"}},
            }
            assert [phase for _, phase in pair.pos.progress] == [
                "insertCard",
                "enterPin",
                "authorizing",
            ]
            assert pair.pos.displayed == ["I am checking the test payment."]
            assert pos.session.state == "ready"
            assert await pos.request("payment.status", {"paymentId": "test-1"}) == {
                "approved": {"authorizationCode": "TEST-OK"}
            }
            refund = await pos.request(
                "payment.refund", {"paymentId": "test-1", "amount": usd("2.50")}
            )
            assert isinstance(refund, dict) and isinstance(refund["amount"], dict)
            assert str(refund["amount"]["amount"]) == "2.50"
            assert await pos.request("payment.void", {"paymentId": "test-1"}) is None
            assert await pos.request("terminal.shutdown", None) is None
            await pos.notify("terminal.exit", None)
            await asyncio.wait_for(pair.terminal.exited.wait(), 5)
            assert pos.session.state == "stopped"
            assert pair.terminal.peer.session.state == "stopped"
    lines = log_path.read_text(encoding="utf-8").splitlines()
    records = [json_codec.loads(line) for line in lines]
    assert all(isinstance(r, dict) and r["dir"] in ("send", "recv") for r in records)
    assert '"amount":{"amount":20.00,"currency":"USD"}' in lines[5]
    assert any('"amount":2.50' in line for line in lines if line.startswith('{"dir":"recv"'))
    progress = [line for line in lines if '"payment.progress"' in line]
    assert progress and all('"requestId":3' in line for line in progress)
    callback = next(line for line in lines if '"pos.confirmTip"' in line)
    assert callback.startswith('{"dir":"recv","message":{"jsonrpc":"2.0","id":1,')


async def test_progress_and_callbacks_are_related_to_the_running_call() -> None:
    async with running_pair() as pair:
        pos = pair.pos.peer
        await pos.request("terminal.initialize", INIT)
        await pos.notify("terminal.initialized", None)
        await pos.request("payment.start", start_params("test-1", "20.00"))
        sent = pair.terminal_conn.sent
        related = {text: rel for text, rel in sent}
        callbacks = [rel for text, rel in sent if '"pos.' in text or "payment.progress" in text]
        assert callbacks and all(rel is not None and rel.value == 2 for rel in callbacks)
        result = next(text for text in related if '"TEST-OK"' in text)
        assert related[result] is not None
        assert pair.pos.progress[0] == (2, "insertCard")


async def test_refusals_are_local_when_checked_and_remote_when_unchecked() -> None:
    async with running_pair() as pair:
        pos = pair.pos.peer
        sent = pair.pos_conn.sent
        with pytest.raises(RpcError) as local:
            await pos.request("payment.status", {"paymentId": "test-1"})
        assert (local.value.code, local.value.message) == (
            1007,
            "I refused payment.status in state starting.",
        )
        assert sent == []
        with pytest.raises(RpcError) as remote:
            await pos.request("payment.status", {"paymentId": "test-1"}, checked=False)
        assert (remote.value.code, remote.value.message) == (
            1007,
            "I refused payment.status in state starting.",
        )
        assert len(sent) == 1
        init = await pos.request(
            "terminal.initialize", {"protocolVersion": "1", "posName": "test checkout (no payment)"}
        )
        assert isinstance(init, dict) and init["capabilities"] == {"payment": False}
        await pos.notify("terminal.initialized", None)
        count = len(sent)
        with pytest.raises(RpcError) as no_capability:
            await pos.request("payment.start", start_params("test-1", "20.00"))
        assert no_capability.value.code == 1008
        assert no_capability.value.message == (
            "I refused payment.start because payment is not advertised."
        )
        assert len(sent) == count
        with pytest.raises(RpcError) as remote_capability:
            await pos.request("payment.start", start_params("test-1", "20.00"), checked=False)
        assert remote_capability.value.code == 1008
        assert pos.session.state == "ready"
        assert pair.terminal.peer.session.state == "ready"
        assert await pos.request("terminal.shutdown", None) is None
        with pytest.raises(RpcError) as stopping:
            await pos.request("payment.status", {"paymentId": "test-1"})
        assert stopping.value.message == "I refused payment.status in state stopping."
        with pytest.raises(RpcError) as remote_stopping:
            await pos.request("payment.status", {"paymentId": "test-1"}, checked=False)
        assert remote_stopping.value.code == 1007
        await pos.notify("terminal.exit", None)
        await asyncio.wait_for(pair.terminal.exited.wait(), 5)


async def test_cancel_notification_cancels_the_running_handler() -> None:
    async with running_pair() as pair:
        pair.pos.cancel_on_progress = True
        pos = pair.pos.peer
        await pos.request("terminal.initialize", INIT)
        await pos.notify("terminal.initialized", None)
        with pytest.raises(RpcError) as cancelled:
            await asyncio.wait_for(
                pos.request("payment.start", start_params("test-cancel", "12345678901234567.17")),
                5,
            )
        assert (cancelled.value.code, cancelled.value.message) == (
            -32800,
            "I cancelled payment.start.",
        )
        assert pair.terminal.cancelled == ["test-cancel"]
        assert pos.session.state == "ready"
        assert pair.terminal.peer.session.state == "ready"
        texts = [text for text, _ in pair.pos_conn.sent]
        assert '"amount":12345678901234567.17' in texts[2]
        assert texts[3] == '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":2}}'
        assert await pos.request("terminal.shutdown", None) is None


async def test_callback_runs_while_the_call_runs() -> None:
    conn_a, conn_b = memory_pair()
    rules = session_rules()
    server = Peer(self_name="terminal", remote_name="pos", rules=rules)
    client = Peer(self_name="pos", remote_name="terminal", rules=rules)
    order: list[str] = []

    async def ask(params: JsonValue | None, ctx: CallContext) -> JsonValue:
        order.append("call started")
        answer = await ctx.request("pos.echo", params)
        order.append("callback answered")
        return answer

    async def echo(params: JsonValue | None, ctx: CallContext) -> JsonValue:
        order.append("callback ran")
        return params

    server.on_request("test.ask", MethodKind.REQUEST_ONLY, ask)
    client.on_request("pos.echo", MethodKind.REQUEST_ONLY, echo)
    tasks = [asyncio.create_task(server.run(conn_a)), asyncio.create_task(client.run(conn_b))]
    assert await client.request("test.ask", {"x": Decimal("1.10")}) == {"x": Decimal("1.10")}
    assert order == ["call started", "callback ran", "callback answered"]
    await conn_b.close()
    await asyncio.gather(*tasks)


@asynccontextmanager
async def raw_terminal() -> AsyncGenerator[tuple[MemoryConnection, Terminal], None]:
    """A terminal peer, and the raw end of its connection."""
    raw, conn = memory_pair()
    terminal = Terminal(Peer(self_name="terminal", remote_name="pos", rules=session_rules()))
    terminal.register()

    class Strict(BaseModel):
        amount: BigDecimal

    async def decode(params: JsonValue | None, ctx: CallContext) -> JsonValue:
        if params == {"path": True}:
            raise DecodeError(path="/amount", message="I expected a number; I found a string.")
        Strict.model_validate(params)
        return None

    async def boom(params: JsonValue | None, ctx: CallContext) -> JsonValue:
        raise RuntimeError("the test failure")

    terminal.peer.on_request("test.decode", MethodKind.REQUEST_ONLY, decode)
    terminal.peer.on_request("test.boom", MethodKind.REQUEST_OR_NOTIFICATION, boom)
    task = asyncio.create_task(terminal.peer.run(conn))
    try:
        yield raw, terminal
    finally:
        await raw.close()
        await asyncio.wait_for(task, 5)


async def exchange(raw: MemoryConnection, text: str) -> JsonValue:
    await raw.send(text)
    reply = await asyncio.wait_for(raw.receive(), 5)
    assert reply is not None
    return json_codec.loads(reply)


async def test_string_and_large_integer_ids_are_kept_exactly() -> None:
    async with raw_terminal() as (raw, _):
        await raw.send('{"jsonrpc":"2.0","id":900719925474099312345,"method":"terminal.ping"}')
        reply = await asyncio.wait_for(raw.receive(), 5)
        assert reply == '{"jsonrpc":"2.0","id":900719925474099312345,"result":null}'
        await raw.send('{"jsonrpc":"2.0","id":"payment-1","method":"terminal.ping"}')
        reply = await asyncio.wait_for(raw.receive(), 5)
        assert reply == '{"jsonrpc":"2.0","id":"payment-1","result":null}'


async def test_a_batch_gets_one_invalid_request_error_with_a_null_id() -> None:
    async with raw_terminal() as (raw, _):
        batch = '[{"jsonrpc":"2.0","id":1,"method":"terminal.ping"},{"jsonrpc":"2.0","id":2}]'
        assert await exchange(raw, batch) == {
            "jsonrpc": "2.0",
            "id": None,
            "error": {
                "code": -32600,
                "message": "I do not accept a batch; I received a JSON array.",
            },
        }
        assert await exchange(raw, '{"jsonrpc":"2.0","id":3,"method":"terminal.ping"}') == {
            "jsonrpc": "2.0",
            "id": 3,
            "result": None,
        }


@pytest.mark.parametrize(
    ("text", "code", "message"),
    [
        ("{oops", -32700, "I could not parse the message as JSON"),
        ('"text"', -32600, 'I expected a valid JSON-RPC 2.0 request; I found the string "text".'),
        (
            '{"jsonrpc":"1.0","id":1,"method":"terminal.ping"}',
            -32600,
            'I expected a valid JSON-RPC 2.0 request; I found the jsonrpc member the string "1.0".',
        ),
        (
            '{"jsonrpc":"2.0","id":1.5,"method":"terminal.ping"}',
            -32600,
            "I expected a valid JSON-RPC 2.0 request; I found the id the number 1.5.",
        ),
        (
            '{"jsonrpc":"2.0","id":1,"method":"terminal.ping","params":3}',
            -32600,
            "I expected a valid JSON-RPC 2.0 request; I found the params the number 3.",
        ),
        (
            '{"jsonrpc":"2.0","id":1,"method":"test.missing"}',
            -32601,
            "I do not know method test.missing.",
        ),
        (
            '{"jsonrpc":"2.0","id":1,"method":"test.decode","params":{"amount":"1"}}',
            -32602,
            "I could not decode test.decode params at /amount: ",
        ),
        (
            '{"jsonrpc":"2.0","id":1,"method":"test.decode","params":{"path":true}}',
            -32602,
            "I could not decode test.decode params at /amount: I expected a number;",
        ),
        (
            '{"jsonrpc":"2.0","id":1,"method":"test.boom"}',
            -32603,
            "I could not handle test.boom: the test failure",
        ),
        (
            '{"jsonrpc":"2.0","id":7,"method":"terminal.initialized"}',
            -32600,
            "I expected a notification for method terminal.initialized; I received a request.",
        ),
    ],
)
async def test_error_mapping(text: str, code: int, message: str) -> None:
    async with raw_terminal() as (raw, terminal):
        if "terminal.initialized" in text:
            await exchange(raw, '{"jsonrpc":"2.0","id":0,"method":"terminal.initialize"}')
        reply = await exchange(raw, text)
        assert isinstance(reply, dict)
        error = reply["error"]
        assert isinstance(error, dict)
        assert error["code"] == code
        assert isinstance(error["message"], str) and error["message"].startswith(message)
        expected_id = None if code in (-32700,) or "1.5" in text or text == '"text"' else 1
        if "terminal.initialized" in text:
            expected_id = 7
            assert terminal.peer.session.state == "ready"
        assert reply["id"] == expected_id


async def test_notification_to_a_request_method_is_dropped() -> None:
    async with raw_terminal() as (raw, terminal):
        await raw.send('{"jsonrpc":"2.0","method":"terminal.ping"}')
        await raw.send('{"jsonrpc":"2.0","method":"test.boom"}')
        await raw.send('{"jsonrpc":"2.0","method":"test.missing"}')
        assert await exchange(raw, '{"jsonrpc":"2.0","id":"after","method":"terminal.ping"}') == {
            "jsonrpc": "2.0",
            "id": "after",
            "result": None,
        }
        assert terminal.peer.session.state == "starting"


async def test_cancel_of_an_inactive_call_does_nothing() -> None:
    async with raw_terminal() as (raw, terminal):
        await exchange(raw, '{"jsonrpc":"2.0","id":1,"method":"terminal.initialize"}')
        await raw.send('{"jsonrpc":"2.0","method":"terminal.initialized"}')
        start = (
            '{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"p",'
            '"amount":{"amount":1.17,"currency":"USD"},"entry":{"chip":{}}}}'
        )
        await raw.send(start)
        progress = await asyncio.wait_for(raw.receive(), 5)
        assert progress is not None and '"insertCard"' in progress
        assert terminal.peer.session.state == "paying"
        await raw.send('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":99}}')
        assert await exchange(
            raw, '{"jsonrpc":"2.0","id":3,"method":"payment.status","params":{"paymentId":"p"}}'
        ) == {
            "jsonrpc": "2.0",
            "id": 3,
            "error": {
                "code": 1005,
                "message": "I found no test payment.",
                "data": {"paymentId": "p"},
            },
        }
        assert terminal.peer.session.state == "paying"


async def test_progress_for_an_unknown_call_is_dropped() -> None:
    async with running_pair() as pair:
        pos = pair.pos.peer
        await pos.request("terminal.initialize", INIT)
        await pos.notify("terminal.initialized", None)
        terminal = pair.terminal.peer
        task = asyncio.create_task(pos.request("payment.start", start_params("p", "1.17")))
        await pair.pos.wait_progress(1)
        await terminal.notify(
            "payment.progress", {"requestId": "missing", "phase": "authorizing"}, checked=False
        )
        await terminal.notify("payment.progress", {"requestId": 2, "phase": "enterPin"})
        await pair.pos.wait_progress(2)
        assert pair.pos.progress == [(2, "insertCard"), (2, "enterPin")]
        task.cancel()


async def test_pending_request_fails_when_the_connection_closes() -> None:
    conn_a, conn_b = memory_pair()
    peer = Peer(self_name="pos", remote_name="terminal", rules=session_rules())
    run = asyncio.create_task(peer.run(conn_a))
    call = asyncio.create_task(peer.request("terminal.ping", None))
    assert await asyncio.wait_for(conn_b.receive(), 5) is not None
    await conn_b.close()
    with pytest.raises(ConnectionError, match=r"terminal\.ping"):
        await asyncio.wait_for(call, 5)
    await run
    with pytest.raises(ConnectionError):
        await peer.request("terminal.ping", None)


async def test_modeled_error_data_passes_through() -> None:
    async with running_pair() as pair:
        pos = pair.pos.peer
        await pos.request("terminal.initialize", INIT)
        await pos.notify("terminal.initialized", None)
        with pytest.raises(RpcError) as declined:
            await pos.request("payment.start", start_params("d", "1.13"))
        assert (declined.value.code, declined.value.data) == (1001, "test decline")
        await pos.request("payment.start", start_params("test-big", "12345678901234567.00"))
        with pytest.raises(RpcError) as exceeded:
            await pos.request(
                "payment.refund", {"paymentId": "test-big", "amount": usd("12345678901234568.00")}
            )
        assert exceeded.value.code == 1006
        data = exceeded.value.data
        assert isinstance(data, dict) and isinstance(data["maximum"], dict)
        assert str(data["maximum"]["amount"]) == "12345678901234567.00"
        with pytest.raises(RpcError) as missing:
            await pos.request("payment.void", {"paymentId": "test-missing"})
        assert (missing.value.code, missing.value.data) == (1005, {"paymentId": "test-missing"})


async def test_cancel_buffered_with_its_request_settles_the_call() -> None:
    async with raw_terminal() as (raw, terminal):
        await exchange(raw, '{"jsonrpc":"2.0","id":1,"method":"terminal.initialize"}')
        await raw.send('{"jsonrpc":"2.0","method":"terminal.initialized"}')
        start = (
            '{"jsonrpc":"2.0","id":2,"method":"payment.start","params":{"paymentId":"p",'
            '"amount":{"amount":1.17,"currency":"USD"},"entry":{"chip":{}}}}'
        )
        # Both messages wait in the queue, so the read loop reads the cancel
        # before the task of the call runs.
        await raw.send(start)
        await raw.send('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":2}}')
        reply = json_codec.loads(await asyncio.wait_for(raw.receive(), 2) or "")
        assert reply == {
            "jsonrpc": "2.0",
            "id": 2,
            "error": {"code": -32800, "message": "I cancelled payment.start."},
        }
        assert terminal.peer.session.state == "ready"
        assert terminal.cancelled == []

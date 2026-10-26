from __future__ import annotations

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from decimal import Decimal

import httpx
import pytest

from smithy_jsonrpc_runtime import (
    CallContext,
    Connection,
    JsonValue,
    MethodKind,
    Peer,
    RpcError,
    json_codec,
)
from smithy_jsonrpc_runtime.http_client import HttpClientConnection, http_connect
from smithy_jsonrpc_runtime.server import RunningServer, start_server
from smithy_jsonrpc_runtime.ws_client import ws_connect

from .payment import Pos, Terminal, session_rules, usd

INIT: JsonValue = {"protocolVersion": "1", "posName": "test checkout"}
CHIP: JsonValue = {"chip": {"maskedNumber": "**** 4242"}}


def start_params(payment_id: str, amount: str) -> JsonValue:
    return {"paymentId": payment_id, "amount": usd(amount), "entry": CHIP}


def terminal_peer() -> Peer:
    terminal = Terminal(Peer(self_name="terminal", remote_name="pos", rules=session_rules()))
    terminal.register()

    async def poke(params: JsonValue | None, ctx: CallContext) -> None:
        await ctx.notify("pos.display", {"message": "I was poked."}, checked=False)

    terminal.peer.on_notification("test.poke", MethodKind.NOTIFICATION_ONLY, poke)
    return terminal.peer


@asynccontextmanager
async def server() -> AsyncGenerator[RunningServer, None]:
    running = await start_server(0, terminal_peer)
    try:
        yield running
    finally:
        await running.stop()


async def connect(transport: str, port: int) -> Connection:
    if transport == "http":
        return await http_connect(f"http://127.0.0.1:{port}/rpc")
    return await ws_connect(f"ws://127.0.0.1:{port}/ws")


@asynccontextmanager
async def pos_over(transport: str) -> AsyncGenerator[Pos, None]:
    async with server() as running:
        conn = await connect(transport, running.port)
        pos = Pos(Peer(self_name="pos", remote_name="terminal", rules=session_rules()))
        pos.register()
        task = asyncio.create_task(pos.peer.run(conn))
        try:
            yield pos
        finally:
            await conn.close()
            await asyncio.wait_for(task, 5)


@pytest.mark.parametrize("transport", ["http", "ws"])
async def test_payment_with_callbacks_and_progress(transport: str) -> None:
    async with pos_over(transport) as pos:
        peer = pos.peer
        assert await peer.request("terminal.ping", None) is None
        await peer.request("terminal.initialize", INIT)
        await peer.notify("terminal.initialized", None)
        result = await asyncio.wait_for(
            peer.request("payment.start", start_params("test-1", "12345678901234567.00")), 10
        )
        assert result == {
            "paymentId": "test-1",
            "outcome": {"approved": {"authorizationCode": "TEST-OK"}},
        }
        assert pos.progress == [(3, "insertCard"), (3, "enterPin"), (3, "authorizing")]
        assert pos.displayed == ["I am checking the test payment."]
        refund = await peer.request(
            "payment.refund", {"paymentId": "test-1", "amount": usd("2.50")}
        )
        assert isinstance(refund, dict) and isinstance(refund["amount"], dict)
        assert str(refund["amount"]["amount"]) == "2.50"
        assert await peer.request("terminal.shutdown", None) is None
        await peer.notify("terminal.exit", None)


@pytest.mark.parametrize("transport", ["http", "ws"])
async def test_cancel_and_refusal(transport: str) -> None:
    async with pos_over(transport) as pos:
        peer = pos.peer
        with pytest.raises(RpcError) as refused:
            await peer.request("payment.status", {"paymentId": "x"}, checked=False)
        assert refused.value.code == 1007
        await peer.request("terminal.initialize", INIT)
        await peer.notify("terminal.initialized", None)
        pos.cancel_on_progress = True
        with pytest.raises(RpcError) as cancelled:
            await asyncio.wait_for(
                peer.request("payment.start", start_params("test-cancel", "1.17")), 10
            )
        assert (cancelled.value.code, cancelled.value.message) == (
            -32800,
            "I cancelled payment.start.",
        )
        assert await peer.request("terminal.shutdown", None) is None


def events(body: str) -> list[str]:
    """The data of each event of an event stream."""
    return [line.removeprefix("data: ") for line in body.split("\n") if line.startswith("data: ")]


async def test_http_wire_rules() -> None:
    async with server() as running, httpx.AsyncClient() as client:
        url = f"http://127.0.0.1:{running.port}/rpc"
        accept = {"Accept": "application/json, text/event-stream"}
        first = await client.post(
            url,
            content='{"jsonrpc":"2.0","id":900719925474099312345,"method":"terminal.ping"}',
            headers=accept,
        )
        assert first.status_code == 200
        assert first.headers["content-type"].startswith("text/event-stream")
        assert first.text.startswith(": open\n\n")
        assert events(first.text) == ['{"jsonrpc":"2.0","id":900719925474099312345,"result":null}']
        session = {**accept, "Smithy-Session-Id": first.headers["Smithy-Session-Id"]}
        second = await client.post(
            url,
            content='{"jsonrpc":"2.0","id":"payment-1","method":"terminal.ping"}',
            headers=session,
        )
        assert events(second.text) == ['{"jsonrpc":"2.0","id":"payment-1","result":null}']
        assert second.headers["Smithy-Session-Id"] == session["Smithy-Session-Id"]
        poked = await client.post(
            url, content='{"jsonrpc":"2.0","method":"test.poke"}', headers=session
        )
        assert (poked.status_code, poked.text) == (202, "")
        third = await client.post(
            url, content='{"jsonrpc":"2.0","id":3,"method":"terminal.ping"}', headers=session
        )
        assert events(third.text) == [
            '{"jsonrpc":"2.0","method":"pos.display","params":{"message":"I was poked."}}',
            '{"jsonrpc":"2.0","id":3,"result":null}',
        ]
        batch = await client.post(url, content='[{"jsonrpc":"2.0","id":1}]', headers=session)
        assert batch.status_code == 200
        assert batch.headers["content-type"] == "application/json"
        assert json_codec.loads(batch.text) == {
            "jsonrpc": "2.0",
            "id": None,
            "error": {
                "code": -32600,
                "message": "I do not accept a batch; I received a JSON array.",
            },
        }
        broken = await client.post(url, content="{oops", headers=session)
        error = json_codec.loads(broken.text)
        assert isinstance(error, dict) and isinstance(error["error"], dict)
        assert error["error"]["code"] == -32700
        unknown = await client.post(
            url,
            content='{"jsonrpc":"2.0","id":1,"method":"terminal.ping"}',
            headers={"Smithy-Session-Id": "nobody"},
        )
        assert unknown.status_code == 404


async def test_http_client_reads_a_json_response() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.headers["Accept"] == "application/json, text/event-stream"
        assert request.headers["Content-Type"] == "application/json"
        body = json_codec.loads(request.content.decode())
        assert isinstance(body, dict)
        if "id" not in body:
            return httpx.Response(202, headers={"Smithy-Session-Id": "s1"})
        return httpx.Response(
            200,
            headers={"Smithy-Session-Id": "s1", "content-type": "application/json"},
            content=f'{{"jsonrpc":"2.0","id":{body["id"]},"result":{{"amount":20.00}}}}',
        )

    conn = HttpClientConnection(
        "http://test/rpc", httpx.AsyncClient(transport=httpx.MockTransport(respond))
    )
    peer = Peer(self_name="pos", remote_name="terminal", rules=session_rules())
    task = asyncio.create_task(peer.run(conn))
    assert await peer.request("terminal.ping", None) == {"amount": Decimal("20.00")}
    await peer.notify("test.note", None)
    assert conn.session_id == "s1"
    await conn.close()
    await asyncio.wait_for(task, 5)

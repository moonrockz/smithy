from __future__ import annotations

import asyncio
import io
import sys
from pathlib import Path

import pytest

from smithy_jsonrpc_runtime import (
    FramingError,
    Peer,
    RpcError,
    StdioConnection,
    json_codec,
    spawn_stdio,
)
from smithy_jsonrpc_runtime.stdio import encode_frame, read_frame, read_frame_blocking

from .payment import Pos, session_rules, usd

ROOT = Path(__file__).resolve().parent.parent


def reader_of(data: bytes) -> asyncio.StreamReader:
    reader = asyncio.StreamReader()
    reader.feed_data(data)
    reader.feed_eof()
    return reader


async def test_frames_carry_utf8_and_ignore_unknown_headers() -> None:
    text = '{"message":"é ✓"}'
    frame = encode_frame(text)
    assert frame.startswith(b"Content-Length: 20\r\n\r\n")
    other = (
        b"Content-Type: application/vscode-jsonrpc; charset=utf-8\r\ncontent-length: 2\r\n\r\n{}"
    )
    reader = reader_of(frame + other)
    assert await read_frame(reader) == text
    assert await read_frame(reader) == "{}"
    assert await read_frame(reader) is None
    stream = io.BytesIO(frame + other)
    assert read_frame_blocking(stream) == text
    assert read_frame_blocking(stream) == "{}"
    assert read_frame_blocking(stream) is None


@pytest.mark.parametrize(
    ("data", "message"),
    [
        (b"Content-Type: x\r\n\r\n{}", "I expected a Content-Length header"),
        (b"Content-Length: ten\r\n\r\n", "I expected a decimal Content-Length; I found 'ten'"),
        (b"Content-Length: 10\r\n\r\n{}", "I expected 10 body bytes; the stream ended after 2"),
        (b"Content-Length: 2\r\n", "I reached the end of the stream inside the headers"),
        (b"nonsense\r\n\r\n", "I expected a header with a colon; I found 'nonsense'"),
    ],
)
async def test_broken_frames_raise_framing_errors(data: bytes, message: str) -> None:
    with pytest.raises(FramingError, match=message):
        await read_frame(reader_of(data))
    with pytest.raises(FramingError, match=message):
        read_frame_blocking(io.BytesIO(data))


async def test_stdio_connection_reads_and_writes_frames() -> None:
    out = io.BytesIO()
    conn = StdioConnection(io.BytesIO(encode_frame('{"a":1}')), out)
    assert await conn.receive() == '{"a":1}'
    assert await conn.receive() is None
    await conn.send('{"b":2.50}')
    assert out.getvalue() == b'Content-Length: 10\r\n\r\n{"b":2.50}'
    await conn.close()
    with pytest.raises(ConnectionError):
        await conn.send("{}")


async def test_pos_drives_a_spawned_terminal_over_stdio(tmp_path: Path) -> None:
    log_path = tmp_path / "terminal.jsonl"
    conn = await spawn_stdio(
        [sys.executable, "-m", "tests.stdio_terminal", str(log_path)], cwd=ROOT
    )
    pos = Pos(Peer(self_name="pos", remote_name="terminal", rules=session_rules()))
    pos.register()
    run = asyncio.create_task(pos.peer.run(conn))
    peer = pos.peer
    with pytest.raises(RpcError) as refused:
        await peer.request("payment.status", {"paymentId": "test-1"}, checked=False)
    assert refused.value.code == 1007
    await peer.request("terminal.initialize", {"protocolVersion": "1", "posName": "test checkout"})
    await peer.notify("terminal.initialized", None)
    result = await asyncio.wait_for(
        peer.request(
            "payment.start",
            {
                "paymentId": "test-1",
                "amount": usd("12345678901234567.00"),
                "entry": {"chip": {"maskedNumber": "**** 4242"}},
            },
        ),
        10,
    )
    assert isinstance(result, dict) and result["paymentId"] == "test-1"
    assert len(pos.progress) == 3
    assert await peer.request("terminal.shutdown", None) is None
    await peer.notify("terminal.exit", None)
    await conn.close()
    assert await conn.wait() == 0
    await asyncio.wait_for(run, 5)
    lines = log_path.read_text(encoding="utf-8").splitlines()
    assert all(isinstance(json_codec.loads(line), dict) for line in lines)
    assert '"amount":12345678901234567.00' in lines[5]
    assert lines[-1] == '{"dir":"recv","message":{"jsonrpc":"2.0","method":"terminal.exit"}}'

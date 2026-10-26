"""The sample POS runs each scenario against the sample terminal over each transport."""

from __future__ import annotations

import asyncio
import socket
import sys
from decimal import Decimal
from pathlib import Path

import pytest

from payment_terminal_app import add_exact, cents

SCENARIOS = ["payment", "errors", "cancellation", "refusals"]
POS = [sys.executable, "-m", "payment_pos_app"]
TERMINAL = [sys.executable, "-m", "payment_terminal_app"]


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


async def run_pos(args: list[str]) -> tuple[int, str]:
    process = await asyncio.create_subprocess_exec(
        *POS, *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    out, err = await asyncio.wait_for(process.communicate(), 60)
    assert out == b"", "I expected no output on stdout."
    return process.returncode or 0, err.decode()


@pytest.mark.parametrize("scenario", SCENARIOS)
async def test_scenario_over_stdio(scenario: str, tmp_path: Path) -> None:
    pos_log = tmp_path / "pos.jsonl"
    terminal_log = tmp_path / "terminal.jsonl"
    code, err = await run_pos(
        [
            "--scenario",
            scenario,
            "--connect",
            "stdio",
            "--log",
            str(pos_log),
            "--",
            *TERMINAL,
            "stdio",
            "--log",
            str(terminal_log),
        ]
    )
    assert code == 0, err
    sent = pos_log.read_text().count('{"dir":"send"')
    received = terminal_log.read_text().count('{"dir":"recv"')
    assert sent == received > 0


@pytest.mark.parametrize("transport", ["http", "ws"])
@pytest.mark.parametrize("scenario", SCENARIOS)
async def test_scenario_over_a_server(transport: str, scenario: str, tmp_path: Path) -> None:
    port = free_port()
    terminal = await asyncio.create_subprocess_exec(
        *TERMINAL,
        "serve",
        "--port",
        str(port),
        "--log",
        str(tmp_path / "terminal.jsonl"),
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        assert terminal.stderr is not None
        line = await asyncio.wait_for(terminal.stderr.readline(), 30)
        assert line == f"listening {port}\n".encode()
        url = f"http://127.0.0.1:{port}/rpc" if transport == "http" else f"ws://127.0.0.1:{port}/ws"
        code, err = await run_pos(["--scenario", scenario, "--connect", url])
        assert code == 0, err
    finally:
        terminal.terminate()
        await terminal.wait()


async def test_bad_arguments_exit_with_2() -> None:
    code, err = await run_pos(["--scenario", "nothing", "--connect", "stdio"])
    assert code == 2
    assert "I expected --scenario with one of payment, errors, cancellation, refusals" in err


def test_terminal_rules_keep_exact_decimals() -> None:
    assert cents(Decimal("1.13")) == ".13"
    assert cents(Decimal("20")) == ""
    assert str(add_exact(Decimal("20.00"), Decimal("2.50"))) == "22.50"
    total = add_exact(Decimal("123456789012345678901234567890.00"), Decimal("2.5"))
    assert str(total) == "123456789012345678901234567892.50"

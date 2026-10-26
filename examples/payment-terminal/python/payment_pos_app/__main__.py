"""The sample POS program.

Usage: `python -m payment_pos_app --scenario NAME --connect TARGET [--log PATH]
[-- TERMINAL ARGV...]`. TARGET is `stdio` (start the terminal command after
`--`), `http://127.0.0.1:N/rpc` or `ws://127.0.0.1:N/ws`. The exit code is 0
when every check of the scenario passes. Diagnostics go to stderr only.
"""

from __future__ import annotations

import asyncio
import sys
from typing import NoReturn

from payment_pos import new_peer
from payment_pos._runtime import Connection, TranscriptLog, spawn_stdio
from payment_pos._runtime.http_client import http_connect
from payment_pos._runtime.ws_client import ws_connect
from payment_pos.client import PaymentTerminalClient
from payment_pos.handler import register_point_of_sale

from . import SCENARIOS, Pos, describe, run_scenario


def note(text: str) -> None:
    """Write a diagnostic line to stderr. Stdout can be the stdio transport."""
    sys.stderr.write(text + "\n")
    sys.stderr.flush()


def usage(message: str) -> NoReturn:
    note(f"pos: {message}")
    raise SystemExit(2)


async def run(args: list[str]) -> int:
    scenario = ""
    target = ""
    log_path: str | None = None
    terminal: list[str] = []
    index = 0
    while index < len(args):
        match args[index]:
            case "--scenario" if index + 1 < len(args):
                index += 1
                scenario = args[index]
            case "--connect" if index + 1 < len(args):
                index += 1
                target = args[index]
            case "--log" if index + 1 < len(args):
                index += 1
                log_path = args[index]
            case "--":
                terminal = args[index + 1 :]
                break
            case other:
                usage(f"I did not expect the argument `{other}`.")
        index += 1
    if scenario not in SCENARIOS:
        usage(f"I expected --scenario with one of {', '.join(SCENARIOS)}, found `{scenario}`.")
    if target == "stdio":
        if not terminal:
            usage("I expected the terminal command after `--`.")
    elif not target.startswith(("http://", "https://", "ws://", "wss://")):
        usage(f"I expected --connect stdio, an http:// URL or a ws:// URL, found `{target}`.")
    log = TranscriptLog.open(log_path) if log_path is not None else None
    try:
        peer = new_peer(log)
        pos = Pos(scenario)
        register_point_of_sale(peer, pos)
        client = PaymentTerminalClient(peer)
        if target == "stdio":
            process = await spawn_stdio(terminal)
            failed = await play(process, pos, client)
            status = await process.wait()
            if status != 0:
                note(f"pos: the terminal exited with status {status}.")
            return 1 if failed or status != 0 else 0
        conn: Connection
        if target.startswith(("http://", "https://")):
            conn = await http_connect(target)
        else:
            conn = await ws_connect(target)
        failed = await play(conn, pos, client)
        return 1 if failed else 0
    finally:
        if log is not None:
            log.close()


async def play(conn: Connection, pos: Pos, client: PaymentTerminalClient) -> bool:
    """Run the scenario while the peer reads the connection. It gives true when a check failed."""
    reader = asyncio.create_task(client.peer.run(conn))
    failed = False
    try:
        await run_scenario(pos, client)
    except Exception as error:
        note(f"pos: scenario failed: {describe(error)}")
        failed = True
    await conn.close()
    try:
        await asyncio.wait_for(reader, 10)
    except (TimeoutError, ConnectionError, OSError) as error:
        note(f"pos: the connection did not end cleanly: {error!r}")
    return failed


def main() -> None:
    raise SystemExit(asyncio.run(run(sys.argv[1:])))


if __name__ == "__main__":
    main()

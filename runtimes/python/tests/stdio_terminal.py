"""A terminal peer on stdio, for the spawn test. Run it with `python -m tests.stdio_terminal`."""

from __future__ import annotations

import asyncio
import sys

from smithy_jsonrpc_runtime import Peer, TranscriptLog, stdio_connection

from .payment import Terminal, session_rules


async def main() -> None:
    log = TranscriptLog.open(sys.argv[1]) if len(sys.argv) > 1 else None
    terminal = Terminal(
        Peer(self_name="terminal", remote_name="pos", rules=session_rules(), log=log)
    )
    terminal.register()
    await terminal.peer.run(stdio_connection())
    sys.stderr.write("terminal stopped\n")


if __name__ == "__main__":
    asyncio.run(main())

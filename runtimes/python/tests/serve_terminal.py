"""A terminal peer behind `serve`, for the stop test: `python -m tests.serve_terminal`."""

from __future__ import annotations

import asyncio

from smithy_jsonrpc_runtime import Peer
from smithy_jsonrpc_runtime.server import serve

from .payment import Terminal, session_rules


def terminal_peer() -> Peer:
    terminal = Terminal(Peer(self_name="terminal", remote_name="pos", rules=session_rules()))
    terminal.register()
    return terminal.peer


if __name__ == "__main__":
    asyncio.run(serve(0, terminal_peer))

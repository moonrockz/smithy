"""The sample terminal program.

Usage: `python -m payment_terminal_app stdio [--log PATH]` or
`python -m payment_terminal_app serve --port N [--log PATH]`. With `serve`, the
terminal serves `POST /rpc` and `GET /ws` on 127.0.0.1:N and writes
`listening N` to stderr when it is ready. Diagnostics go to stderr only.
"""

from __future__ import annotations

import asyncio
import sys
from typing import NoReturn

from payment_terminal import fastapi_app, new_peer
from payment_terminal._runtime import TranscriptLog, stdio_connection
from payment_terminal.handler import register_payment_terminal

from . import Terminal


def usage(message: str) -> NoReturn:
    sys.stderr.write(f"terminal: {message}\n")
    raise SystemExit(2)


async def run(args: list[str]) -> int:
    if not args or args[0] not in ("stdio", "serve"):
        usage(f"I expected the command stdio or serve, found `{' '.join(args[:1])}`.")
    command = args[0]
    port: int | None = None
    log_path: str | None = None
    index = 1
    while index < len(args):
        match args[index]:
            case "--log" if index + 1 < len(args):
                index += 1
                log_path = args[index]
            case "--port" if index + 1 < len(args) and command == "serve":
                index += 1
                text = args[index]
                if not text.isdigit() or int(text) > 65535:
                    usage(f"I expected a port number after --port, found `{text}`.")
                port = int(text)
            case other:
                usage(f"I did not expect the argument `{other}`.")
        index += 1
    log = TranscriptLog.open(log_path) if log_path is not None else None
    try:
        if command == "stdio":
            peer = new_peer(log)
            register_payment_terminal(peer, Terminal())
            await peer.run(stdio_connection())
        else:
            if port is None:
                usage("I expected --port N with serve.")
            await fastapi_app.serve(port, Terminal, log=log)
    finally:
        if log is not None:
            log.close()
    return 0


def main() -> None:
    raise SystemExit(asyncio.run(run(sys.argv[1:])))


if __name__ == "__main__":
    main()

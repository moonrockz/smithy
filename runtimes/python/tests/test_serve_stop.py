"""A requested stop ends `serve` normally, with exit code 0, on every platform."""

from __future__ import annotations

import asyncio
import re
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


async def test_a_stop_signal_ends_serve_with_exit_code_0() -> None:
    # The matrix runner stops a network receiver with SIGTERM on Unix and with
    # CTRL_BREAK on Windows. uvicorn raises the captured signal again after its
    # graceful shutdown: that gives -15 on Unix and 3 (the code of abort()) on
    # Windows. A stop that the server asked for is a normal end.
    if sys.platform == "win32":
        flags = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        flags = 0
    process = await asyncio.create_subprocess_exec(
        sys.executable,
        "-m",
        "tests.serve_terminal",
        cwd=ROOT,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE,
        creationflags=flags,
    )
    try:
        assert process.stderr is not None
        line = await asyncio.wait_for(process.stderr.readline(), 30)
        assert re.fullmatch(rb"listening [0-9]+\n", line), line
        if sys.platform == "win32":
            process.send_signal(signal.CTRL_BREAK_EVENT)
        else:
            process.send_signal(signal.SIGTERM)
        code = await asyncio.wait_for(process.wait(), 30)
        rest = await process.stderr.read()
        assert code == 0, rest.decode(errors="replace")
    finally:
        if process.returncode is None:
            process.kill()
            await process.wait()

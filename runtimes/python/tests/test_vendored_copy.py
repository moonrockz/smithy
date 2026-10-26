from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent / "smithy_jsonrpc_runtime"

PROGRAM = """
import asyncio
from decimal import Decimal
from payment_terminal._runtime import MethodKind, Peer, SessionRules, memory_pair

async def main() -> None:
    a, b = memory_pair()
    server = Peer(self_name="terminal", remote_name="pos", rules=SessionRules.none())
    client = Peer(self_name="pos", remote_name="terminal", rules=SessionRules.none())

    async def echo(params, ctx):
        return params

    server.on_request("test.echo", MethodKind.REQUEST_ONLY, echo)
    tasks = [asyncio.create_task(server.run(a)), asyncio.create_task(client.run(b))]
    result = await client.request("test.echo", {"amount": Decimal("20.00")})
    assert str(result["amount"]) == "20.00", result
    await b.close()
    await asyncio.gather(*tasks)

asyncio.run(main())
"""


def test_the_runtime_works_as_a_vendored_subpackage(tmp_path: Path) -> None:
    package = tmp_path / "payment_terminal"
    package.mkdir()
    (package / "__init__.py").write_text("", encoding="utf-8")
    shutil.copytree(SOURCE, package / "_runtime", ignore=shutil.ignore_patterns("__pycache__"))
    completed = subprocess.run(
        [sys.executable, "-c", PROGRAM],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
        env={**os.environ, "PYTHONPATH": str(tmp_path)},
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout == ""

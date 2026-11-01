#!/usr/bin/env python3
"""Run source tests without installing or starting Noctalia or Umbriel."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
commands = [
    ["lua", str(root / "tests/test_state.lua"), str(root)],
    ["lua", str(root / "tests/test_service.lua"), str(root)],
    [sys.executable, "-B", str(root / "tests/test_reader.py")],
    [sys.executable, "-B", str(root / "tests/test_manifest.py")],
    [sys.executable, "-B", str(root / "tests/test_actions.py")],
    ["lua", str(root / "tests/test_inline.lua"), str(root)],
    ["noctalia", "plugins", "lint", str(root)],
]
for command in commands:
    result = subprocess.run(command, cwd=root, env=env)
    if result.returncode:
        raise SystemExit(result.returncode)

#!/usr/bin/env python3
"""Read-only compatibility evidence for the audited installed executable.

This never invokes a daemon or loads a plugin. A different binary requires a new
audit, rather than carrying this conclusion forward from a version string.
"""
import hashlib
from pathlib import Path

binary = Path("/usr/bin/noctalia").read_bytes()
digest = hashlib.sha256(binary).hexdigest()
expected = "cee728de4f2b7cbc185f64e530a1c22a09301b58dc2914f310c30d3a99ffcd9f"
if digest != expected:
    raise SystemExit("Installed binary changed; API ceiling must be re-audited.")
# In this ELF, .text virtual addresses equal file offsets. Plugin loader guard:
# mov 0x240(%rsp),%eax; sub $3,%eax; cmp $40,%eax; jbe supported.
guard = bytes.fromhex("8b84244002000083e80383f8280f86")
assert binary[0x8FB11B:0x8FB11B + len(guard)] == guard
# Adjacent unsupported-plugin diagnostic arguments contain min=3, max=43.
assert binary[0x8FB174:0x8FB17F] == bytes.fromhex("c784247003000003000000")
assert binary[0x8FB18F:0x8FB19A] == bytes.fromhex("c78424800300002b000000")
print("Verified installed plugin loader accepts API 3 through 43 (binary inspection).")
print("SHA-256: " + digest)
print("Lattice declares API 43; no API 45 bindings are used.")

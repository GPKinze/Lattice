#!/usr/bin/env python3
"""Owned, read-only Umbriel subscription. Python standard library; Linux only.

No actions, CLI subprocesses, private logging, or desktop configuration access.
"""
import argparse
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import socket
import stat
import sys
import time

FAMILIES = ("workspaces", "windows", "outputs")
MAX_LINE = 1024 * 1024
MAX_HOST_LINE = 60 * 1024  # Noctalia v5.4.0 drops partial lines over 64 KiB.


class Reader:
    def __init__(self, socket_path, generation=0, parent_pid=None):
        self.socket_path = socket_path
        self.generation = generation
        self.parent_pid = os.getppid() if parent_pid is None else parent_pid
        self.running = True

    def alive(self):
        return self.running and os.getppid() == self.parent_pid

    def emit(self, event, **data):
        message = (json.dumps({"event": event, "data": dict(
            generation=self.generation, **data)}, ensure_ascii=False,
            separators=(",", ":"), allow_nan=False) + "\n").encode()
        if len(message) > MAX_HOST_LINE:
            self.emit("lattice.invalid", family=data.get("snapshot", {}).get("event"))
            return
        view = memoryview(message)
        while view and self.alive():
            _, writable, _ = select.select([], [sys.stdout.fileno()], [], 0.25)
            if writable:
                view = view[os.write(sys.stdout.fileno(), view):]

    def line(self, raw):
        family = None
        try:
            event = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
            if not isinstance(event, dict):
                raise ValueError()
            if "err" in event:
                raise ConnectionError()  # Subscription rejection: reconnect, never log its text.
            family = event.get("event")
            if family not in FAMILIES or not isinstance(event.get("data"), list):
                raise ValueError()
            # JSON null array elements can disappear when decoded into Luau
            # tables. Reject them before the host can mistake them for removals.
            if not all(isinstance(row, dict) for row in event["data"]):
                raise ValueError()
            self.emit("lattice.snapshot", snapshot=event)
        except (ValueError, UnicodeError, TypeError, RecursionError):
            self.emit("lattice.invalid", family=family if family in FAMILIES else None)

    def pause(self, seconds):
        deadline = time.monotonic() + seconds
        while self.alive() and time.monotonic() < deadline:
            time.sleep(min(0.1, max(0, deadline - time.monotonic())))

    def run(self):
        backoff = 0.25
        try:
            while self.alive():
                self.emit("lattice.transport", status="connecting")
                try:
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                        connection.settimeout(0.25)
                        connection.connect(self.socket_path)
                        connection.sendall(json.dumps({"cmd": "subscribe", "events": list(FAMILIES)}).encode() + b"\n")
                        self.generation += 1
                        self.emit("lattice.transport", status="connected")
                        pending = b""
                        heartbeat = time.monotonic()
                        connected_at = heartbeat
                        while self.alive():
                            try:
                                chunk = connection.recv(65536)
                                if not chunk:
                                    raise ConnectionError()
                                pending += chunk
                                while b"\n" in pending:
                                    line, pending = pending.split(b"\n", 1)
                                    if len(line) > MAX_LINE:
                                        raise ConnectionError()
                                    self.line(line)
                                if len(pending) > MAX_LINE:
                                    raise ConnectionError()
                            except socket.timeout:
                                pass
                            if time.monotonic() - heartbeat >= 1:
                                self.emit("lattice.heartbeat")
                                heartbeat = time.monotonic()
                            if time.monotonic() - connected_at >= 5:
                                backoff = 0.25
                except OSError:
                    pass
                if self.alive():
                    self.emit("lattice.transport", status="disconnected")
                    self.pause(backoff)
                    backoff = min(backoff * 2, 4)
        finally:
            if self.alive():
                self.emit("lattice.transport", status="stopped")


def parent_guard(reader):
    # Linux parent-death signal plus a race check and periodic getppid fallback.
    # Noctalia's runStream shell must exec us, never leave a shell between us.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
        raise OSError("parent protection unavailable")
    if not reader.alive():
        raise OSError("parent exited")
    def stop(_signum, _frame):
        reader.running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    os.set_blocking(sys.stdout.fileno(), False)


def acquire_lock(directory, socket_path):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise OSError("unsafe lock directory")
    key = hashlib.sha256(os.fsencode(socket_path)).hexdigest()[:24]
    fd = os.open(directory / (key + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise OSError("unsafe lock file")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except BaseException:
        os.close(fd)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket")  # Testability; the production service never overrides it.
    parser.add_argument("--lock-dir")
    parser.add_argument("--generation-base", type=int, default=0)
    parser.add_argument("--owner", default="standalone")  # Watchdog identity, not a credential.
    args = parser.parse_args()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    display = os.environ.get("WAYLAND_DISPLAY")
    path = args.socket or os.environ.get("UMBRIEL_SOCKET")
    if not path and runtime and display:
        path = str(Path(runtime) / ("umbriel-" + display + ".sock"))
    if not path or (not args.lock_dir and not runtime):
        return 2
    reader = Reader(path, args.generation_base)
    lock = None
    try:
        parent_guard(reader)
        lock = acquire_lock(args.lock_dir or str(Path(runtime) / "noctalia-lattice"), path)
        reader.run()
        return 0
    except (OSError, ValueError):
        # Fixed status only: socket paths, raw errors and titles never hit logs.
        return 1
    finally:
        if lock is not None:
            os.close(lock)  # Retain the file: unlinking a flock inode causes races.


if __name__ == "__main__":
    raise SystemExit(main())

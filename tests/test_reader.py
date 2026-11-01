"""Synthetic AF_UNIX integration tests. Never connects to the desktop socket."""
import importlib.util
import io
import json
import os
from pathlib import Path
import selectors
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ipc_reader", ROOT / "ipc_reader.py")
reader_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader_module)


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / "tests", prefix="runtime-")
        self.path = Path(self.tmp.name)
        self.children = []
        self.sockets = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(3)
            if child.stdout:
                child.stdout.close()
            if child.stderr:
                child.stderr.close()
        for sock in self.sockets:
            sock.close()
        self.tmp.cleanup()

    def server(self):
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sockets.append(server)
        previous = Path.cwd()
        try:
            # Linux AF_UNIX has a short path limit; the project path is long.
            os.chdir(self.path)
            server.bind("test.sock")
        finally:
            os.chdir(previous)
        server.listen()
        server.settimeout(3)
        return server

    def launch(self, extra=None):
        child = subprocess.Popen([sys.executable, "-B", "-u", str(ROOT / "ipc_reader.py"),
            "--socket", "test.sock", "--lock-dir", str(self.path / "locks"),
            *(extra or [])], stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=self.path)
        self.children.append(child)
        child.pending = b""
        return child

    def packet(self, child, event=None, status=None, timeout=4):
        deadline = time.monotonic() + timeout
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while time.monotonic() < deadline:
                while b"\n" in child.pending:
                    line, child.pending = child.pending.split(b"\n", 1)
                    message = json.loads(line)
                    if (event is None or message["event"] == event) and (
                        status is None or message["data"].get("status") == status):
                        return message
                if selector.select(max(0, deadline - time.monotonic())):
                    chunk = os.read(child.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    child.pending += chunk
        self.fail("expected synthetic packet did not arrive")

    def connect(self, server, child):
        connection, _ = server.accept()
        connection.settimeout(3)
        self.sockets.append(connection)
        request = b""
        while not request.endswith(b"\n"):
            request += connection.recv(4096)
        self.assertEqual(json.loads(request), {"cmd": "subscribe", "events": ["workspaces", "windows", "outputs"]})
        packet = self.packet(child, "lattice.transport", "connected")
        return connection, packet["data"]["generation"]

    def test_single_read_only_subscription_and_full_snapshots(self):
        server = self.server(); child = self.launch()
        connection, generation = self.connect(server, child)
        for family in ["outputs", "windows", "workspaces"]:
            connection.sendall(json.dumps({"event": family, "data": []}).encode() + b"\n")
            packet = self.packet(child, "lattice.snapshot")
            self.assertEqual(packet["data"]["snapshot"], {"event": family, "data": []})
            self.assertEqual(packet["data"]["generation"], generation)
        self.packet(child, "lattice.heartbeat")
        connection.settimeout(.1)
        with self.assertRaises(socket.timeout):
            connection.recv(4096)  # No actions, polling requests or extra subscriptions.

    def test_partial_lines_invalid_json_and_recovery(self):
        server = self.server(); child = self.launch(); connection, _ = self.connect(server, child)
        connection.sendall(b'bad json\n{"event":"windows","data":{}}\n')
        self.packet(child, "lattice.invalid"); self.packet(child, "lattice.invalid")
        connection.sendall(b'{"event":"windows",')
        connection.sendall(b'"data":[]}\n')
        self.assertEqual(self.packet(child, "lattice.snapshot")["data"]["snapshot"]["data"], [])

    def test_disconnect_reconnect_advances_generation(self):
        server = self.server(); child = self.launch(); connection, generation = self.connect(server, child)
        connection.close()
        self.packet(child, "lattice.transport", "disconnected")
        _, next_generation = self.connect(server, child)
        self.assertGreater(next_generation, generation)

    def test_start_before_socket_exists_recovers(self):
        child = self.launch()
        self.packet(child, "lattice.transport", "disconnected")
        server = self.server()
        self.connect(server, child)

    def test_server_rejection_reconnects_without_exposing_error(self):
        server = self.server(); child = self.launch(); connection, generation = self.connect(server, child)
        connection.sendall(b'{"err":"SYNTHETIC_PRIVATE_ERROR"}\n')
        packet = self.packet(child, "lattice.transport", "disconnected")
        self.assertNotIn("SYNTHETIC_PRIVATE_ERROR", json.dumps(packet))
        _, next_generation = self.connect(server, child)
        self.assertGreater(next_generation, generation)

    def test_generation_base_survives_helper_restart(self):
        server = self.server(); child = self.launch(["--generation-base", "41"])
        _, generation = self.connect(server, child)
        self.assertEqual(generation, 42)

    def test_duplicate_reader_is_rejected_without_second_subscription(self):
        server = self.server(); first = self.launch(); self.connect(server, first)
        second = self.launch()
        self.assertEqual(second.wait(3), 1)
        server.settimeout(.2)
        with self.assertRaises(socket.timeout): server.accept()

    def test_sigterm_releases_socket_and_lock(self):
        server = self.server(); first = self.launch(); connection, _ = self.connect(server, first)
        first.terminate(); self.assertEqual(first.wait(3), 0)
        self.assertEqual(connection.recv(1024), b"")
        second = self.launch(); self.connect(server, second)

    def test_broken_stdout_exits(self):
        child = self.launch(); child.stdout.close()
        self.assertEqual(child.wait(3), 1)

    def test_oversized_host_packet_is_explicitly_invalid(self):
        reader = reader_module.Reader("unused")
        captured = []
        def write(_fd, value):
            captured.append(bytes(value)); return len(value)
        with patch.object(reader_module.select, "select", return_value=([], [1], [])), patch.object(reader_module.os, "write", side_effect=write):
            reader.line(json.dumps({"event": "windows", "data": [{"title": "x" * 65000}]}).encode())
        packet = json.loads(b"".join(captured))
        self.assertEqual(packet["event"], "lattice.invalid")
        self.assertNotIn("title", b"".join(captured).decode())

    def test_server_cannot_inject_transport_events(self):
        reader = reader_module.Reader("unused")
        with patch.object(reader, "emit") as emit:
            reader.line(b'{"event":"lattice.transport","data":{"status":"connected"}}')
        self.assertEqual(emit.call_args.args[0], "lattice.invalid")

    def test_null_rows_cannot_turn_into_empty_luau_snapshots(self):
        reader = reader_module.Reader("unused")
        with patch.object(reader, "emit") as emit:
            reader.line(b'{"event":"windows","data":[null]}')
        self.assertEqual(emit.call_args.args[0], "lattice.invalid")
        self.assertEqual(emit.call_args.kwargs["family"], "windows")

    def test_private_lock_directory_required(self):
        directory = self.path / "unsafe"; directory.mkdir(mode=0o755)
        with self.assertRaises(OSError): reader_module.acquire_lock(directory, "synthetic")

    def test_parent_death_exits_without_orphan(self):
        # A synthetic parent execs the reader exactly as Noctalia's exec wrapper
        # does. Killing that parent must leave no live reader or held lock.
        script = "import subprocess,sys,time; p=subprocess.Popen(sys.argv[1:]); print(p.pid,flush=True); time.sleep(30)"
        command = [sys.executable, "-B", "-u", "-c", script, sys.executable, "-B", "-u",
            str(ROOT / "ipc_reader.py"), "--socket", "test.sock",
            "--lock-dir", str(self.path / "locks")]
        parent = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=self.path)
        self.children.append(parent)
        pid = int(parent.stdout.readline())
        # Wait until the reader has started rather than racing Python startup.
        deadline = time.monotonic() + 3
        while not (self.path / "locks").exists() and time.monotonic() < deadline:
            time.sleep(.01)
        parent.kill(); parent.wait(3)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                state = Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1].split()[0]
            except FileNotFoundError:
                break
            if state == "Z": break  # Exited; reaping belongs to the host init.
            time.sleep(.02)
        else:
            os.kill(pid, signal.SIGKILL)
            self.fail("reader survived parent death")


if __name__ == "__main__":
    unittest.main(verbosity=2)

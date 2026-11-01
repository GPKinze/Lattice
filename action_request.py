"""One-shot validated Umbriel actions; no shell interpolation or title logging."""
import json
import os
import socket
import sys

LIMIT = 1024 * 1024

def exchange(connection, request):
    connection.sendall(json.dumps(request, ensure_ascii=False).encode() + b"\n")
    line = bytearray()
    while not line.endswith(b"\n"):
        byte = connection.recv(65536)
        if not byte or len(line) >= LIMIT: raise ValueError()
        line.extend(byte)
        if len(line) > LIMIT: raise ValueError()
    reply = json.loads(line)
    if not isinstance(reply, dict) or "err" in reply or "ok" not in reply: raise ValueError()
    return reply["ok"]

def plan(token, workspaces, windows, outputs):
    if not isinstance(token, dict): raise ValueError()
    ws = next((w for w in workspaces if w.get("id") == token.get("id")), None)
    if not ws or any(ws.get(k) != token.get(k) for k in ("output", "name", "named", "index")):
        raise ValueError()
    if not any(o.get("name") == ws["output"] and o.get("enabled") is True for o in outputs): raise ValueError()
    if token.get("kind") == "window":
        window = next((w for w in windows if w.get("id") == token.get("window")), None)
        if not window or window.get("workspace") != ws["id"] or window.get("output") != ws["output"]: raise ValueError()
        # Native stable-ID focus + warp reveals its workspace without a switch
        # or fallback. Dispatch even when active: the cursor may still be on the bar.
        return {"cmd":"action","action":"window-focus-warp","window":window["id"]}
    if token.get("kind") != "workspace": raise ValueError()
    if ws.get("active"): return None  # Respect existing back-and-forth configuration.
    selector = ws["name"] if ws["named"] else ws["index"]
    # Refuse ambiguous names after output evacuation instead of guessing.
    if ws["named"] and sum(w.get("name") == ws["name"] and w.get("named") is True and w.get("output") == ws["output"] for w in workspaces) != 1: raise ValueError()
    return {"cmd":"action","action":"workspace-switch","workspace":selector,"output":ws["output"]}

def main():
    try:
        token = json.loads(sys.argv[1])
        path = os.environ.get("UMBRIEL_SOCKET")
        if not path:
            path = os.environ["XDG_RUNTIME_DIR"] + "/umbriel-" + os.environ["WAYLAND_DISPLAY"] + ".sock"
        # Installed Umbriel closes ordinary query connections after each reply.
        identity = lambda: (os.stat(path).st_dev, os.stat(path).st_ino)
        original = identity()
        def request(payload):
            if identity() != original: raise ValueError()
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as c:
                c.settimeout(0.6)
                c.connect(path)
                return exchange(c, payload)
        ws = request({"cmd":"workspaces"})
        windows = request({"cmd":"windows"}) if token.get("kind") == "window" else []
        outputs = request({"cmd":"outputs"})
        for rows in (ws, windows, outputs):
            if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows): raise ValueError()
        action = plan(token, ws, windows, outputs)
        if action:
            # Recheck inventory just before dispatch; no positional fallback if
            # the captured ID, output, index or exact name has changed.
            fresh = request({"cmd":"workspaces"})
            action = plan(token, fresh, windows, outputs)
            if action: request(action)
        return 0
    except (OSError, ValueError, KeyError, TypeError, IndexError, StopIteration, AttributeError, RecursionError):
        return 1  # No raw server responses or titles are emitted.

if __name__ == "__main__": raise SystemExit(main())

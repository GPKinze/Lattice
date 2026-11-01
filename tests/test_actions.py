import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("actions",ROOT/"action_request.py")
A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A)
class ActionsTests(unittest.TestCase):
    def setUp(self):
        self.ws={"id":"stable","name":"2","named":True,"index":3,"output":"OUT-B","active":False}
        self.token=dict(self.ws,kind="workspace");self.outputs=[{"name":"OUT-B","enabled":True}]
        self.window={"id":"exact","workspace":"stable","output":"OUT-B","active":False}
    def plan(self):return A.plan(self.token,[self.ws],[self.window],self.outputs)
    def test_named_numeric_uses_string_and_explicit_output(self):
        p=self.plan();self.assertEqual(p["workspace"],"2");self.assertEqual(p["output"],"OUT-B")
    def test_anonymous_uses_numeric_position(self):
        self.ws["named"]=self.token["named"]=False
        self.assertEqual(self.plan()["workspace"],3)
    def test_active_workspace_is_noop_not_back_and_forth(self):
        self.ws["active"]=True;self.assertIsNone(self.plan())
    def test_exact_window_movement_is_rejected_even_with_forged_support(self):
        token=dict(self.token,kind="move",window="exact",destination="other",exactTargetSupported=True)
        with self.assertRaises(ValueError):A.plan(token,[self.ws],[self.window],self.outputs)
    def test_malformed_move_tokens_never_fall_back_to_focus(self):
        for token in [{"kind":"move"},{"kind":"drag"},{"action":"window-move-to-workspace"}]:
            with self.subTest(token=token), self.assertRaises(ValueError):
                A.plan(token,[self.ws],[self.window],self.outputs)
    def test_valid_request_with_unavailable_socket_emits_no_action_or_output(self):
        token=dict(self.token,kind="window",window="exact")
        with tempfile.TemporaryDirectory(dir=ROOT/"tests",prefix="runtime-") as folder:
            refused_socket=Path(folder)/"refused.sock"
            listener=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
            listener.bind(str(refused_socket))
            listener.close()
            self.assertTrue(refused_socket.exists())
            result=subprocess.run([sys.executable,"-B",str(ROOT/"action_request.py"),json.dumps(token)],
                env=dict(os.environ,UMBRIEL_SOCKET=str(refused_socket)),capture_output=True,timeout=3)
        self.assertEqual(result.returncode,1)
        self.assertEqual(result.stdout,b"")
        self.assertEqual(result.stderr,b"")
    def test_exact_window_focus_warp_has_no_workspace_switch(self):
        self.token.update(kind="window",window="exact")
        self.assertEqual(self.plan(),{"cmd":"action","action":"window-focus-warp","window":"exact"})
    def test_already_focused_window_still_warps(self):
        self.token.update(kind="window",window="exact");self.window["active"]=True
        self.assertEqual(self.plan(),{"cmd":"action","action":"window-focus-warp","window":"exact"})
    def test_closed_window_never_falls_back(self):
        self.token.update(kind="window",window="closed")
        with self.assertRaises(ValueError):self.plan()
    def test_transferred_window_rejected(self):
        self.token.update(kind="window",window="exact");self.window["output"]="OUT-A"
        with self.assertRaises(ValueError):self.plan()
    def test_reorder_or_rename_rejected(self):
        for key,value in [("index",9),("name","renamed"),("output","OUT-A")]:
            original=self.ws[key];self.ws[key]=value
            with self.assertRaises(ValueError):self.plan()
            self.ws[key]=original
    def test_unavailable_output_rejected(self):
        self.outputs[0]["enabled"]=False
        with self.assertRaises(ValueError):self.plan()
    def test_ambiguous_named_workspace_rejected(self):
        with self.assertRaises(ValueError):A.plan(self.token,[self.ws,dict(self.ws,id="other")],[],self.outputs)
    def test_unicode_and_shell_metacharacters_are_data(self):
        self.ws["name"]=self.token["name"]=" 一 ' $(false) "
        self.assertEqual(self.plan()["workspace"],self.ws["name"])
    def test_window_warp_preserves_identity_for_all_placements(self):
        self.token.update(kind="window",window="exact")
        for flags in [{"floating":True},{"floating":False},{"fullscreen":True},{"maximized":True}]:
            with self.subTest(flags=flags):
                self.window.update(flags)
                self.assertEqual(self.plan(),{"cmd":"action","action":"window-focus-warp","window":"exact"})
    def window_protocol(self, reject_action=False):
        with tempfile.TemporaryDirectory(dir=ROOT/"tests",prefix="runtime-") as folder:
            path=str(Path(folder)/"ipc.sock");server=socket.socket(socket.AF_UNIX);server.bind(path);server.listen();server.settimeout(3)
            self.token.update(kind="window",window="exact");requests=[];errors=[]
            def serve():
                try:
                    for _ in range(5):
                        c,_=server.accept()
                        with c:
                            request=json.loads(c.makefile("rb").readline());requests.append(request)
                            data=[self.ws] if request["cmd"]=="workspaces" else [self.window] if request["cmd"]=="windows" else self.outputs if request["cmd"]=="outputs" else None
                            reply={"err":"target closed"} if reject_action and request["cmd"]=="action" else {"ok":data}
                            c.sendall(json.dumps(reply).encode()+b"\n")
                except Exception as error:errors.append(error)
            worker=threading.Thread(target=serve);worker.start()
            try:
                result=subprocess.run([sys.executable,"-B",str(ROOT/"action_request.py"),json.dumps(self.token)],env=dict(os.environ,UMBRIEL_SOCKET=path),capture_output=True,timeout=4)
                worker.join(4);self.assertFalse(errors);self.assertEqual(result.stdout,b"");self.assertEqual(result.stderr,b"")
                actions=[q for q in requests if q["cmd"]=="action"]
                self.assertEqual(actions,[{"cmd":"action","action":"window-focus-warp","window":"exact"}])
                self.assertEqual([q["cmd"] for q in requests],["workspaces","windows","outputs","workspaces","action"])
                return result.returncode
            finally:server.close()
    def test_protocol_dispatches_warp_even_for_already_focused_window(self):
        for active in (False,True):
            with self.subTest(active=active):
                self.window["active"]=active;self.assertEqual(self.window_protocol(),0)
    def test_rejected_closed_target_warp_never_retries_or_falls_back(self):
        self.assertEqual(self.window_protocol(reject_action=True),1)
    def test_real_protocol_uses_new_connections_and_validated_action(self):
        with tempfile.TemporaryDirectory(dir=ROOT/"tests",prefix="runtime-") as folder:
            previous=Path.cwd();os.chdir(folder)
            server=socket.socket(socket.AF_UNIX);server.bind("ipc.sock");server.listen();server.settimeout(3)
            requests=[];errors=[]
            def serve():
                try:
                    for _ in range(4):
                        c,_=server.accept()
                        with c:
                            request=json.loads(c.makefile("rb").readline());requests.append(request)
                            data=[self.ws] if request["cmd"]=="workspaces" else self.outputs if request["cmd"]=="outputs" else None
                            c.sendall(json.dumps({"ok":data}).encode()+b"\n")
                except Exception as error:errors.append(error)
            worker=threading.Thread(target=serve);worker.start()
            try:
                result=subprocess.run([sys.executable,"-B",str(ROOT/"action_request.py"),json.dumps(self.token)],
                    env=dict(os.environ,UMBRIEL_SOCKET="ipc.sock"),capture_output=True,timeout=4)
                worker.join(4)
                self.assertEqual(result.returncode,0);self.assertEqual(result.stdout,b"")
                self.assertFalse(errors);self.assertEqual(requests[-1]["action"],"workspace-switch")
            finally:server.close();os.chdir(previous)
if __name__=="__main__":unittest.main(verbosity=2)

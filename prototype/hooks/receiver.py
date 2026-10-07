#!/usr/bin/env python3
"""Throwaway hook receiver for the notch-orchestrator prototype (ticket #2).

Listens on 127.0.0.1:47821, appends every hook request (and the response it
gave) to a JSONL log, and can hold PermissionRequest / AskUserQuestion requests
open until a human answers them with ./answer.

Stdlib only. Not production code.
"""
import argparse
import base64
import json
import os
import select
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(HERE, "logs")
SESSION_DIR = os.path.join(LOG_DIR, "by-session")
PID_FILE = os.path.join(HERE, ".receiver.pid")
PORT = 47821

PERM_MODES = ("hold", "none", "allow", "deny", "http500")
ASK_MODES = ("hold", "none")


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


class State:
    def __init__(self, args):
        self.lock = threading.Lock()
        self.seq = 0
        self.next_pending = 1
        self.pending = {}  # id -> dict
        self.perm_mode = args.perm_mode
        self.ask_mode = args.ask_mode
        self.hold_timeout = args.hold_timeout
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.run_log = os.path.join(LOG_DIR, f"run-{stamp}.jsonl")
        os.makedirs(SESSION_DIR, exist_ok=True)
        latest = os.path.join(LOG_DIR, "latest.jsonl")
        try:
            if os.path.islink(latest) or os.path.exists(latest):
                os.remove(latest)
            os.symlink(os.path.basename(self.run_log), latest)
        except OSError:
            pass

    def write(self, record):
        """Append one record to the run log and to the per-session log."""
        record.setdefault("ts", now_iso())
        line = json.dumps(record, ensure_ascii=False)
        with self.lock:
            with open(self.run_log, "a") as f:
                f.write(line + "\n")
            sid = record.get("session_id")
            if sid:
                safe = "".join(c for c in str(sid) if c.isalnum() or c in "-_")
                with open(os.path.join(SESSION_DIR, safe + ".jsonl"), "a") as f:
                    f.write(line + "\n")

    def next_seq(self):
        with self.lock:
            self.seq += 1
            return self.seq


STATE = None


def say(msg):
    print(f"{datetime.now().strftime('%H:%M:%S.%f')[:-3]}  {msg}", flush=True)


def summarize(payload):
    tool = payload.get("tool_name")
    ti = payload.get("tool_input") or {}
    if tool == "Bash":
        return f"Bash: {ti.get('command', '')[:160]}"
    if tool == "AskUserQuestion":
        qs = ti.get("questions") or []
        return "AskUserQuestion: " + " | ".join(
            f"{q.get('question')} [{', '.join(o.get('label', '') for o in q.get('options', []))}]"
            for q in qs
        )
    if tool:
        target = ti.get("file_path") or ti.get("path") or ti.get("url") or ti.get("description") or ""
        return f"{tool}: {str(target)[:160]}"
    for key in ("source", "reason", "notification_type", "trigger", "agent_type", "prompt", "error"):
        if key in payload:
            return f"{key}={str(payload[key])[:120]}"
    return ""


def build_answers(questions, picks):
    """picks: list of strings, one per question. Each is a 1-based option index,
    a label, or a comma-separated list of those (multi-select)."""
    answers = {}
    for i, q in enumerate(questions):
        if i >= len(picks):
            raise ValueError(f"no pick given for question {i + 1}: {q.get('question')}")
        labels = [o.get("label", "") for o in q.get("options", [])]
        chosen = []
        raw_parts = [picks[i]] if picks[i] in labels else picks[i].split(",")
        for part in raw_parts:
            part = part.strip()
            if part.isdigit() and 1 <= int(part) <= len(labels):
                chosen.append(labels[int(part) - 1])
            else:
                # exact label, else case-insensitive, else free text ("Other")
                match = [l for l in labels if l.lower() == part.lower()]
                chosen.append(match[0] if match else part)
        answers[q.get("question")] = ", ".join(chosen)
    return answers


def decision_body(pending, answer):
    """Translate a human answer into the hook response JSON (or None = empty body).

    Returns (http_status, body_obj_or_None).
    """
    event = pending["event"]
    payload = pending["payload"]
    action = answer["action"]
    if action == "none":
        return 200, None
    if action == "http500":
        return 500, {"error": "simulated receiver failure"}
    if action == "raw":
        return 200, answer["body"]
    if event == "PermissionRequest":
        if action == "allow":
            decision = {"behavior": "allow"}
        elif action == "deny":
            decision = {"behavior": "deny"}
            if answer.get("reason"):
                decision["message"] = answer["reason"]
            if answer.get("interrupt"):
                decision["interrupt"] = True
        elif action == "pick":
            questions = (payload.get("tool_input") or {}).get("questions") or []
            decision = {
                "behavior": "allow",
                "updatedInput": {"questions": questions, "answers": build_answers(questions, answer["picks"])},
            }
        else:
            raise ValueError(f"unsupported action {action} for {event}")
        return 200, {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}
    if event == "PreToolUse":
        out = {"hookEventName": "PreToolUse"}
        if action == "allow":
            out["permissionDecision"] = "allow"
        elif action == "deny":
            out["permissionDecision"] = "deny"
            if answer.get("reason"):
                out["permissionDecisionReason"] = answer["reason"]
        elif action == "pick":
            questions = (payload.get("tool_input") or {}).get("questions") or []
            out["permissionDecision"] = "allow"
            out["updatedInput"] = {"questions": questions, "answers": build_answers(questions, answer["picks"])}
        else:
            raise ValueError(f"unsupported action {action} for {event}")
        return 200, {"hookSpecificOutput": out}
    raise ValueError(f"cannot answer event {event}")


def client_gone(sock):
    """True if the peer closed the connection while we are holding the response."""
    try:
        r, _, _ = select.select([sock], [], [], 0)
        if not r:
            return False
        return sock.recv(1, socket.MSG_PEEK) == b""
    except OSError:
        return True


class Handler(BaseHTTPRequestHandler):
    server_version = "notch-proto-receiver/0"

    def log_message(self, fmt, *args):  # silence default access log
        pass

    def _send(self, status, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        try:
            self.send_response(status)
            if obj is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return None
        except OSError as e:
            return f"{type(e).__name__}: {e}"

    def _read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw) if raw else {}, None
        except ValueError:
            return {}, raw.decode("utf-8", "replace")

    # ---- control API (used by ./answer) -------------------------------------
    def do_GET(self):
        if self.path == "/control/pending":
            with STATE.lock:
                items = [
                    {k: p[k] for k in ("id", "seq", "event", "session_id", "tool_name", "summary", "received")}
                    for p in STATE.pending.values()
                ]
            return self._send(200, {"pending": items})
        if self.path == "/control/status":
            with STATE.lock:
                n = len(STATE.pending)
            return self._send(200, {
                "pid": os.getpid(), "perm_mode": STATE.perm_mode, "ask_mode": STATE.ask_mode,
                "hold_timeout": STATE.hold_timeout, "pending": n, "run_log": STATE.run_log,
            })
        self._send(404, {"error": "not found"})

    def _control_post(self, body):
        if self.path == "/control/mode":
            if "perm" in body:
                if body["perm"] not in PERM_MODES:
                    return self._send(400, {"error": f"perm must be one of {PERM_MODES}"})
                STATE.perm_mode = body["perm"]
            if "ask" in body:
                if body["ask"] not in ASK_MODES:
                    return self._send(400, {"error": f"ask must be one of {ASK_MODES}"})
                STATE.ask_mode = body["ask"]
            if "hold_timeout" in body:
                STATE.hold_timeout = float(body["hold_timeout"])
            STATE.write({"kind": "control", "control": "mode", "perm_mode": STATE.perm_mode,
                         "ask_mode": STATE.ask_mode, "hold_timeout": STATE.hold_timeout})
            say(f"MODE perm={STATE.perm_mode} ask={STATE.ask_mode} hold_timeout={STATE.hold_timeout}")
            return self._send(200, {"perm_mode": STATE.perm_mode, "ask_mode": STATE.ask_mode,
                                    "hold_timeout": STATE.hold_timeout})
        if self.path == "/control/answer":
            with STATE.lock:
                if not STATE.pending:
                    return self._send(409, {"error": "nothing pending"})
                pid = body.get("id")
                if pid is None:
                    pid = min(STATE.pending)  # oldest
                p = STATE.pending.get(int(pid))
                if p is None:
                    return self._send(404, {"error": f"no pending request #{pid}"})
            try:
                status, obj = decision_body(p, body)
            except ValueError as e:
                return self._send(400, {"error": str(e)})
            p["answer"] = {"status": status, "body": obj, "action": body.get("action")}
            p["done"].set()
            return self._send(200, {"answered": p["id"], "event": p["event"], "status": status, "body": obj})
        if self.path == "/control/note":
            STATE.write({"kind": "note", "note": body.get("note", ""), "session_id": body.get("session_id")})
            say(f"NOTE {body.get('note', '')}")
            return self._send(200, {"ok": True})
        self._send(404, {"error": "not found"})

    # ---- hook traffic -------------------------------------------------------
    def do_POST(self):
        body, unparsed = self._read_json()
        if self.path.startswith("/control/"):
            return self._control_post(body)

        seq = STATE.next_seq()
        t0 = time.monotonic()
        payload = body
        event = payload.get("hook_event_name") or self.path.rstrip("/").split("/")[-1]
        sid = payload.get("session_id")
        headers = {k: v for k, v in self.headers.items()}
        record = {
            "kind": "request", "seq": seq, "event": event, "session_id": sid,
            "path": self.path, "method": "POST", "client": self.client_address[0],
            "headers": headers, "payload": payload,
        }
        # The SessionStart/Setup command forwarder ships extra context in headers.
        for hdr, key in (("X-Hook-Env-B64", "env"), ("X-Hook-Proc-B64", "process_chain")):
            if hdr in self.headers:
                try:
                    text = base64.b64decode(self.headers[hdr]).decode("utf-8", "replace")
                    record[key] = [l for l in text.splitlines() if l.strip()]
                    record["headers"][hdr] = "<decoded into '%s'>" % key
                except ValueError:
                    pass
        if unparsed is not None:
            record["unparsed_body"] = unparsed
        STATE.write(record)

        tool = payload.get("tool_name")
        is_ask = tool == "AskUserQuestion"
        hold = False
        status, obj, resolved_by = 200, None, "immediate"
        if event == "PermissionRequest":
            mode = STATE.perm_mode
            if mode == "hold":
                hold = True
            elif mode in ("allow", "deny"):
                reason = "auto-deny by receiver mode" if mode == "deny" else None
                status, obj = decision_body({"event": event, "payload": payload}, {"action": mode, "reason": reason})
                resolved_by = f"mode:{mode}"
            elif mode == "http500":
                status, obj, resolved_by = 500, {"error": "simulated receiver failure"}, "mode:http500"
            else:
                resolved_by = "mode:none"
        elif event == "PreToolUse" and is_ask and STATE.ask_mode == "hold":
            hold = True

        say(f"#{seq:<4} {event:<20} {str(sid)[:8]}  {summarize(payload)}")

        if hold:
            done = threading.Event()
            with STATE.lock:
                pid = STATE.next_pending
                STATE.next_pending += 1
                p = {
                    "id": pid, "seq": seq, "event": event, "session_id": sid, "tool_name": tool,
                    "summary": summarize(payload), "received": now_iso(), "payload": payload, "done": done,
                }
                STATE.pending[pid] = p
            hint = "./answer pick <option>" if is_ask else "./answer allow | deny [reason] | none"
            say(f"      >>> PENDING #{pid} ({event}) — {hint}")
            deadline = (t0 + STATE.hold_timeout) if STATE.hold_timeout else None
            while True:
                if done.wait(0.2):
                    status, obj = p["answer"]["status"], p["answer"]["body"]
                    resolved_by = f"answer:{p['answer']['action']}"
                    break
                if client_gone(self.connection):
                    resolved_by = "client_disconnected"
                    break
                if deadline and time.monotonic() > deadline:
                    status, obj, resolved_by = 200, None, "hold_timeout"
                    break
            with STATE.lock:
                STATE.pending.pop(pid, None)

        send_error = None
        if resolved_by == "client_disconnected":
            status, obj = None, None
            say(f"      <<< #{seq} CLIENT CLOSED THE CONNECTION while the request was held "
                f"({int((time.monotonic() - t0) * 1000)} ms)")
        else:
            send_error = self._send(status, obj)
            if hold or obj is not None:
                say(f"      <<< #{seq} {event} -> {status} {json.dumps(obj) if obj is not None else '(empty body = no decision)'}"
                    f"  [{resolved_by}]" + (f"  SEND FAILED: {send_error}" if send_error else ""))
        STATE.write({
            "kind": "response", "seq": seq, "event": event, "session_id": sid,
            "status": status, "body": obj, "held": hold, "resolved_by": resolved_by,
            "elapsed_ms": int((time.monotonic() - t0) * 1000), "send_error": send_error,
        })


def main():
    global STATE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=PORT)
    ap.add_argument("--perm-mode", choices=PERM_MODES, default="hold",
                    help="what to do with PermissionRequest: hold (wait for ./answer), none (empty 200 at once), "
                         "allow / deny (auto-answer), http500 (non-2xx)")
    ap.add_argument("--ask-mode", choices=ASK_MODES, default="hold",
                    help="what to do with PreToolUse for AskUserQuestion: hold (wait for ./answer pick) or none")
    ap.add_argument("--hold-timeout", type=float, default=0,
                    help="seconds after which a held request is answered with no decision (0 = never)")
    args = ap.parse_args()

    os.makedirs(LOG_DIR, exist_ok=True)
    STATE = State(args)
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer.allow_reuse_address = True
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as e:
        sys.exit(f"cannot bind 127.0.0.1:{args.port}: {e} (is another receiver running? ./stop)")
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    STATE.write({"kind": "control", "control": "start", "pid": os.getpid(), "perm_mode": args.perm_mode,
                 "ask_mode": args.ask_mode, "hold_timeout": args.hold_timeout})
    say(f"receiver listening on http://127.0.0.1:{args.port}  perm={args.perm_mode} ask={args.ask_mode} "
        f"hold_timeout={args.hold_timeout}")
    say(f"log: {STATE.run_log}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        STATE.write({"kind": "control", "control": "stop"})
        try:
            os.remove(PID_FILE)
        except OSError:
            pass
        say("receiver stopped")


if __name__ == "__main__":
    import signal
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    main()

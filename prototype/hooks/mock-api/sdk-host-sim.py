#!/usr/bin/env python3
"""Minimal stand-in for an Agent-SDK permission host (how Claude Desktop and the
VS Code extension host Claude Code: permission prompts go to the host through
the stream-json control protocol as `can_use_tool` requests).

Runs `claude -p --input-format stream-json --output-format stream-json
--permission-prompt-tool stdio`, sends one prompt, prints every message with a
timestamp, and answers can_use_tool according to --host:

  --host wait            never answer (the hook has to decide)
  --host allow:SECONDS   answer allow after SECONDS
  --host deny:SECONDS    answer deny after SECONDS
  --host pick:SECONDS:LABEL   AskUserQuestion: answer with LABEL after SECONDS

Usage (from sandbox/):
  ../prototype/hooks/mock-api/sdk-host-sim.py --host wait "MOCK:bash:./hello.sh"
  ../prototype/hooks/mock-api/sdk-host-sim.py --real --host wait "Run ./hello.sh with the Bash tool"
--real uses the normal logged-in `claude` instead of the scripted mock API.
"""
import argparse
import json
import os
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
T0 = time.monotonic()


def say(msg):
    print(f"[{time.monotonic() - T0:7.3f}s] {msg}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="wait")
    ap.add_argument("--real", action="store_true")
    ap.add_argument("--timeout", type=float, default=120)
    ap.add_argument("prompt")
    ap.add_argument("extra", nargs="*", help="extra claude flags after --")
    a = ap.parse_args()

    exe = ["claude"] if a.real else [os.path.join(HERE, "mock-claude")]
    cmd = exe + ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                 "--permission-prompt-tool", "stdio"] + a.extra
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    def answer_later(req_id, request, kind, delay, label=None):
        time.sleep(delay)
        if kind == "allow":
            resp = {"behavior": "allow", "updatedInput": request.get("input", {})}
        elif kind == "pick":
            inp = dict(request.get("input", {}))
            inp["answers"] = {q["question"]: label for q in inp.get("questions", [])}
            resp = {"behavior": "allow", "updatedInput": inp}
        else:
            resp = {"behavior": "deny", "message": "denied by the simulated host"}
        say(f"HOST -> control_response {kind} for {req_id}")
        try:
            send({"type": "control_response",
                  "response": {"subtype": "success", "request_id": req_id, "response": resp}})
        except (BrokenPipeError, ValueError) as e:
            say(f"HOST could not answer: {e}")

    killer = threading.Timer(a.timeout, proc.kill)
    killer.daemon = True
    killer.start()
    send({"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": a.prompt}]}})

    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            m = json.loads(line)
        except ValueError:
            say(f"(non-json) {line[:300]}")
            continue
        t = m.get("type")
        if t == "control_request":
            req = m.get("request", {})
            say(f"<- control_request {req.get('subtype')} id={m.get('request_id')} "
                f"{json.dumps({k: v for k, v in req.items() if k != 'subtype'})[:700]}")
            if req.get("subtype") == "can_use_tool" and a.host != "wait":
                parts = a.host.split(":")
                threading.Thread(target=answer_later, daemon=True, args=(
                    m["request_id"], req, parts[0], float(parts[1]), parts[2] if len(parts) > 2 else None)).start()
        elif t == "control_cancel_request":
            say(f"<- control_cancel_request {json.dumps(m)[:300]}")
        elif t == "assistant":
            for b in m.get("message", {}).get("content", []):
                if b.get("type") == "text":
                    say(f"<- assistant text: {b['text'][:500]}")
                elif b.get("type") == "tool_use":
                    say(f"<- assistant tool_use {b['name']} {json.dumps(b['input'])[:300]}")
        elif t == "user":
            for b in m.get("message", {}).get("content", []):
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    say(f"<- tool_result is_error={b.get('is_error')} {json.dumps(b.get('content'))[:500]}")
        elif t == "system":
            extra = ""
            if m.get("subtype") == "init":
                extra = f" session={m.get('session_id')} permissionMode={m.get('permissionMode')} " \
                        f"has_AskUserQuestion={'AskUserQuestion' in (m.get('tools') or [])}"
            say(f"<- system/{m.get('subtype')}{extra}")
        elif t == "result":
            say(f"<- result subtype={m.get('subtype')} permission_denials={json.dumps(m.get('permission_denials'))[:400]}")
            break
        else:
            say(f"<- {t} {line[:200]}")
    try:
        proc.stdin.close()
    except OSError:
        pass
    proc.wait(timeout=20)
    say(f"claude exited with {proc.returncode}")


if __name__ == "__main__":
    main()

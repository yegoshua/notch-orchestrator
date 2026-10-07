#!/usr/bin/env python3
"""Scripted stand-in for the Anthropic Messages API (127.0.0.1:47822).

Purpose: exercise the REAL Claude Code client (hooks, permission flow, tool
execution) without a model and without credentials. The "model" is a script:
the prompt carries a directive and the mock answers with the matching tool call.

  MOCK:bash:<command>           -> Bash tool call
  MOCK:write:<abs path>:<text>  -> Write tool call
  MOCK:read:<abs path>          -> Read tool call
  MOCK:ask                      -> AskUserQuestion ("Which color?" Red/Green/Blue)
  MOCK:ask2                     -> AskUserQuestion with two questions (second is multi-select)
  MOCK:agent:<prompt>           -> Agent/Task tool call (the prompt may itself be a MOCK: directive)
  anything else                 -> plain text "pong"

After a tool result comes back, the mock ends the turn with the text
"TOOL_RESULT_SEEN: <tool result content>", which shows exactly what the agent
was told (e.g. a deny reason).
"""
import json
import os
import re
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 47822
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mock-requests.jsonl")

ASK1 = {"questions": [{
    "question": "Which color?", "header": "Color", "multiSelect": False,
    "options": [{"label": "Red", "description": "The color red"},
                {"label": "Green", "description": "The color green"},
                {"label": "Blue", "description": "The color blue"}]}]}
ASK2 = {"questions": ASK1["questions"] + [{
    "question": "Which sizes?", "header": "Sizes", "multiSelect": True,
    "options": [{"label": "Small", "description": "S"}, {"label": "Medium", "description": "M"},
                {"label": "Large", "description": "L"}]}]}


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for b in content or []:
        if b.get("type") == "text":
            out.append(b.get("text", ""))
        elif b.get("type") == "tool_result":
            out.append(text_of(b.get("content")))
    return "\n".join(out)


def plan(body):
    """Return ("text", str) or ("tool", name, input)."""
    tools = [t.get("name") for t in body.get("tools") or []]
    msgs = body.get("messages") or []
    # Everything the "user" side said since the last assistant message.
    trailing = []
    for msg in reversed(msgs):
        if msg.get("role") == "assistant":
            break
        trailing.insert(0, msg)
    results = []
    for msg in trailing:
        c = msg.get("content")
        if isinstance(c, list):
            results += [text_of(b.get("content")) for b in c if b.get("type") == "tool_result"]
    if results:
        return ("text", "TOOL_RESULT_SEEN: " + " || ".join(results)[:1500])
    # Only look at the user's own text, not at injected <system-reminder> blocks.
    text = "\n".join(text_of(msg.get("content")) for msg in trailing)
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.S)
    m = re.search(r"MOCK:(\w+)(?::(.*))?", text)  # directive ends at end of line
    if not m:
        return ("text", "pong")
    kind, arg = m.group(1), (m.group(2) or "").strip()

    def tool(name, inp):
        if name not in tools:
            return ("text", f"TOOL_NOT_OFFERED: {name}; offered={tools}")
        return ("tool", name, inp)

    if kind == "bash":
        return tool("Bash", {"command": arg, "description": "mock-scripted command"})
    if kind == "write":
        path, _, data = arg.partition(":")
        return tool("Write", {"file_path": path, "content": data + "\n"})
    if kind == "read":
        return tool("Read", {"file_path": arg})
    if kind == "ask":
        return tool("AskUserQuestion", ASK1)
    if kind == "ask2":
        return tool("AskUserQuestion", ASK2)
    if kind == "agent":
        name = "Agent" if "Agent" in tools else "Task"
        return tool(name, {"description": "mock subagent", "prompt": arg, "subagent_type": "general-purpose"})
    return ("text", f"unknown directive {kind}")


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, status, obj):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._json(200, {"data": [], "has_more": False})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        try:
            body = json.loads(raw) if raw else {}
        except ValueError:
            body = {}
        path = self.path.split("?")[0]
        if path.endswith("/count_tokens"):
            return self._json(200, {"input_tokens": 100})
        if not path.endswith("/v1/messages"):
            return self._json(200, {})
        p = plan(body)
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "ts": time.strftime("%H:%M:%S"), "model": body.get("model"), "stream": body.get("stream"),
                "n_messages": len(body.get("messages") or []),
                "roles": [m_.get("role") for m_ in body.get("messages") or []],
                "tools": [t.get("name") for t in body.get("tools") or []],
                "last_text": text_of((body.get("messages") or [{}])[-1].get("content"))[-300:],
                "plan": p,
            }) + "\n")
        mid = "msg_mock_" + uuid.uuid4().hex[:12]
        model = body.get("model", "mock")
        usage = {"input_tokens": 100, "output_tokens": 10, "cache_creation_input_tokens": 0,
                 "cache_read_input_tokens": 0}
        if p[0] == "text":
            block = {"type": "text", "text": p[1]}
            stop = "end_turn"
        else:
            block = {"type": "tool_use", "id": "toolu_mock_" + uuid.uuid4().hex[:16], "name": p[1], "input": p[2]}
            stop = "tool_use"
        if not body.get("stream"):
            return self._json(200, {"id": mid, "type": "message", "role": "assistant", "model": model,
                                    "content": [block], "stop_reason": stop, "stop_sequence": None,
                                    "usage": usage})
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        def ev(name, data):
            self.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()

        ev("message_start", {"type": "message_start", "message": {
            "id": mid, "type": "message", "role": "assistant", "model": model, "content": [],
            "stop_reason": None, "stop_sequence": None, "usage": usage}})
        if block["type"] == "text":
            ev("content_block_start", {"type": "content_block_start", "index": 0,
                                       "content_block": {"type": "text", "text": ""}})
            ev("content_block_delta", {"type": "content_block_delta", "index": 0,
                                       "delta": {"type": "text_delta", "text": block["text"]}})
        else:
            ev("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {
                "type": "tool_use", "id": block["id"], "name": block["name"], "input": {}}})
            ev("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {
                "type": "input_json_delta", "partial_json": json.dumps(block["input"])}})
        ev("content_block_stop", {"type": "content_block_stop", "index": 0})
        ev("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None},
                             "usage": {"output_tokens": 10}})
        ev("message_stop", {"type": "message_stop"})


if __name__ == "__main__":
    ThreadingHTTPServer.daemon_threads = True
    ThreadingHTTPServer.allow_reuse_address = True
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    print(f"mock Anthropic API on http://127.0.0.1:{PORT}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)

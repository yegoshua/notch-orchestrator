#!/usr/bin/env python3
"""Drive the REAL interactive `claude` TUI (real model, the user's normal login)
in a pseudo-terminal, always with cwd = sandbox/, and print what is on screen at
chosen moments. Real-model sibling of mock-api/tui-drive.py: no mock env, no
scratch config dir. The environment is reduced to HOME/PATH/USER/TERM/... so
nothing is inherited from an orchestrating Claude Code session.

A minimal VT emulator (cursor moves, erases, scrolling) renders the screen, so
snaps are close to what a human sees, minus colours. Wide characters may be
misaligned.

Steps (argv), executed in order:
  type:<text>          type text and press Enter
  text:<text>          type text, no Enter
  key:<name>           enter, esc, up, down, tab, ctrl-c, ctrl-o, space, focus-out, focus-in, or literal chars
  wait:<seconds>
  snap:<label>         print lines scrolled off since the last snap + the current screen
  sh:<command>         run a shell command in prototype/hooks/ and print its output
  until:<secs>:<regex> wait until the current screen matches the regex (or timeout)
  pend:<secs>[:<n>]    wait until the receiver holds at least n (default 1) pending requests
  ev:<secs>:<Event>    wait until a new hook request with that event name appears in logs/latest.jsonl
  trust                if a workspace-trust dialog is on screen, accept it with Enter

Extra CLI args for claude: env TUI_ARGS (shell-split). `--permission-mode default` is always passed.
"""
import fcntl
import json
import os
import pty
import re
import select
import shlex
import struct
import subprocess
import sys
import termios
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SANDBOX = os.path.normpath(os.path.join(HERE, "..", "..", "sandbox"))
ROWS, COLS = 50, 120
KEYS = {"enter": "\r", "esc": "\x1b", "up": "\x1b[A", "down": "\x1b[B", "right": "\x1b[C", "left": "\x1b[D",
        "focus-out": "\x1b[O", "focus-in": "\x1b[I", "ctrl-c": "\x03", "ctrl-o": "\x0f", "ctrl-d": "\x04", "tab": "\t", "space": " "}
T0 = time.time()


def now():
    return time.strftime("%H:%M:%S") + f".{int(time.time() * 1000) % 1000:03d}"


class Screen:
    def __init__(self):
        self.g = [[" "] * COLS for _ in range(ROWS)]
        self.r = self.c = 0
        self.scrolled = []
        self.pending = ""

    def _scroll(self):
        self.scrolled.append("".join(self.g[0]).rstrip())
        self.g.pop(0)
        self.g.append([" "] * COLS)

    def _lf(self):
        if self.r == ROWS - 1:
            self._scroll()
        else:
            self.r += 1

    def feed(self, data):
        s = self.pending + data
        self.pending = ""
        i, n = 0, len(s)
        while i < n:
            ch = s[i]
            if ch == "\x1b":
                if i + 1 >= n:
                    self.pending = s[i:]
                    return
                nx = s[i + 1]
                if nx == "[":
                    m = re.compile(r"\x1b\[([0-9;?<>=]*)([ -/]*)([@-~])").match(s, i)
                    if not m:
                        if n - i < 40:
                            self.pending = s[i:]
                            return
                        i += 2
                        continue
                    self._csi(m.group(1), m.group(3))
                    i = m.end()
                elif nx == "]":
                    j1, j2 = s.find("\x07", i), s.find("\x1b\\", i)
                    ends = [x for x in (j1, j2) if x != -1]
                    if not ends:
                        self.pending = s[i:]
                        return
                    j = min(ends)
                    i = j + (1 if j == j1 and (j2 == -1 or j1 < j2) else 2)
                elif nx in "()":
                    i += 3
                elif nx == "M":
                    self.r = max(0, self.r - 1)
                    i += 2
                else:
                    i += 2
            elif ch == "\r":
                self.c = 0
                i += 1
            elif ch == "\n":
                self._lf()
                i += 1
            elif ch == "\b":
                self.c = max(0, self.c - 1)
                i += 1
            elif ch == "\t":
                self.c = min(COLS - 1, (self.c // 8 + 1) * 8)
                i += 1
            elif ord(ch) < 32:
                i += 1
            else:
                if self.c >= COLS:
                    self.c = 0
                    self._lf()
                self.g[self.r][self.c] = ch
                self.c += 1
                i += 1

    def _csi(self, params, final):
        if params[:1] in "?<>=" and params:
            return
        nums = [int(x) if x else 0 for x in params.split(";")] if params else []
        a = nums[0] if nums else 0
        one = a or 1
        if final == "A":
            self.r = max(0, self.r - one)
        elif final == "B":
            self.r = min(ROWS - 1, self.r + one)
        elif final == "C":
            self.c = min(COLS - 1, self.c + one)
        elif final == "D":
            self.c = max(0, self.c - one)
        elif final == "E":
            self.r, self.c = min(ROWS - 1, self.r + one), 0
        elif final == "F":
            self.r, self.c = max(0, self.r - one), 0
        elif final == "G":
            self.c = min(COLS - 1, one - 1)
        elif final in "Hf":
            self.r = min(ROWS - 1, max(0, one - 1))
            self.c = min(COLS - 1, max(0, (nums[1] if len(nums) > 1 and nums[1] else 1) - 1))
        elif final == "d":
            self.r = min(ROWS - 1, one - 1)
        elif final == "J":
            if a == 0:
                self.g[self.r][self.c:] = [" "] * (COLS - self.c)
                for r in range(self.r + 1, ROWS):
                    self.g[r] = [" "] * COLS
            elif a == 1:
                for r in range(0, self.r):
                    self.g[r] = [" "] * COLS
                self.g[self.r][:self.c + 1] = [" "] * (self.c + 1)
            else:
                if a == 2:
                    for r in range(ROWS):
                        line = "".join(self.g[r]).rstrip()
                        if line:
                            self.scrolled.append(line)
                for r in range(ROWS):
                    self.g[r] = [" "] * COLS
        elif final == "K":
            if a == 0:
                self.g[self.r][self.c:] = [" "] * (COLS - self.c)
            elif a == 1:
                self.g[self.r][:self.c + 1] = [" "] * (self.c + 1)
            else:
                self.g[self.r] = [" "] * COLS
        elif final == "S":
            for _ in range(one):
                self._scroll()

    def text(self):
        lines = ["".join(row).rstrip() for row in self.g]
        while lines and not lines[-1]:
            lines.pop()
        return "\n".join(lines)

    def snap(self):
        out = []
        if self.scrolled:
            prev = None
            for l in self.scrolled:
                if l != prev and l.strip():
                    out.append("  ^ " + l)
                prev = l
            self.scrolled = []
        out.append(self.text())
        return "\n".join(out)


def pending_count():
    try:
        with urllib.request.urlopen("http://127.0.0.1:47821/control/pending", timeout=2) as r:
            return len(json.loads(r.read())["pending"])
    except Exception:
        return -1


def main():
    steps = sys.argv[1:]
    env = {k: os.environ[k] for k in ("HOME", "PATH", "USER", "LOGNAME") if k in os.environ}
    env.update(TERM="xterm-256color", SHELL="/bin/zsh", LANG="en_US.UTF-8", COLUMNS=str(COLS), LINES=str(ROWS))
    argv = ["claude", "--permission-mode", "default"] + shlex.split(os.environ.get("TUI_ARGS", ""))
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(SANDBOX)
        os.execvpe("claude", argv, env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    os.environ["TUI_CLAUDE_PID"] = str(pid)  # for sh: steps (e.g. the kill -9 check)
    scr = Screen()
    dec = __import__("codecs").getincrementaldecoder("utf-8")("replace")
    alive = [True]
    log_path = os.path.join(HERE, "logs", "latest.jsonl")
    log_off = [os.path.getsize(log_path) if os.path.exists(log_path) else 0]
    log_real = [os.path.realpath(log_path)]

    def pump(seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end and alive[0]:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    alive[0] = False
                    return
                if not data:
                    alive[0] = False
                    return
                if b"\x1b[6n" in data:
                    os.write(fd, f"\x1b[{scr.r + 1};{scr.c + 1}R".encode())
                if b"\x1b[?1004h" in data:
                    print(f"[{now()}] (claude enabled terminal focus reporting, DECSET 1004)", flush=True)
                if b"\x1b[c" in data:
                    os.write(fd, b"\x1b[?62;c")
                scr.feed(dec.decode(data))
        if not alive[0]:
            time.sleep(max(0, min(0.05, end - time.monotonic())))

    def send(s):
        try:
            os.write(fd, s.encode())
        except OSError:
            alive[0] = False

    def new_events():
        real = os.path.realpath(log_path)
        if real != log_real[0]:
            log_real[0], log_off[0] = real, 0
        if not os.path.exists(real):
            return []
        with open(real) as f:
            f.seek(log_off[0])
            chunk = f.read()
        nl = chunk.rfind("\n")
        if nl == -1:
            return []
        log_off[0] += len(chunk[:nl + 1].encode())
        out = []
        for l in chunk[:nl + 1].splitlines():
            try:
                rec = json.loads(l)
            except ValueError:
                continue
            if rec.get("kind") == "request":
                out.append(rec.get("event"))
        return out

    print(f"[{now()}] claude pid in pty: {pid}  argv: {' '.join(argv)}  cwd: {SANDBOX}", flush=True)
    for step in steps:
        kind, _, arg = step.partition(":")
        if kind == "wait":
            pump(float(arg))
        elif kind == "type":
            for k in range(0, len(arg), 40):
                send(arg[k:k + 40])
                pump(0.08)
            pump(0.5)
            send("\r")
            print(f"[{now()}] typed + Enter: {arg[:70]}", flush=True)
            pump(0.3)
        elif kind == "text":
            send(arg)
            pump(0.4)
        elif kind == "key":
            send(KEYS.get(arg, arg))
            print(f"[{now()}] key {arg}", flush=True)
            pump(0.3)
        elif kind == "snap":
            pump(0.3)
            print(f"\n----- SNAP {arg} [{now()}] alive={alive[0]} " + "-" * 40)
            print(scr.snap())
            print("-" * 80, flush=True)
        elif kind == "sh":
            out = subprocess.run(arg, shell=True, capture_output=True, text=True, cwd=HERE)
            print(f"\n[{now()}] $ {arg}\n{out.stdout}{out.stderr}", flush=True)
        elif kind == "until":
            secs, _, rx = arg.partition(":")
            t = time.monotonic()
            ok = False
            while time.monotonic() - t < float(secs) and alive[0]:
                pump(0.25)
                if re.search(rx, scr.text(), re.I | re.S):
                    ok = True
                    break
            print(f"[{now()}] until /{rx}/ -> {'MATCH' if ok else 'TIMEOUT'} after {time.monotonic() - t:.1f}s", flush=True)
        elif kind == "pend":
            parts = arg.split(":")
            secs, want = float(parts[0]), int(parts[1]) if len(parts) > 1 else 1
            t = time.monotonic()
            n = -1
            while time.monotonic() - t < secs:
                pump(0.25)
                n = pending_count()
                if n >= want:
                    break
            print(f"[{now()}] pend(>={want}) -> {n} pending after {time.monotonic() - t:.1f}s", flush=True)
        elif kind == "ev":
            secs, _, name = arg.partition(":")
            t = time.monotonic()
            ok = False
            while time.monotonic() - t < float(secs) and not ok:
                pump(0.25)
                ok = name in new_events()
            print(f"[{now()}] ev {name} -> {'SEEN' if ok else 'TIMEOUT'} after {time.monotonic() - t:.1f}s", flush=True)
        elif kind == "trust":
            pump(1.0)
            if re.search(r"trust", scr.text(), re.I):
                print(f"[{now()}] trust dialog on screen:\n{scr.text()}", flush=True)
                send("\r")
                pump(3)
            else:
                print(f"[{now()}] no trust dialog", flush=True)
        else:
            print(f"unknown step {step!r}", flush=True)
    for sig in (15, 9):
        try:
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
            os.kill(pid, sig)
        except OSError:
            break
        pump(1.5)
    try:
        os.close(fd)
    except OSError:
        pass
    for _ in range(30):
        try:
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
        except OSError:
            break
        time.sleep(0.1)
    print(f"[{now()}] driver done", flush=True)


if __name__ == "__main__":
    main()

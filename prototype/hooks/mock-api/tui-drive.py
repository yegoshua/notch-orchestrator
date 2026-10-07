#!/usr/bin/env python3
"""Drive the interactive `claude` TUI in a pseudo-terminal (against the mock API)
and print what is on screen at chosen moments. Crude: ANSI sequences are
stripped, so the text is a rough transcript, not a faithful screen.

Script steps (argv after the options), executed in order:
  type:<text>     type text and press Enter
  key:<name>      press a key: enter, esc, up, down, 1, 2, 3, ctrl-c
  wait:<seconds>
  snap:<label>    print the text that appeared since the previous snap
  sh:<command>    run a shell command (e.g. the ./answer CLI) and print its output

Usage (from sandbox/):
  ../prototype/hooks/mock-api/tui-drive.py wait:4 snap:start type:MOCK:bash:./hello.sh wait:3 snap:dialog
"""
import os
import pty
import re
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KEYS = {"enter": "\r", "esc": "\x1b", "up": "\x1b[A", "down": "\x1b[B", "ctrl-c": "\x03", "tab": "\t"}
ANSI = re.compile(r"\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][A-Za-z0-9]|\x1b[=>78]")


def clean(raw):
    text = raw.decode("utf-8", "replace")
    text = re.sub(r"\x1b\[\d*C", " ", text)          # cursor-forward used as spacing
    text = re.sub(r"\x1b\[\d+;\d+H|\x1b\[\d*[ABEFG]", "\n", text)  # cursor moves -> newline
    text = ANSI.sub("", text).replace("\r", "\n")
    lines = [l.rstrip() for l in text.split("\n")]
    out = []
    for l in lines:
        if l.strip() and (not out or out[-1] != l):
            out.append(l.strip())
    # the TUI positions most words with cursor moves; re-flow into ~110 columns
    flowed, cur = [], ""
    for w in out:
        if len(cur) + len(w) + 1 > 110:
            flowed.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    flowed.append(cur)
    return "\n".join(flowed)


def main():
    steps = sys.argv[1:]
    env = dict(os.environ, TERM="xterm-256color", COLUMNS="110", LINES="45")
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(os.path.join(HERE, "mock-claude"), ["mock-claude"] + os.environ.get("TUI_ARGS", "").split(), env)
    import fcntl, struct, termios
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 110, 0, 0))
    buf = b""

    def pump(seconds):
        nonlocal buf
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    return
                if not data:
                    return
                buf += data
                # answer terminal capability queries minimally (cursor position report)
                if b"\x1b[6n" in data:
                    os.write(fd, b"\x1b[1;1R")

    print(f"claude pid in pty: {pid}", flush=True)
    for step in steps:
        kind, _, arg = step.partition(":")
        if kind == "wait":
            pump(float(arg))
        elif kind == "type":
            os.write(fd, arg.encode())
            pump(0.5)
            os.write(fd, b"\r")
            pump(0.3)
        elif kind == "key":
            os.write(fd, KEYS.get(arg, arg).encode())
            pump(0.3)
        elif kind == "snap":
            pump(0.2)
            print(f"\n----- SNAP {arg} " + "-" * 60)
            print(clean(buf))
            sys.stdout.flush()
            buf = b""
        elif kind == "sh":
            out = subprocess.run(arg, shell=True, capture_output=True, text=True)
            print(f"\n$ {arg}\n{out.stdout}{out.stderr}", flush=True)
    for sig in (15, 9):
        try:
            os.kill(pid, sig)
        except OSError:
            break
        pump(0.7)
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


if __name__ == "__main__":
    main()

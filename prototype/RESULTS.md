# Manual check results (running log)

Raw notes taken during the session on 2026-10-07. Source for the "Prototype findings" in issue #1.
"Log" = read from receiver / status line logs; "Human" = reported by the user from the screen.

## CLI (Terminal.app, Claude Code 2.1.236, `--permission-mode default`)

### C1. Hooks reach the receiver — PASS
- Log: session `e9952653`, receiver run `run-20261007-143835.jsonl`.
  Events: InstructionsLoaded x3, SessionStart (source=startup, via command hook), Notification
  (notification_type=auth_success, after /login), UserPromptSubmit (permission_mode=default), Stop
  (carries last_assistant_message, background_tasks, session_crons).
- Log: command-hook env has CLAUDE_CODE_ENTRYPOINT=cli, TERM_PROGRAM=Apple_Terminal,
  CLAUDE_CODE_SESSION_ID, CLAUDE_PID; process chain gives the TTY (ttys011) of the `claude` process.
- Human: on-screen details (trust dialog, hook lines in the TUI) not reported yet.

### Status line in CLI (env checklist 1-4) — answered from the log
- Log: status line command ran 3 times in session `e9952653`: at start, after /login, after the first
  response. `rate_limits` absent in the first two, present in the third (first API response):
  `{"five_hour": {"used_percentage": 28.999999999999996, "resets_at": 1791380400},
    "seven_day": {"used_percentage": 3, "resets_at": 1791936000}}`
  used_percentage is a float 0-100 (not rounded), resets_at is epoch seconds.

### C2 attempt 1 (14:46) — turned into C6 (native answer first), C2 still to do
- Log: PreToolUse -> PermissionRequest (held, PENDING #1) -> Notification permission_prompt 6 s later ->
  PostToolUse 18 s after the request -> PostToolBatch -> Stop. No `./answer` reached the receiver:
  request seq 12 has no response and was still pending after Stop. So the tool was allowed by
  something other than the hook (to be confirmed by the human: native dialog answered in the TUI).
- Log, real model: the held PermissionRequest is NOT cancelled when the tool runs; the receiver gets no
  signal other than the later PostToolUse for the same tool + input.
- Log: an unexplained `SubagentStop` with empty agent_type arrived at 14:42:53, three minutes after
  Stop, with no prompt in between (idle session).
- Human (14:5x): confirmed pressing "Yes" in the native dialog in attempt 1 -> this is C6: native Yes
  first leaves the hook request pending, never cancelled.
- Human (screenshot): native "Do you want to proceed?" dialog is visible in the TUI in parallel while
  the hook request is held (options: Yes / Yes, and don't ask again for: ./hello.sh * / No).

### C2. Allow via hook is honoured (CLI) — PASS
- Log: PermissionRequest seq 21 held 99 s, answered `{"hookSpecificOutput": {"hookEventName":
  "PermissionRequest", "decision": {"behavior": "allow"}}}`; PostToolUse arrived 34 ms later, then
  PostToolBatch, Stop. Stale pending #1 from attempt 1 still open at that time.

## CLI checks C3-C26 — run by an agent through a pty (`prototype/hooks/tui-real.py`), real model

The agent was stopped before writing its report; the lines below were reconstructed from the receiver
logs (`run-20261007-143835.jsonl`, `run-20261007-150234.jsonl`). Screen text was not preserved, so
anything that is only visible on screen is marked "screen: not captured".

- C3 deny: honoured. PermissionRequest -> deny -> PostToolBatch -> Stop; no PostToolUse, no retry.
- C4 deny + message: the agent's reply refers to the message text ("use data/colors.txt instead") and
  treats it as tool output rather than a user instruction.
- C5 deny + interrupt: turn ends; no Stop event followed (next event was SessionEnd).
- C6 native Yes first (slow.sh 20): PostToolUse, Stop arrived with the hook request still held; a late
  `allow` 33 s after Stop was accepted by the socket and had no effect.
- C7 native No / Esc: held connection dropped by the client after ~2.2-2.5 s; no PostToolBatch, no Stop.
- C8 no decision (empty 200) / C9 immediate no decision / C11 HTTP 500: tool ran after a native answer;
  normal PostToolUse -> Stop. Screen: not captured.
- C10 receiver not running: run made, nothing logged by definition. Screen: not captured.
- C12 hook timeout 20 s: client closed the connection at 20.1 s; tool ran 18 s later after a native answer.
- C13: Notification(permission_prompt) 6.0 s after PermissionRequest (same in C12, C21).
- C14 Edit: PermissionRequest carries tool_input (file_path, old/new strings) and permission_suggestions.
- C15 question via PreToolUse pick -> agent answered "Green". C16 via PermissionRequest pick -> "Blue".
- C17 native answer first: PostToolUse carries the answer; held PermissionRequest closed only at SessionEnd.
- C18 two questions + multi-select -> "Blue; Small, Large". C18b free text -> "Magenta (custom …); Medium".
- C19 PreToolUse deny with reason: agent chose by itself ("Blue") and could quote the reason.
- C20-C26 fixtures: see `fixtures/README.md`.

## Not done (deferred by the user on 2026-10-07)

- Every desktop-app check in `prototype/hooks/CHECKLIST.md` section 2 (D1-D28).
- `prototype/env/CHECKLIST.md` checks 5-33: status line in a desktop session, mapping timing, deep
  links, Automation grant test (ad-hoc vs self-signed), Gatekeeper launch by hand.

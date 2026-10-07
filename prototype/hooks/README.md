# Hook prototype (ticket #2) — throwaway

A local receiver that logs every Claude Code hook request and can hold a
permission request (or a multiple-choice question) open until you answer it by
hand. Hooks are configured **only** in `sandbox/.claude/settings.json`, so they
affect only sessions opened in `sandbox/`. Nothing here touches
`~/.claude/settings.json`.

## Start / stop

```sh
cd prototype/hooks
./start                      # foreground, Ctrl-C to stop; listens on 127.0.0.1:47821
./start --perm-mode none     # PermissionRequest gets "no decision" immediately
./start --hold-timeout 20    # held requests get "no decision" after 20 s
./stop                       # from another shell; also the "receiver not running" test
```

The receiver prints one line per event and a `>>> PENDING #n` line for every
request it is holding.

## Answer CLI (second shell)

```sh
./answer                     # list pending requests
./answer allow               # oldest pending request (add --id N for a specific one)
./answer deny
./answer deny "reason text"  # the reason is returned to the agent
./answer deny "reason" --interrupt
./answer none                # 200 + empty body = no decision (Claude Code falls back to its own dialog)
./answer http500             # non-2xx response
./answer pick 2              # AskUserQuestion: option index or label; one pick per question; 1,3 for multi-select
./answer raw '{"hookSpecificOutput": {...}}'
./answer mode perm hold|none|allow|deny|http500   # behaviour for PermissionRequest without restarting
./answer mode ask hold|none                       # hold PreToolUse(AskUserQuestion) or let it pass
./answer mode hold-timeout 20
./answer note "CLI check 1.3 starts"              # marker line in the log
./answer status
```

What is held: every `PermissionRequest` (mode `hold`) and `PreToolUse` for the
`AskUserQuestion` tool (ask mode `hold`). Everything else is answered at once
with an empty 200.

## Logs

- `logs/run-<timestamp>.jsonl` — everything from one receiver run
  (`logs/latest.jsonl` → newest). One JSON object per line: `kind` =
  `request` (timestamp, `event`, `session_id`, headers, full `payload`),
  `response` (status, body, `resolved_by`, `elapsed_ms`), `note`, `control`.
  `resolved_by: client_disconnected` means Claude Code closed the held
  connection before we answered.
- `logs/by-session/<session_id>.jsonl` — the same records split per session.
- `logs/recorded/` — sequences saved by name (see its README).

```sh
./sessions                         # list sessions
./sessions last                    # compact sequence of the most recent session
./sessions <id-prefix> --raw       # raw JSONL of one session
./sessions last --save cli-normal-turn   # copy to logs/recorded/cli-normal-turn.jsonl
./sessions last --env              # env + process chain captured at SessionStart
./sessions last --pid              # pid of that session's claude process
```

## Hook configuration

`./install-sandbox-hooks.py` rewrites only the `hooks` key of
`sandbox/.claude/settings.json` (`--remove` deletes it, `--print` shows it).
`SessionStart` and `Setup` do not accept HTTP hooks, so they use the command
hook `sandbox/.claude/hooks/forward-to-receiver.sh`, which also reports a
filtered environment and the parent process chain.

## Scripted "model" (no login needed)

`mock-api/` exercises the real `claude` client against a scripted fake of the
Messages API; this is how the headless results in `CHECKLIST.md` section 0 were
produced. Not needed for the manual checklist.

```sh
python3 mock-api/mock_anthropic.py &                                 # 127.0.0.1:47822
cd ../../sandbox
../prototype/hooks/mock-api/mock-claude -p "MOCK:bash:./hello.sh"    # real CLI, fake model
../prototype/hooks/mock-api/sdk-host-sim.py --host wait "MOCK:ask"   # CLI behind a simulated SDK permission host
../prototype/hooks/mock-api/tui-drive.py wait:4 type:MOCK:bash:./hello.sh wait:3 snap:dialog   # interactive TUI in a pty
```

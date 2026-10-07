# Fixtures: recorded hook event sequences

Recorded on 2026-10-07 during the prototype (tickets #2, #3) with the throwaway receiver in
`prototype/hooks/`. One JSON object per line: `kind: request` (hook `event`, `payload`, headers; for
command hooks also `env` and `process_chain`), `kind: response` (what the receiver answered, `held`,
`resolved_by`, `elapsed_ms`) and `kind: note` markers.

## `cli/` — real model, interactive TUI, Claude Code 2.1.236, `--permission-mode default`

Driven through a pseudo-terminal (`prototype/hooks/tui-real.py`), so the "human" keystrokes were scripted.

| File | What it is | Notable |
| --- | --- | --- |
| `cli-normal-turn` | one prompt, no tools, idle, `/exit` | SessionStart(startup) → UserPromptSubmit → Stop → Notification(idle_prompt) 60 s later → SessionEnd(prompt_input_exit) |
| `cli-permission-allow` | Bash needing permission, hook answers allow after 10 s | PreToolUse → PermissionRequest → Notification(permission_prompt) +6 s → PostToolUse 60 ms after the answer → PostToolBatch → Stop |
| `cli-permission-deny` | same, hook answers deny with a message | no PostToolUse and no PermissionDenied; PostToolBatch → Stop |
| `cli-permission-native-yes` | human presses Yes in the terminal dialog while the hook request is held | PostToolUse / Stop arrive while the PermissionRequest is still open; nothing cancels it |
| `cli-permission-native-no` | human presses No, then Esc | held connection is dropped by the client ~2 s later; no PostToolBatch, no Stop — the next event is the next UserPromptSubmit |
| `cli-subagents` | two background subagents | `Stop` arrives while both are running (`background_tasks` lists them); each result re-enters as a `UserPromptSubmit` whose prompt starts with `<task-notification>`; three Stops in total |
| `cli-killed` | `kill -9` during a 60 s Bash command | last event is the PermissionRequest/PreToolUse; no PostToolUse, Stop or SessionEnd |
| `cli-resumed` | `/exit`, then `--continue` | same `session_id`; SessionStart(source=resume). InstructionsLoaded before it carries a different, throwaway session id |
| `cli-resumed-after-kill` | `--resume` of the killed session | same `session_id`, SessionStart(source=resume); the interrupted tool call never gets a closing event |
| `cli-compaction` | `/compact` between turns | PreCompact → SubagentStop(agent_type "") → SessionStart(source=compact) → PostCompact; same `session_id`; no Stop |
| `cli-clear` | `/clear` | SessionEnd(reason=clear) then SessionStart(source=clear) with a NEW `session_id` |

Noise to expect in every sequence: a `SubagentStop` with an empty `agent_type` about 2 s after many
`Stop`s (an internal helper agent, not a user-visible subagent), and three `InstructionsLoaded` per start.

## Not recorded

- **Desktop app sequences: none.** The desktop checks were deferred. The closest material is
  `prototype/hooks/logs/recorded/mock-sdkhost-*` (the real 2.1.236 / 2.1.289 client behind a simulated
  SDK permission host with a scripted fake model) — a prediction of desktop behaviour, not a recording.

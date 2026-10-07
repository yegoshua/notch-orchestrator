# Recorded sequences

Raw per-session JSONL copied from `../by-session/` (format: see `../../README.md`).
Everything currently here was recorded by the agent on 2026-10-07, before any
manual check. Names say how each was produced:

- `mock-…` — the real Claude Code client driven by the scripted fake model in
  `../../mock-api/`. Hook payloads, ordering and the permission flow are the
  client's real behaviour; prompts and tool calls are synthetic
  (`MOCK:bash:./hello.sh`, answers like `TOOL_RESULT_SEEN: …`), `model` and
  token numbers are meaningless, and `transcript_path` points into a scratch
  config directory.
  - `mock-plain-p-…` — `claude -p`, no permission host.
  - `mock-sdkhost-…` — `claude -p --permission-prompt-tool stdio` behind
    `sdk-host-sim.py`, i.e. the way Claude Desktop / IDE extensions host
    Claude Code. Not the desktop app itself.
  - `mock-tui-…` — the interactive terminal UI in a pseudo-terminal.
  - `2.1.236` = the Homebrew CLI, `2.1.289` = the binary bundled with the
    desktop app (`~/Library/Application Support/Claude/claude-code/2.1.289/`).
    No version in the name = 2.1.236.
- `real-…` — real runs without the mock. Only two exist: `claude -p` failing
  with `StopFailure error=authentication_failed` because the CLI is logged out.

None of these come from a real model turn or from the desktop app. The
fixtures the spec asks for (`cli-…`, `desktop-…`) are produced by the manual
checklist (`../../CHECKLIST.md`, parts 1.F and 2.F) and should replace the
`mock-…` files where they overlap.

Sequences worth a look:

| File | What it shows |
| --- | --- |
| `mock-tui-2.1.236-permission-native-first` | human answers the native dialog first: no signal to the hook, the held request stays open until the process exits |
| `mock-sdkhost-H5b-host-denies-first` | host denies first: no PostToolUse / PermissionDenied, only PostToolBatch + Stop |
| `mock-sdkhost-turn-with-subagent` | background subagent: parent `Stop` arrives while the subagent's PermissionRequest is still open; later a Claude-started `UserPromptSubmit` |
| `mock-plain-p-subagent-resume-compact` | `SessionStart source=resume`, then `/compact`: PreCompact, a `SubagentStop` with empty `agent_type`, `SessionStart source=compact`, PostCompact |
| `mock-sdkhost-killed-session` | `kill -9` mid-tool: the sequence just stops (no Stop, no SessionEnd) |
| `mock-tui-2.1.236-askuserquestion-permissionrequest-pick` | question answered through the PermissionRequest hook while the native question dialog was on screen |

Update, later on 2026-10-07: the `cli-*.jsonl` files here ARE real-model recordings (interactive 2.1.236 driven through `tui-real.py`); they are curated in `fixtures/cli/`. No desktop-app recording exists.

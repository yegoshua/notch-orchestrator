# Manual checklist — hook checks (ticket #2)

Answers prototype findings 1, 2 and 5 of spec #1 and records the fixture
sequences. Section 0 is what was already established without a human; sections
1 (CLI) and 2 (desktop app) are yours. Every check has: **Do**, **Look at**,
**Write down**.

Paths below are relative to the repo root. Shell A runs the receiver, shell B
runs `./answer` / `./sessions`; both in `prototype/hooks/`.

---

## 0. Before you start

### 0.1 Preconditions

1. **Log the CLI in.** On 2026-10-07 `claude auth status` reported
   `"loggedIn": false` and `claude -p` failed with "OAuth session expired". Run
   `claude` in Terminal.app and `/login` first. (This is why no real-model run
   exists yet.)
2. **Use the default permission mode.** In auto mode no permission prompt
   appears and `PermissionRequest` never fires (a classifier decides; you get
   `PermissionDenied` at most). Your user settings contain an `autoMode` key,
   and the 2.1.289 binary started in `auto` on a fresh config. CLI: start with
   `claude --permission-mode default`. Desktop: pick the "ask permissions" /
   manual mode in the session's mode picker. Check `permission_mode=default`
   in the receiver's `UserPromptSubmit` line before trusting any result.
3. **Trust dialog.** The first interactive `claude` in `sandbox/` shows the
   workspace-trust dialog; no hook runs until you accept it.
4. **Desktop: open the folder itself, no worktree.** `sandbox/` is not
   committed, so a session that runs in a git worktree will not contain it.
   Start a local Code session directly on
   `/Users/yegor-nextcode/work/pet/notch-orchestrator/sandbox`. The first
   receiver line must show that `cwd`.
5. **Versions differ.** Terminal CLI = 2.1.236 (Homebrew). The desktop app runs
   its own bundled Claude Code (2.1.289 at the time of writing). Write down
   both versions you actually tested (`claude --version`; desktop: `./sessions
   last --env` shows `CLAUDE_CODE_EXECPATH`).
6. Do **not** start `claude` at the repo root for these checks and do not copy
   the hooks anywhere else: a held permission hook there would freeze the
   orchestrating session.

### 0.2 Receiver commands

```sh
# shell A
cd prototype/hooks && ./start
# shell B
cd prototype/hooks
./answer                 # what is pending
./answer allow | deny | deny "reason" | none | pick 2
./answer note "C3 start" # marker in the log before each check
./sessions last          # compact sequence of the session that spoke last
```

### 0.3 Prompts (paste exactly)

| Id | Prompt |
| --- | --- |
| P-BASH | `Run ./hello.sh with the Bash tool. Do nothing else.` |
| P-SLOW | `Run ./slow.sh 60 with the Bash tool. Do nothing else.` |
| P-EDIT | `Use the Edit tool to change the word DRAFT to FINAL in notes.txt. Do nothing else.` |
| P-PLAIN | `Reply with one short sentence about the colour blue. Do not use any tools.` |
| P-ASK | `Use the AskUserQuestion tool to ask me which colour I prefer, with exactly three options: Red, Green, Blue. Then reply with only the colour I picked.` |
| P-ASK2 | `Use the AskUserQuestion tool once with two questions: "Which colour?" (Red, Green, Blue) and "Which sizes?" (Small, Medium, Large, multi-select). Then repeat my answers.` |
| P-SUB | `Launch two general-purpose subagents in parallel with the Agent tool: one reads data/colors.txt and reports the number of lines, the other reads notes.txt and reports its first line. Then summarise both results in one sentence.` |
| P-AFTER | `What did the last tool call return, or why did it not run? Quote any message you were given.` |

`hello.sh` is not on any allow list, so P-BASH always needs permission. If a
"don't ask again" rule gets saved by accident, delete
`sandbox/.claude/settings.local.json`.

### 0.4 Already established headlessly (expectations, not a substitute)

Method: the real `claude` binaries (2.1.236 CLI and the desktop-bundled
2.1.289) were run in `sandbox/` against a scripted fake of the model API
(`mock-api/`), in three shapes: `claude -p`, `claude -p` behind a simulated SDK
permission host (the mechanism Claude Desktop uses), and the interactive TUI in
a pseudo-terminal. The hook and permission machinery was real; the model, the
human and the desktop app's own UI were not.

| # | Observation | Where seen |
| --- | --- | --- |
| a | `sandbox/.claude/settings.json` is picked up with cwd = `sandbox/` although it is a subdirectory of a git repo (`CLAUDE_PROJECT_DIR` = sandbox). A session started at the repo root produced no hook traffic. | `-p`, both versions |
| b | `SessionStart` and `Setup` do not accept HTTP hooks (docs); they are delivered through a command hook. | docs + config |
| c | Interactive TUI: the native permission dialog is shown **in parallel** while the HTTP hook is held. Hook `allow` → dialog disappears, tool runs, transcript says "Allowed by PermissionRequest hook". Hook `deny` + reason → "Denied by PermissionRequest hook", the reason text is the tool result the agent sees. | TUI 2.1.236; allow also on 2.1.289 |
| d | Human answers the native dialog **Yes** first: the tool runs, the held hook request is **not** cancelled — it stayed open through PostToolUse and Stop until the process exited. Native **No**: the turn is interrupted, the held connection is closed at once, and no Stop / PostToolBatch follows. | TUI 2.1.236; Yes also on 2.1.289 |
| e | SDK-host shape: the host receives `can_use_tool` at the same moment the hook fires. Hook decides first → host gets `control_cancel_request`. Host decides first → hook request left open until exit. | sdk-host-sim, both versions |
| f | No decision (200 + empty body) and HTTP 500 → falls back to the native dialog / host. Receiver not running → same, within milliseconds. | sdk-host-sim, TUI |
| g | Receiver not running is **not silent** in the TUI: every hooked event prints `… hook error — connect ECONNREFUSED 127.0.0.1:47821` in the transcript; `-p` prints a SessionEnd hook failure to stderr. | TUI 2.1.236, `-p` |
| h | Claude-side hook timeout (set to 4 s): the connection is closed at the timeout, the native prompt stays. | sdk-host-sim 2.1.236 |
| i | `PermissionRequest` payload has no `tool_use_id` (PreToolUse / PostToolUse have it). | all |
| j | AskUserQuestion can be answered by a hook two ways: `PreToolUse` → `permissionDecision: allow` + `updatedInput.answers` (documented; the native question dialog never appears while the hook is held), or `PermissionRequest` → `decision.behavior: allow` + `updatedInput.answers` (native question dialog is on screen in parallel and is dismissed). PreToolUse `allow` without answers is not enough. Multi-select = labels joined with `, `; free text is accepted. | sdk-host-sim, TUI 2.1.236 |
| k | Plain `claude -p` (no host): 2.1.236 does **not** fire `PermissionRequest` and auto-denies; 2.1.289 fires it and honours `allow`. AskUserQuestion is not offered at all in plain `-p`. | `-p` |
| l | `CLAUDE_CODE_ENTRYPOINT` is visible to command hooks: `cli` (interactive), `sdk-cli` (`-p`), `claude-desktop` (seen only as an inherited value, see D2). Not present in any hook payload. | SessionStart forwarder |

---

## 1. CLI — interactive `claude` in Terminal.app

Setup: shell A `./start`; Terminal.app window C:

```sh
cd /Users/yegor-nextcode/work/pet/notch-orchestrator/sandbox
claude --permission-mode default
```

Start a fresh `claude` for each lettered part unless a check says otherwise.

### 1.A Connection

**C1. Hooks reach the receiver.**
- Do: start `claude` as above, accept the trust dialog, send P-PLAIN.
- Look at: shell A — `InstructionsLoaded`, `SessionStart`, `UserPromptSubmit`, `Stop`.
- Write down: events seen; `permission_mode` value; `./sessions last --env`
  output (keep `CLAUDE_CODE_ENTRYPOINT` and the TTY in the process chain).

### 1.B Permission over HTTP (finding 1) and the native dialog (finding 2)

**C2. Allow is honoured.**
- Do: `./answer note "C2"`; send P-BASH; wait for `>>> PENDING`; wait 5 s; `./answer allow`.
- Look at: window C while pending (is the native "Do you want to proceed?" dialog visible?) and after the answer (does it disappear, does the script output appear?).
- Write down: dialog shown in parallel / hidden; what the transcript says after allow; `./sessions last`.

**C3. Deny is honoured.**
- Do: `./answer note "C3"`; send P-BASH; `./answer deny`.
- Look at: window C — tool did not run; what the agent says.
- Write down: transcript wording; did the agent retry (new PENDING)?

**C4. Deny with a reason — does the agent see it?**
- Do: `./answer note "C4"`; send P-BASH; `./answer deny "Not now: the notch owner says use data/colors.txt instead"`; then send P-AFTER.
- Look at: whether the agent's reply quotes the reason.
- Write down: quoted text; whether the reason is also visible to you in the transcript.

**C5. Deny with interrupt.**
- Do: `./answer note "C5"`; send P-BASH; `./answer deny "stop" --interrupt`.
- Look at: does the turn end immediately; is there a `Stop` event in shell A?
- Write down: events after the deny; what window C shows.

**C6. Human answers natively first — Yes.**
- Do: `./answer note "C6"`; send P-SLOW; when PENDING appears do **not** answer in shell B; in window C choose "Yes"; wait for the script to finish (60 s) and 30 s more; then `./answer`.
- Look at: shell A for `CLIENT CLOSED THE CONNECTION`; whether `./answer` still lists the request after the tool finished and after `Stop`.
- Write down: was the hook request cancelled, and when (at the click / at tool end / at Stop / never); then run `./answer allow` on the stale request and note whether anything happens in window C.

**C7. Human answers natively first — No.**
- Do: `./answer note "C7"`; send P-BASH; in window C choose "No" (or Esc).
- Look at: shell A — disconnect line and its delay; which events follow (Stop? PostToolBatch? nothing?).
- Write down: events after the native No; state of window C (interrupted, waiting for input?).

**C8. Receiver returns no decision.**
- Do: `./answer note "C8"`; send P-BASH; `./answer none`.
- Look at: window C — the native dialog should simply stay; answer it there.
- Write down: any visible trace of the hook; events after the native answer.

**C9. Receiver returns no decision immediately.**
- Do: `./answer mode perm none`; `./answer note "C9"`; send P-BASH; answer natively; afterwards `./answer mode perm hold`.
- Look at: any flicker / delay / message before the native dialog.
- Write down: difference from a session with no hooks at all, if any.

**C10. Receiver not running.**
- Do: `./stop`; in window C send P-BASH, answer natively, then send P-PLAIN; then `./start` again in shell A.
- Look at: window C — "hook error … ECONNREFUSED" lines, their number and where they appear (transcript, status area, only with ctrl+o); any delay.
- Write down: exact wording and count per turn; does anything block. (Bears on "behaves as if never installed".)

**C11. Non-2xx.**
- Do: `./answer note "C11"`; send P-BASH; `./answer http500`; answer natively.
- Look at / write down: as C10 — is an error shown, and how.

**C12. Hook timeout (cheap variant).**
- Do: quit `claude`; `./install-sandbox-hooks.py --perm-timeout 20`; start `claude --permission-mode default` again; `./answer note "C12"`; send P-BASH; touch nothing for 40 s.
- Look at: shell A at ~20 s (`CLIENT CLOSED THE CONNECTION`); window C at ~20 s (does the dialog stay? any message?).
- Write down: what happened at the timeout; then answer natively. **Restore:** quit `claude`, run `./install-sandbox-hooks.py`.

**C13. Notification timing.**
- Do: `./answer note "C13"`; send P-BASH; leave both the dialog and shell B alone for 15 s without typing; then `./answer allow`.
- Look at: shell A — `Notification notification_type=permission_prompt` and its delay after `PermissionRequest`.
- Write down: delay in seconds; whether it arrives at all when the terminal is focused.

**C14. Edit permission.**
- Do: `./answer note "C14"`; send P-EDIT; `./answer`; `./sessions last --raw | tail -2` to see the payload; `./answer allow`.
- Look at: `tool_input` (old/new strings) and `permission_suggestions` in the payload.
- Write down: whether the payload has what the card needs for "a short excerpt of the change". Afterwards change FINAL back to DRAFT in `sandbox/notes.txt` by hand.

### 1.Q Multiple-choice question (finding 5)

**C15. Answer through PreToolUse.**
- Do: `./answer mode ask hold`; `./answer note "C15"`; send P-ASK; when PENDING shows `PreToolUse … AskUserQuestion`, look at window C first, then `./answer pick 2`.
- Look at: window C while pending (question dialog visible or only a spinner?); after the pick (does the agent say Green?).
- Write down: dialog visibility; agent's reply; `./sessions last`.

**C16. Answer through PermissionRequest (native dialog in parallel).**
- Do: `./answer note "C16"`; send P-ASK; `./answer none` on the PreToolUse request; a second PENDING (`PermissionRequest … AskUserQuestion`) should appear; look at window C; `./answer pick Blue`.
- Look at: question dialog on screen while PermissionRequest is pending; does it disappear after the pick; agent's reply.
- Write down: whether PermissionRequest fired for the question at all; dialog behaviour; reply.

**C17. Human answers the question natively first.**
- Do: `./answer note "C17"`; send P-ASK; `./answer none` on PreToolUse; then pick an option in window C.
- Look at: shell A — is the held PermissionRequest closed? `./answer` afterwards.
- Write down: stale request yes/no; events that follow (PostToolUse with the answer in `tool_response`?).

**C18. Two questions, multi-select, free text.**
- Do: `./answer note "C18"`; send P-ASK2; `./answer none`; then `./answer pick 3 1,3`. Repeat with `./answer pick "Magenta" 2`.
- Look at: agent's repetition of the answers.
- Write down: exact answers the agent reports.

**C19. Dismiss.**
- Do: `./answer note "C19"`; send P-ASK; on the PreToolUse request `./answer deny "The user is away; choose yourself"`.
- Look at / write down: does the agent continue on its own; wording it received (send P-AFTER).

### 1.F Fixture sequences (CLI)

For each: `./answer note "<name>"` first, and `./sessions last --save <name>` after.
Use `./answer mode perm allow` where a prompt says "auto-allow", and set it
back to `hold` afterwards.

**C20. Normal turn** — fresh `claude`; send P-PLAIN; wait 70 s after the reply (to catch `Notification idle_prompt`); exit with `/exit`. Save as `cli-normal-turn`. Write down: `SessionEnd reason`.

**C21. Turn with a permission request** — fresh `claude`; send P-BASH; wait 10 s; `./answer allow`; `/exit`. Save as `cli-permission-allow`. Repeat with `./answer deny "no"` → `cli-permission-deny`.

**C22. Turn with subagents** — `./answer mode perm allow`; fresh `claude`; send P-SUB; wait until the final summary; `/exit`. Save as `cli-subagents`. Write down: number of `SubagentStart` / `SubagentStop`, whether a `Stop` arrives before the last `SubagentStop`, any Claude-started `UserPromptSubmit`.

**C23. Killed session** — `./answer mode perm allow`; fresh `claude`; send P-SLOW; after ~10 s in shell B: `kill -9 $(./sessions last --pid)`. Save as `cli-killed`. Write down: last event received; confirm no `Stop` / `SessionEnd`; `pgrep -fl slow.sh` (orphaned child?) then `pkill -f slow.sh`.

**C24. Resumed session** — fresh `claude`; send P-PLAIN; `/exit`; then `claude --permission-mode default --continue`; send P-PLAIN again; `/exit`. Save as `cli-resumed`. Then resume the killed session from C23 with `claude --resume` (pick it in the list), send P-PLAIN, `/exit`, save as `cli-resumed-after-kill`. Write down: `SessionStart source` values; whether `session_id` stays the same across resume.

**C25. Compaction** — fresh `claude`; send P-PLAIN twice; type `/compact`; after it finishes send P-PLAIN; `/exit`. Save as `cli-compaction`. Write down: order of `PreCompact`, `SessionStart source=compact`, `PostCompact`; any `SubagentStop` with an empty `agent_type`; any `Stop`; whether "PreCompact … completed successfully" lines are printed in the transcript.

**C26. `/clear`** (cheap extra) — in a session with one turn type `/clear`, then P-PLAIN. Save as `cli-clear`. Write down: `SessionEnd reason=clear`, new `session_id`?

---

## 2. Claude desktop app — Code tab, session on the sandbox folder

Setup: shell A `./start`. In the desktop app open the Code tab, start a new
**local** session on `…/notch-orchestrator/sandbox` (no worktree, see 0.1.4),
permission mode "ask" / manual. Start a new session per lettered part unless
stated otherwise.

### 2.A Connection

**D1. Hooks reach the receiver.**
- Do: send P-PLAIN.
- Look at: shell A — same events as C1? `cwd` = sandbox?
- Write down: events seen; `permission_mode`; anything missing compared with C1 (e.g. `SessionStart`, `Notification`).

**D2. What distinguishes a desktop session.**
- Do: `./sessions last --env`; `./sessions last --raw | head -3`.
- Look at: `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_DESKTOP_APP_VERSION`, `CLAUDE_CODE_HOST_SESSION_ID`, `CLAUDE_CODE_EXECPATH`, `__CFBundleIdentifier`, the process chain (parent = `Claude.app`?), HTTP `User-Agent`, payload keys.
- Write down: every field that differs from C1. Check whether `CLAUDE_CODE_HOST_SESSION_ID` (`local_<uuid>`) matches the id in the desktop app's own session record (prototype/env has the finder).

### 2.B Permission over HTTP (finding 1) and the native dialog (finding 2)

**D3. Allow is honoured.**
- Do: `./answer note "D3"`; send P-BASH; wait for PENDING; wait 5 s; `./answer allow`.
- Look at: the app while pending — is its permission card shown at the same time? After the answer — does the card disappear by itself, what label does the tool call get?
- Write down: shown in parallel / hidden / appears late; behaviour after allow; `./sessions last`.

**D4. Deny.** As C3 with note "D4". Write down the app's rendering of the denied call.

**D5. Deny with a reason.** As C4 with note "D5". Write down: reason quoted by the agent yes/no; reason visible in the app UI yes/no.

**D6. Deny with interrupt.** As C5 with note "D6".

**D7. Human answers in the app first — allow.**
- Do: `./answer note "D7"`; send P-SLOW; do not answer in shell B; click the app's allow button; wait for the tool to finish plus 30 s; `./answer`.
- Look at: shell A for `CLIENT CLOSED THE CONNECTION` and when.
- Write down: is the hook request cancelled — at the click, at tool end, at Stop, or never (headless expectation: never, 0.4 e). Then `./answer allow` on the stale request: does anything visible happen?

**D8. Human answers in the app first — deny.**
- Do: `./answer note "D8"`; send P-BASH; click the app's deny button.
- Look at: shell A — disconnect or not; following events (PostToolBatch, Stop, PermissionDenied?).
- Write down: how the receiver could learn that the request is gone.

**D9. No decision.** As C8 (`./answer none`, then answer in the app), note "D9".

**D10. No decision immediately.** As C9 (`./answer mode perm none`), note "D10". Restore `./answer mode perm hold`.

**D11. Receiver not running.**
- Do: `./stop`; send P-BASH, answer in the app, send P-PLAIN; `./start`.
- Look at: the app's transcript — hook error rows? banners? delays?
- Write down: exact wording and count per turn, or "nothing visible".

**D12. Non-2xx.** As C11, note "D12".

**D13. Hook timeout.** As C12 (`--perm-timeout 20`, **new desktop session** afterwards so the changed settings are loaded), note "D13". Restore with `./install-sandbox-hooks.py` and start a new session.

**D14. Notification timing.** As C13, note "D14". Write down the delay of `Notification permission_prompt` and whether it fires while the app window is focused.

**D15. App in the background.**
- Do: `./answer note "D15"`; send P-BASH; immediately switch to another app (Cmd-Tab) and answer from shell B with `./answer allow`.
- Look at: when you return — did the session continue without you touching the app?
- Write down: yes/no. (This is the product's core promise.)

**D16. Edit permission.** As C14, note "D16". Also write down whether the app shows its own diff card in parallel.

### 2.Q Multiple-choice question (finding 5)

**D17. Answer through PreToolUse.** As C15, note "D17". Write down: is the app's question card shown while the hook is held; agent's reply after `./answer pick 2`; how the answered question is rendered in the app.

**D18. Answer through PermissionRequest.** As C16, note "D18". Write down: does `PermissionRequest` fire for the question in the desktop app; is the card dismissed after `./answer pick Blue`; agent's reply.

**D19. Human answers in the app first.** As C17, note "D19".

**D20. Two questions / multi-select / free text.** As C18, note "D20".

**D21. Is the tool offered at all?** If the agent says it has no AskUserQuestion tool in D17, write that down with the app version and stop the 2.Q part.

### 2.F Fixture sequences (desktop)

Same procedure as 1.F: `./answer note "<name>"`, then `./sessions last --save <name>`.

**D22. Normal turn** — new session; P-PLAIN; wait 70 s. Save `desktop-normal-turn`. Write down whether closing / archiving the session in the app produces `SessionEnd` (try it) and with which `reason`.

**D23. Turn with a permission request** — P-BASH, wait 10 s, `./answer allow` → `desktop-permission-allow`; again with `./answer deny "no"` → `desktop-permission-deny`; once more answering in the app → `desktop-permission-native`.

**D24. Turn with subagents** — `./answer mode perm allow`; P-SUB → `desktop-subagents`. Write down the same points as C22.

**D25. Killed session** — `./answer mode perm allow`; P-SLOW; after ~10 s `kill -9 $(./sessions last --pid)` → `desktop-killed`. Write down: last event; what the app shows for that session; does the app restart the process by itself (new `SessionStart`? same `session_id`?).

**D26. Resumed session** — after D25 send P-PLAIN in the same desktop session → `desktop-resumed-after-kill`. Then quit the desktop app completely (Cmd-Q) while a session is idle, note whether `SessionEnd` arrives, reopen the app, open that session, send P-PLAIN → `desktop-resumed-after-app-restart`. Write down: `SessionStart source`, whether `session_id` and `transcript_path` are unchanged.

**D27. Compaction** — two P-PLAIN turns, then `/compact` (if the app accepts the command; otherwise write down how compaction is triggered there), then P-PLAIN → `desktop-compaction`. Write down the same points as C25.

**D28. Quit the app while a permission request is pending** (cheap extra) — P-BASH, leave it pending, Cmd-Q the app. Write down: disconnect in shell A? `SessionEnd`? → `desktop-quit-while-pending`.

---

## 3. When you are done

1. `./stop`; `./answer mode …` changes are gone with the receiver.
2. Check `sandbox/.claude/settings.json` still has the 3600 s PermissionRequest timeout (`./install-sandbox-hooks.py` restores it).
3. Fill in spec #1 → "Prototype findings":
   - **1. Permission hook over HTTP in desktop sessions:** D3–D6, D15.
   - **2. Native dialog behaviour while the hook waits:** C2, C6–C12 and D3, D7–D13 (parallel / hidden / dismissed; who wins; what the receiver sees when the human answers natively; receiver down; no decision).
   - **5. Hook-supplied answer to a multiple-choice question:** C15–C19, D17–D21 (which hook event; is the native card shown in parallel).
4. Leave `logs/recorded/cli-*.jsonl` and `desktop-*.jsonl` for fixture curation.

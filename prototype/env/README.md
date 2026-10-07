# prototype/env — environment checks for ticket #3

Throwaway prototype for spec findings 3 (status line), 4 (desktop deep link and session mapping)
and 6 (self-signed certificate, quarantine). No tests, no architecture; the value is the answers.
Start with **CHECKLIST.md**.

Nothing here changes global settings. The status line is registered only in
`sandbox/.claude/settings.json` (key `statusLine`; the `hooks` key there belongs to `prototype/hooks/`).
`~/Library/Application Support/Claude/` is only ever read.

| File | What it is |
| - | - |
| `CHECKLIST.md` | the manual checks, in order: CLI, desktop, mapping, deep links, signing, quarantine |
| `statusline-logger.sh` | status line command: appends each stdin payload to `logs/statusline.jsonl`, prints `[proto-sl] ...` |
| `statusline-summary.sh` | per session: first record with `rate_limits`, its shape, how many records precede it |
| `logs/` | `statusline.jsonl` (git-ignored: contains local paths and session ids) |
| `find-desktop-session.py` | hook `session_id` -> desktop record (sessionId, title, cwd, record path); `--list`, `--json` |
| `DESKTOP-SESSIONS.md` | record schema found, desktop-vs-CLI rule, caveats |
| `deeplinks.sh` | prints the candidate `open 'claude://...'` commands for one session; never opens |
| `DEEPLINKS.md` | routes found in the desktop app, which id each expects, ranked candidates |
| `signing/main.swift` | test app: one Apple event to Terminal, shows result + own version |
| `signing/build.sh` | `adhoc` / `selfsigned` / `all`: versions 1.0 and 1.1 into `signing/.build/<variant>/<version>/` |
| `signing/install.sh` | copies one build to the fixed path `signing/.build/installed/NotchAETest-<variant>.app` |
| `signing/show-requirements.sh` | designated requirement of every bundle |
| `quarantine-check.sh` | local HTTP server + curl download + `xattr` + `spctl`; `--serve` for the browser comparison |

## Verified while preparing (2026-10-07, Claude Code 2.1.236, Claude desktop 2.26454.0, Darwin 27)

- The status line command from `sandbox/.claude/settings.json` runs in an interactive terminal session at
  start, with no trust dialog (one real record is in the log). No `rate_limits` there: the CLI was not logged in.
- Record schema and resolver: see `DESKTOP-SESSIONS.md`.
- Ad-hoc builds: designated requirement is `cdhash H"..."`, different for 1.0 and 1.1.
- `curl` download + unpack: no `com.apple.quarantine`; `spctl --assess` says `rejected`.

## Surprises worth knowing

- Desktop-run sessions carry `CLAUDE_CODE_ENTRYPOINT=claude-desktop` and
  `CLAUDE_CODE_HOST_SESSION_ID=local_...` in their environment: a possible direct desktop marker and id.
- `cliSessionId` in a desktop record is not stable; older ids move to `priorCliSessionIds`.
- `claude://resume?session=<CLI uuid>` accepts the hook id directly but imports sessions it does not own.
- `~/Library/Application Support/Claude/plan-usage-history.json` holds the desktop app's own usage samples
  (`t` in ms, `org`, `u.fh`, `u.sd`: five-hour and seven-day percentages). Not continuously updated (last
  sample was hours old). A possible fallback source for limits if the status line does not run in desktop sessions.

Not verified (needs the human): everything in CHECKLIST.md marked as a check.

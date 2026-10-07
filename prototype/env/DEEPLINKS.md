# Deep links into a specific desktop Code session (ticket #3, finding 4)

Throwaway prototype notes. Routes were **read from the app, not exercised**:
Claude desktop 2.26454.0, main-process bundle inside `app.asar` (function handling `open-url`).
Nothing here has been opened by the agent. Run the commands yourself, one at a time.

Print the commands filled in for one session (prints only, never opens):

```bash
prototype/env/deeplinks.sh <local_... desktop id | CLI/hook session_id>
```

## Two identifiers

| Name | Looks like | Where it comes from |
| - | - | - |
| desktop sessionId | `local_<uuid>` | record file name / `sessionId` field; env `CLAUDE_CODE_HOST_SESSION_ID` inside a desktop session |
| CLI session id | bare `<uuid>` | hook `session_id`, status line `session_id`, record field `cliSessionId` |

They are different uuids (in 53 of 54 records on this machine). Only sessions imported from the
CLI get `local_<the CLI uuid>`.

## How the app dispatches `claude://`

Scheme `claude:`; the URL **host** selects the area: `code`, `claude.ai`, `cowork`, `resume`,
`login`, `hotkey`. The window is restored/shown/focused only when the handler accepts the link;
a rejected link does nothing at all. All of it is off if the managed setting `disableDeepLinks`
is on. `code/continue` and `code/needs-input` are additionally ignored when the user is logged out.
Optional `source=<tag>` query parameter is telemetry only.

Routes under host `code`:

| Path | Query | Identifier | Purpose |
| - | - | - | - |
| `/continue` | `session=last` or `session=local_...` | desktop id, must match `^local_[A-Za-z0-9-]{1,64}$` | open that session |
| `/needs-input` | optional `session=local_...` | desktop id | open a session that waits for a tool permission |
| `/new` | `q`/`prompt`, `folder` (repeatable), `file`, ssh params | none | new session (documented) |
| `/search` | none | none | session search |
| `/<id>` | `artifact`, `org` | only `cse_...` / `session_...` (cloud/remote ids) | open a remote session |
| `/project/<id>` | `thread`, `msg` | project id | cloud project thread |

Host `resume`: `claude://resume?session=<uuid>` takes a **CLI** session uuid.
Host `claude.ai`: `claude://claude.ai/<web path>` forwards web-app paths; `/epitaxy/...` (the internal
route prefix of the Code tab; a session route is `/epitaxy/<desktop id>`) is navigated to directly,
`/code/...` is handed to the renderer's own deep-link handler.

## Candidates, most likely first

Replace `<SESSION_ID>` with the id type named in the heading.

### 1. `code/continue` (desktop id) — expected: opens exactly that session

```bash
open 'claude://code/continue?session=<SESSION_ID>'      # <SESSION_ID> = local_...
```

Looks up a **non-archived** session whose `sessionId` equals the parameter and navigates to it.
If there is no such session (unknown id, archived) it falls back to the Code home screen, so
"app came to front on the wrong screen" means "id not found". This is the route the app itself
uses for its Dock menu "Continue ..." entry and Spotlight items.

### 2. Direct route (desktop id) — expected: opens exactly that session

```bash
open 'claude://claude.ai/epitaxy/<SESSION_ID>'          # <SESSION_ID> = local_...
```

No lookup in the main process, the path is passed to the web app router as is. Not gated by the
logged-in check. What the UI shows for an unknown id is unknown. The name `epitaxy` is internal
and may change between app versions, so this is a fallback, not a first choice.

### 3. `resume` (CLI id) — expected: opens the desktop session that owns this CLI session, or imports it

```bash
open 'claude://resume?session=<SESSION_ID>'             # <SESSION_ID> = CLI/hook session_id (bare uuid)
```

The only route that takes the hook `session_id` directly. Behaviour read from the code:
- a desktop session exists with id `local_<that uuid>`: opens it;
- a desktop session currently holds that uuid as its live transcript (`cliSessionId`): opens it,
  **un-archiving it** if it was archived;
- otherwise: **imports the CLI transcript as a new desktop session** (`local_<uuid>`), marks the
  folder as trusted without a dialog, then opens it. Errors show a toast ("Couldn't open that session...").

Caveats: a uuid that is only in `priorCliSessionIds` (the session was since cleared/compacted/resumed
under a new id) is not treated as owned, so it would be imported as a second session. For a session
running in a terminal this creates a desktop copy of it, which is not a "jump". Useful as
"open this CLI session in the desktop app", risky as a generic jump. Test it last.

### 4. `code/needs-input` (desktop id) — expected: opens that session only while it waits for a permission

```bash
open 'claude://code/needs-input?session=<SESSION_ID>'   # <SESSION_ID> = local_...
```

Considers only sessions with a pending tool permission. If the given one is not waiting, it opens
the **first other waiting session**, and if none waits, the Code home screen. Fits the
"waiting for permission" card, but can land on a different session.

### 5. Web-style path (desktop id) — outcome unknown

```bash
open 'claude://claude.ai/code/<SESSION_ID>'             # <SESSION_ID> = local_...
```

Forwarded to the renderer as `https://claude.ai/code/local_...`; whether the web app maps it to the
local session is not visible from the main process.

### 6. Negative controls — expected: rejected, nothing happens

```bash
open 'claude://code/<SESSION_ID>'                       # local_... : path form accepts only cse_/session_ ids
open 'claude://code/continue?session=<SESSION_ID>'      # bare CLI uuid : fails the local_ pattern
```

### 7. Positive control — expected: opens the most recently active non-archived session

```bash
open 'claude://code/continue?session=last'
```

## Conclusion to verify

The desktop deep link expects the **desktop** `local_...` id, so the jump needs the resolver
(`find-desktop-session.py`: hook `session_id` -> record -> `sessionId`), or the environment variable
`CLAUDE_CODE_HOST_SESSION_ID` if command hooks inherit it. `resume` accepts the CLI id but has
import side effects. Also check each link with the app **not running** (cold start) once the
winner is known.

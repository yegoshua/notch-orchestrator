# Desktop session records (ticket #3, finding 4, mapping part)

Throwaway prototype notes. Observed on Claude desktop 2.26454.0, 54 records, read-only.
Examples are redacted: no titles or prompts from the real records are copied here.

## Location

```
~/Library/Application Support/Claude/claude-code-sessions/
  <accountUuid>/<organizationUuid>/
    local_<uuid>.json        one record per desktop Code session; file name == sessionId + ".json"
    deleted_<uuid>/          empty directory left behind for a deleted session (tombstone)
    scheduled-tasks.json     not a session record
    backlog/tasks.json       not a session record
```

Both directory uuids equal the env variables `CLAUDE_CODE_ACCOUNT_UUID` / `CLAUDE_CODE_ORGANIZATION_UUID`
seen inside a desktop session. Several accounts/orgs mean several directories: scan all of them.

## Fields that matter

| Field | Type | Meaning |
| - | - | - |
| `sessionId` | string `local_<uuid>` | desktop session id; what deep links expect |
| `cliSessionId` | string uuid | **current** Claude Code session id = hook / status line `session_id`; transcript is `~/.claude/projects/<slug>/<cliSessionId>.jsonl` (found for 54 of 54) |
| `priorCliSessionIds` | string[] | earlier CLI ids of the same desktop session (present in 27 of 54 records, up to 21 entries). `cliSessionId` changes over a session's life |
| `title` | string, optional | session title (missing in 10 of 54); `titleSource` is `auto` or `user` |
| `cwd` | string | directory the session runs in; for worktree sessions the worktree path |
| `originCwd` | string | folder the user picked; differs from `cwd` only for worktree sessions (3 of 54) |
| `worktreePath`, `worktreeName`, `branch`, `sourceBranch` | string, optional | present for worktree sessions; path is `<originCwd>/.claude/worktrees/<name>` |
| `isArchived` | bool | archived flag (false in all 54 here, so not observed as true) |
| `createdAt`, `lastActivityAt`, `lastFocusedAt` | int, epoch **milliseconds** | timestamps |
| `model`, `effort`, `permissionMode` | string | session settings (`permissionMode` seen: `auto`, `acceptEdits`) |
| `completedTurns` | int | turn counter |
| `bridgeSessionIds` | string[] `session_...` | cloud/remote-control ids, unrelated to hooks |
| `forkedFromSessionId`, `spawnedFrom.sessionId`, `dispatchParentId` | string, optional | parent desktop session for forks / spawned tasks |

Named in the app code but not present in any record here (so unverified): `unarchivedCliSessionId`,
`preClearCliSessionId`, `historyOnlyCliSessionId`, `importedFrom`. The resolver checks them anyway.

Redacted example:

```json
{
  "sessionId": "local_11111111-2222-3333-4444-555555555555",
  "cliSessionId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "priorCliSessionIds": ["99999999-8888-7777-6666-555555555555"],
  "title": "<redacted>",
  "cwd": "/Users/me/project",
  "originCwd": "/Users/me/project",
  "isArchived": false,
  "createdAt": 1790000000000,
  "lastActivityAt": 1790000300000,
  "model": "claude-opus-5-5",
  "permissionMode": "auto"
}
```

## Resolver

```bash
prototype/env/find-desktop-session.py <hook session_id>   # exit 0 = desktop record found, 1 = none
prototype/env/find-desktop-session.py --list 10
prototype/env/find-desktop-session.py --json <hook session_id>
```

Match order: `cliSessionId` (current) > lineage (`priorCliSessionIds`, ...) > `sessionId == local_<id>`.

## Desktop session or CLI session?

- A record references the `session_id` => desktop session. No record => CLI session.
- Verified both ways: the id of the desktop session this prototype was written in resolves to its
  record; the id of a session started with `claude` in a terminal pty resolves to nothing.
- Second, independent signal (seen in the environment of a desktop-run session, **not yet checked
  inside a hook**): `CLAUDE_CODE_ENTRYPOINT=claude-desktop` (a terminal session has `cli`),
  `CLAUDE_CODE_HOST_SESSION_ID=local_...` (the desktop id itself), `CLAUDE_CODE_DESKTOP_APP_VERSION`.
  The status line logger records these, so the checklist tells whether child commands inherit them.
  HTTP hooks have no environment, so for them the record lookup stays the way.

## Caveats

- **The id moves.** `cliSessionId` is replaced during the life of a desktop session and the old one
  goes to `priorCliSessionIds`. A resolver must also search the lineage, and should re-resolve on
  each event rather than cache `session_id -> record` forever. When exactly the record is rewritten
  relative to the first hook of the new id (a race) is not known: check in the checklist.
- **Timing at session start.** Whether the record already contains `cliSessionId` when the very first
  hook (`SessionStart`) fires is not known. Retry for a short time before deciding "CLI".
- **Worktrees.** `cwd` is the worktree, `originCwd` the real project folder. Show `originCwd` (and
  `worktreeName`) to the user; hook `cwd` equals record `cwd`, not `originCwd`.
- **Multiple records per CLI id.** None among 54 records here (0 ids referenced twice), but forks and
  CLI imports could produce it; the resolver prints all hits, strongest first.
- **Archived sessions** appear to keep their record with `isArchived: true`, judging by the app code (not
  observed here). `code/continue` ignores archived sessions; `resume` un-archives.
- **Deleted sessions** leave only an empty `deleted_<uuid>` directory: a hook from a still-running
  process of a deleted session would look like a CLI session.
- **CLI session imported into desktop** (`claude://resume`): from then on the same uuid has a record
  although a terminal may still be running it.
- The format is private and undocumented; it can change with any app update.

#!/usr/bin/env python3
"""Throwaway prototype (ticket #3). Desktop session resolver. READ-ONLY.

Maps a Claude Code session id (the `session_id` seen by hooks / the status line)
to the Claude desktop app's per-session record under
~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<orgUuid>/local_<uuid>.json

Usage:
  find-desktop-session.py <cli-session-id>      # resolve one id
  find-desktop-session.py --list [N]            # N most recently active records (default 15)
  find-desktop-session.py --json <cli-session-id>

Exit code: 0 = desktop record found, 1 = no record (treat as a plain CLI session), 2 = usage/IO error.
"""
import glob
import json
import os
import sys
from datetime import datetime

BASE = os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions")

# Where a CLI session id can appear in a record, in order of how strong the match is.
CURRENT_FIELDS = ("cliSessionId", "unarchivedCliSessionId")          # live transcript handles
LINEAGE_FIELDS = ("preClearCliSessionId", "historyOnlyCliSessionId")  # older ids of the same desktop session
LINEAGE_LISTS = ("priorCliSessionIds",)


def load_records():
    for path in glob.glob(os.path.join(BASE, "*", "*", "local_*.json")):
        try:
            with open(path, "r", encoding="utf-8") as f:
                rec = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(rec, dict) and "sessionId" in rec:
            yield path, rec


def match_kind(rec, cli_id):
    cid = cli_id.lower()
    for k in CURRENT_FIELDS:
        if str(rec.get(k, "")).lower() == cid:
            return "current:" + k
    for k in LINEAGE_FIELDS:
        if str(rec.get(k, "")).lower() == cid:
            return "lineage:" + k
    for k in LINEAGE_LISTS:
        if cid in [str(x).lower() for x in (rec.get(k) or [])]:
            return "lineage:" + k
    # Sessions imported from the CLI get the desktop id local_<cli uuid>.
    if str(rec.get("sessionId", "")).lower() == "local_" + cid:
        return "name:sessionId==local_<cli id>"
    return None


def ts(ms):
    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return "?"


def summary(path, rec, kind=None):
    out = {
        "sessionId": rec.get("sessionId"),
        "cliSessionId": rec.get("cliSessionId"),
        "title": rec.get("title"),
        "cwd": rec.get("cwd"),
        "originCwd": rec.get("originCwd"),
        "worktreePath": rec.get("worktreePath"),
        "isArchived": rec.get("isArchived"),
        "lastActivityAt": ts(rec.get("lastActivityAt", 0)),
        "priorCliSessionIds": len(rec.get("priorCliSessionIds") or []),
        "record": path,
    }
    if kind:
        out["match"] = kind
    return out


def main(argv):
    as_json = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 2
    if not os.path.isdir(BASE):
        print("no desktop session store at " + BASE, file=sys.stderr)
        return 2

    if argv[0] == "--list":
        n = int(argv[1]) if len(argv) > 1 else 15
        recs = sorted(load_records(), key=lambda pr: pr[1].get("lastActivityAt", 0), reverse=True)[:n]
        rows = [summary(p, r) for p, r in recs]
        if as_json:
            print(json.dumps(rows, indent=2, ensure_ascii=False))
            return 0
        for s in rows:
            flags = ("A" if s["isArchived"] else "-") + ("W" if s["worktreePath"] else "-")
            print("{lastActivityAt}  {f}  {sessionId}  cli={cliSessionId} (+{priorCliSessionIds} prior)".format(f=flags, **s))
            print("    title: {title!r}".format(**s))
            print("    cwd:   {cwd}".format(**s) + ("   (origin: {originCwd})".format(**s) if s["originCwd"] != s["cwd"] else ""))
        print("\nflags: A = archived, W = runs in a git worktree")
        return 0

    cli_id = argv[0]
    hits = []
    for path, rec in load_records():
        kind = match_kind(rec, cli_id)
        if kind:
            hits.append(summary(path, rec, kind))
    # Strongest match first: current handle, then lineage, then name; newest first inside a class.
    order = {"current": 0, "lineage": 1, "name": 2}
    hits.sort(key=lambda s: s["lastActivityAt"], reverse=True)
    hits.sort(key=lambda s: order[s["match"].split(":")[0]])

    if as_json:
        print(json.dumps(hits, indent=2, ensure_ascii=False))
        return 0 if hits else 1
    if not hits:
        print("NO desktop record references " + cli_id)
        print("=> treat it as a CLI session (or a desktop session whose record was deleted).")
        return 1
    if len(hits) > 1:
        print("WARNING: {} records reference this id; strongest match first.\n".format(len(hits)))
    for s in hits:
        print("desktop sessionId: {sessionId}".format(**s))
        print("match:             {match}".format(**s))
        print("title:             {title!r}".format(**s))
        print("cwd:               {cwd}".format(**s))
        print("originCwd (folder): {originCwd}".format(**s))
        if s["worktreePath"]:
            print("worktreePath:      {worktreePath}".format(**s))
        print("current cliSessionId: {cliSessionId}  (prior ids: {priorCliSessionIds})".format(**s))
        print("isArchived:        {isArchived}".format(**s))
        print("lastActivityAt:    {lastActivityAt}".format(**s))
        print("record:            {record}".format(**s))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

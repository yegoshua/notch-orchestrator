#!/bin/bash
# Throwaway prototype (ticket #3). PRINTS candidate deep links for one session.
# It never opens anything: copy one `open '...'` line at a time into a terminal yourself.
#
# Usage: deeplinks.sh <desktop sessionId local_...  |  CLI/hook session_id uuid>
# Whichever id is given, the other one is looked up in the desktop records (read-only).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ID="${1:-}"
[ -n "$ID" ] || { echo "usage: $0 <local_... | cli-session-uuid>" >&2; exit 2; }

LOCAL="<DESKTOP_SESSION_ID>"; CLI="<CLI_SESSION_ID>"
if [[ "$ID" == local_* ]]; then
  LOCAL="$ID"
  rec=$(ls "$HOME/Library/Application Support/Claude/claude-code-sessions"/*/*/"$ID.json" 2>/dev/null | head -1)
  if [ -n "$rec" ]; then CLI=$(/usr/bin/jq -r '.cliSessionId // "<CLI_SESSION_ID>"' "$rec"); else echo "# note: no desktop record named $ID" ; fi
else
  CLI="$ID"
  found=$("$DIR/find-desktop-session.py" --json "$ID" | /usr/bin/jq -r '.[0].sessionId // empty')
  if [ -n "$found" ]; then LOCAL="$found"; else echo "# note: no desktop record references $ID (CLI-only session); links needing a desktop id keep a placeholder"; fi
fi

cat <<OUT
# desktop sessionId: $LOCAL
# CLI session id:    $CLI
# Run ONE line at a time, note what the app did, then go on. See DEEPLINKS.md for what each should do.

# 1. continue by desktop id (best candidate)
open 'claude://code/continue?session=$LOCAL'

# 2. direct route by desktop id
open 'claude://claude.ai/epitaxy/$LOCAL'

# 3. resume/import by CLI id (SIDE EFFECT: imports the session into the desktop app if it does not own it yet)
open 'claude://resume?session=$CLI'

# 4. needs-input by desktop id (only meaningful while that session waits for a permission)
open 'claude://code/needs-input?session=$LOCAL'

# 5. web-style code path by desktop id (handed to the renderer; outcome unknown)
open 'claude://claude.ai/code/$LOCAL'

# 6. negative controls (expected: nothing happens, or the app only comes to front)
open 'claude://code/$LOCAL'
open 'claude://code/continue?session=$CLI'

# 7. positive control (expected: opens the most recently active session, whichever it is)
open 'claude://code/continue?session=last'
OUT

#!/bin/bash
# Throwaway prototype (ticket #3). Status line logger.
# Registered ONLY in sandbox/.claude/settings.json (never in ~/.claude/settings.json).
# Appends every stdin payload, wrapped with a timestamp, to logs/statusline.jsonl
# and prints one short visible line so a human can see that it ran.
# Also records three environment variables that the desktop app was seen to set for
# its Code sessions (CLAUDE_CODE_ENTRYPOINT, CLAUDE_CODE_HOST_SESSION_ID,
# CLAUDE_CODE_DESKTOP_APP_VERSION) so we learn whether the status line command inherits them.
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$DIR/logs"
LOG="$LOG_DIR/statusline.jsonl"
mkdir -p "$LOG_DIR"

input="$(cat)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
epoch="$(date +%s)"

# Wrap the raw payload. If stdin is not valid JSON, keep it as a string in "raw".
if ! printf '%s' "$input" | /usr/bin/jq -c \
      --arg ts "$ts" --argjson epoch "$epoch" --arg ppid "$PPID" \
      --arg entry "${CLAUDE_CODE_ENTRYPOINT:-}" \
      --arg host_sid "${CLAUDE_CODE_HOST_SESSION_ID:-}" \
      --arg desktop_ver "${CLAUDE_CODE_DESKTOP_APP_VERSION:-}" \
      '{ts:$ts, epoch:$epoch, ppid:$ppid, entrypoint:$entry, host_session_id:$host_sid, desktop_app_version:$desktop_ver, input:.}' >>"$LOG" 2>/dev/null; then
  /usr/bin/jq -cn --arg ts "$ts" --argjson epoch "$epoch" --arg raw "$input" \
      '{ts:$ts, epoch:$epoch, parse_error:true, raw:$raw}' >>"$LOG"
fi

printf '%s' "$input" | /usr/bin/jq -r '
  def pct: if . == null then "-" else (.|tostring) + "%" end;
  (.session_id // "?" | .[0:8]) as $sid
  | if .rate_limits == null then "[proto-sl] no rate_limits | sid \($sid)"
    else "[proto-sl] 5h \(.rate_limits.five_hour.used_percentage|pct) 7d \(.rate_limits.seven_day.used_percentage|pct) | sid \($sid)"
    end' 2>/dev/null || echo "[proto-sl] ran (unparseable stdin)"

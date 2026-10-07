#!/bin/bash
# Throwaway prototype (ticket #3). Summarises logs/statusline.jsonl per session:
# how many records precede the first one with rate_limits, and the shape of rate_limits.
# Usage: statusline-summary.sh [path/to/statusline.jsonl]
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${1:-$DIR/logs/statusline.jsonl}"
[ -s "$LOG" ] || { echo "no log at $LOG (status line never ran)"; exit 1; }

/usr/bin/jq -rs '
  def shape: if type=="object" then with_entries(.value |= shape)
             elif type=="array" then [ (.[0] | shape) ] else type end;
  "records total: \(length)",
  "top-level input keys seen: \([.[].input | select(type=="object") | keys[]] | unique | join(", "))",
  "",
  ( group_by(.input.session_id // "unparseable")[]
    | sort_by(.epoch) as $r
    | ($r | map(.input.rate_limits != null) | index(true)) as $i
    | "session_id:   \($r[0].input.session_id // "?")",
      "  entrypoint: \($r | map(.entrypoint // "") | unique | join(","))   host_session_id(env): \($r | map(.host_session_id // "") | unique | join(","))",
      "  cwd:        \($r[0].input.cwd // "?")",
      "  version:    \($r[0].input.version // "?")   model: \($r[0].input.model.id // "?")",
      "  records:    \($r|length)   first: \($r[0].ts)   last: \($r[-1].ts)",
      ( if $i == null then "  rate_limits: NEVER present in this session"
        else "  rate_limits: first present in record #\($i + 1) (\($i) record(s) before it), at \($r[$i].ts), \($r[$i].epoch - $r[0].epoch)s after the first record",
             "  shape:       \($r[$i].input.rate_limits | shape | tojson)",
             "  first value: \($r[$i].input.rate_limits | tojson)",
             "  last value:  \($r[-1].input.rate_limits | tojson)",
             "  api duration at first appearance (ms): \($r[$i].input.cost.total_api_duration_ms // "?")"
        end ),
      "" )
' "$LOG"

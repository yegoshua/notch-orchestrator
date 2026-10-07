#!/bin/sh
# Command-type hook used for the events that do NOT support HTTP hooks
# (SessionStart, Setup). Forwards the hook's stdin JSON to the prototype
# receiver, plus a filtered dump of the environment and the parent process
# chain (useful to tell a CLI session from a desktop-app session and to find
# the TTY). Prints nothing: SessionStart stdout would be added to the context.
EVENT="${1:-unknown}"

ENV_B64=$(env \
  | grep -E '^(CLAUDE|ANTHROPIC_MODEL|TERM|TERM_PROGRAM|TERM_SESSION_ID|ITERM_SESSION_ID|__CFBundleIdentifier|VSCODE_|XPC_SERVICE_NAME|TMUX|SSH_TTY|PWD|SHLVL)' \
  | sed -E 's/^([^=]*(TOKEN|KEY|SECRET|PASSWORD|AUTH|CREDENTIAL|EMAIL|UUID)[^=]*)=.*/\1=<redacted>/' \
  | base64 | tr -d '\n')

PROC=""
P=$$
i=0
while [ "$i" -lt 8 ] && [ -n "$P" ] && [ "$P" -gt 1 ] 2>/dev/null; do
  LINE=$(ps -o pid=,ppid=,tty=,command= -p "$P" 2>/dev/null | cut -c1-300)
  [ -z "$LINE" ] && break
  PROC="$PROC$LINE
"
  P=$(ps -o ppid= -p "$P" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
PROC_B64=$(printf '%s' "$PROC" | base64 | tr -d '\n')

/usr/bin/curl -s -m 3 -o /dev/null -X POST \
  -H 'Content-Type: application/json' \
  -H 'X-Hook-Transport: command' \
  -H "X-Hook-Env-B64: $ENV_B64" \
  -H "X-Hook-Proc-B64: $PROC_B64" \
  --data-binary @- \
  "http://127.0.0.1:47821/hook/$EVENT" >/dev/null 2>&1
exit 0

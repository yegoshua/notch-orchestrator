#!/usr/bin/env python3
"""Write the prototype hooks into sandbox/.claude/settings.json.

Read-modify-write: only the top-level "hooks" key is replaced, every other key
(e.g. the statusLine owned by prototype/env) is preserved. Never touches
~/.claude/settings.json or any settings file outside sandbox/.

  ./install-sandbox-hooks.py            install / refresh the hooks
  ./install-sandbox-hooks.py --remove   remove the "hooks" key again
  ./install-sandbox-hooks.py --print    print the hooks block, change nothing
  ./install-sandbox-hooks.py --perm-timeout 20
                                        same as install, but PermissionRequest gets a 20 s hook
                                        timeout (for the hook-timeout check); run without the
                                        flag afterwards to restore 3600 s
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = os.path.normpath(os.path.join(HERE, "..", "..", "sandbox", ".claude", "settings.json"))
BASE = "http://127.0.0.1:47821/hook"

# Long timeout: these two can be held open by the receiver until a human answers.
HELD = {"PermissionRequest": 3600, "PreToolUse": 3600}
SHORT = 5

# Events that accept HTTP hooks in Claude Code 2.1.236 (docs + names present in the binary).
HTTP_EVENTS = [
    "SessionEnd",
    "InstructionsLoaded",
    "UserPromptSubmit",
    "UserPromptExpansion",
    "PreToolUse",
    "PermissionRequest",
    "PermissionDenied",
    "PostToolUse",
    "PostToolUseFailure",
    "PostToolBatch",
    "Notification",
    "SubagentStart",
    "SubagentStop",
    "TaskCreated",
    "TaskCompleted",
    "Stop",
    "StopFailure",
    "TeammateIdle",
    "ConfigChange",
    "CwdChanged",
    "DirectoryAdded",
    "PreCompact",
    "PostCompact",
    "Elicitation",
    "ElicitationResult",
]
# SessionStart and Setup only support command / mcp_tool hooks, so they go
# through a tiny curl forwarder that also reports environment + process chain.
COMMAND_EVENTS = ["SessionStart", "Setup"]
# Deliberately not hooked:
#   WorktreeCreate / WorktreeRemove - a hook there REPLACES git worktree behaviour
#   MessageDisplay                  - fires per streamed text chunk, pure noise here
#   FileChanged                     - needs a filename matcher, not relevant to #2
#   PreModelSwitch / PostModelSwitch - need Claude Code >= 2.1.251 (installed: 2.1.236)


def hooks_block():
    hooks = {}
    for ev in COMMAND_EVENTS:
        hooks[ev] = [{"hooks": [{
            "type": "command",
            "command": f'"$CLAUDE_PROJECT_DIR"/.claude/hooks/forward-to-receiver.sh {ev}',
            "timeout": SHORT,
        }]}]
    for ev in HTTP_EVENTS:
        hooks[ev] = [{"hooks": [{
            "type": "http",
            "url": f"{BASE}/{ev}",
            "timeout": HELD.get(ev, SHORT),
            "headers": {"X-Notch-Prototype": "sandbox"},
        }]}]
    return hooks


def main():
    if "--perm-timeout" in sys.argv:
        HELD["PermissionRequest"] = int(sys.argv[sys.argv.index("--perm-timeout") + 1])
    if "--print" in sys.argv:
        print(json.dumps({"hooks": hooks_block()}, indent=2))
        return
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    # Re-read immediately before writing; another agent owns the other keys.
    try:
        with open(SETTINGS) as f:
            settings = json.load(f)
    except FileNotFoundError:
        settings = {}
    if "--remove" in sys.argv:
        settings.pop("hooks", None)
    else:
        settings["hooks"] = hooks_block()
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(SETTINGS), prefix=".settings.", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, SETTINGS)
    print(f"wrote {SETTINGS}; top-level keys: {list(settings)}")


if __name__ == "__main__":
    main()

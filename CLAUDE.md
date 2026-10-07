# CLAUDE.md

Working code name: **notch-orchestrator**. A native macOS app (Swift, SwiftUI) that lives in the MacBook notch and orchestrates Claude Code sessions running in the CLI and in the Claude desktop app.

## Agent skills

### Issue tracker

Issues and specs live in this repo's GitHub Issues (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Development

```bash
swift build                 # type-check and build everything
swift test                  # session core and connection installer tests
swift test --filter SessionCoreTests
scripts/build-app.sh        # universal, ad-hoc signed bundle in .build/app/
```

Layout: `Sources/SessionCore` (pure state, tested against `fixtures/`), `Sources/ClaudeConnection` (settings transformation and installer, tested), `Sources/NotchApp` (receiver, overlay, menu; verified by hand).

On launch the app writes its hook entries into `~/.claude/settings.json`. When running a development build, point it somewhere else so it cannot affect real sessions:

```bash
".build/app/Notch Orchestrator.app/Contents/MacOS/NotchApp" \
  -claudeSettingsPath /path/to/test-project/.claude/settings.json \
  -supportDirectory /tmp/notch-support -port 47811
```

The reconciler reads `~/.claude` (session records and transcripts, read-only), so a development build lists the real sessions on the machine. `-claudeDataDirectory /path` points it elsewhere.

A permission request the user ignores goes back to Claude Code's own dialog after five minutes. `-requestTimeoutSeconds 20` shortens that for a check by hand.

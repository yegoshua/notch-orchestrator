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

It also reads the Claude desktop app's session records (read-only) to tell desktop sessions from CLI ones and to take their sidebar titles. `-claudeDesktopSessionsDirectory /path` points it elsewhere.

Colours, sizes, radii and springs of the island live in `Sources/NotchApp/IslandKit.swift`; they follow the "Notch Island v2" design.

The settings window is `Sources/NotchApp/SettingsWindow.swift`: an ordinary window with the tabs General, Interruptions, Connection and GitLab, after screen 6 of the same design; the menu bar item only shows the state and opens it. `-openSettings GitLab` opens it on a tab at launch, for a check by hand. The GitLab tab is the setup of the CI integration: it asks `glab auth status` for gitlab.com, the hosts the user named and those sessions pushed to (`GitHost.access`), and gives the commands that are still to be run. It opens by itself, once, the first time a GitLab cannot be asked about a push.

The companion, the small orange character at the left end of the band, is `Sources/NotchApp/Companion.swift`: drawn in a canvas and driven by the clock, with one mood for all sessions (waiting, then failed, working, finished, asleep). It is the one deliberate exception to the design's rule against motion while sessions simply work.

A permission request the user ignores goes back to Claude Code's own dialog after five minutes. `-requestTimeoutSeconds 20` shortens that for a check by hand.

Whether the island interrupts is decided in the session core (`Sources/SessionCore/Interruptions.swift`) from the mode, the window in front and Focus; the app only reports those and carries the decisions out. A Focus silences every mode unless "Respect Focus" is turned off. `-interruptionMode loud|smart|quiet` and `-interruptionSound Name` (empty for none) override the stored settings for one run. Focus is read from `~/Library/DoNotDisturb/DB/Assertions.json`, which macOS keeps from apps without Full Disk Access; without it no Focus is seen. Which Terminal tab is in front is asked of Terminal by Apple event, so it needs the same Automation grant as the jump.

Usage limits come from the status line of CLI sessions and, since desktop sessions run none, from the Claude desktop app's own `plan-usage-history.json` (read-only, undocumented format, no reset times). `-claudeDesktopUsageHistory /path` points it elsewhere.

The CI of what a session pushed is followed by the session core (the "Pipelines" part of `Sources/SessionCore/SessionCore.swift`, its types in `Pipelines.swift`): a push counts once a `PostToolUse` hook reports `git push`, `gh pr create` or `glab mr create`, and only then. The app reads the commit, branch and remote from the session's repository and asks the host through `gh` or `glab`: `Sources/SessionCore/GitHost.swift` reads their answers, `Sources/NotchApp/PipelinePoller.swift` runs them, on a 20-second timer in `AppModel`. It holds no tokens: a host the CLI is not signed in to shows as "no access", and the menu and the GitLab tab of the settings give the sign-in command. A host without "github" in its name is taken to be a GitLab.

A merge request a session pushed to is followed after that session has left the list (the "Merge requests" part of `SessionCore.swift`, `FollowedMergeRequest` in `Pipelines.swift`): the core says which to ask about and how often, `GitHost.mergeRequest` reads GitLab's answer, the same poller runs it, and the list shows them in a section under the sessions. They are kept in `merge-requests.json` in the support directory. Each shows its approvals, given and required, and when GitLab's own verdict (`detailed_merge_status`) is mergeable and somebody approved, the island says "ready to merge" in a line, once per time it becomes so. A closed one is dropped. A merged one stays in the section and is followed for the commit it was merged as: the pipeline of that commit on the target branch and the deployments GitLab recorded for it, by environment (asked for by time and picked by commit, since the list cannot be asked by commit). A pipeline held at a manual step is a state of its own (`CIState.held`), for a session's push as well. The island says so in a line when that pipeline or a deployment fails, or the pipeline is held. A merged one leaves a liveness threshold after the pipeline and every deployment ended, and a day after the merge in any case. GitLab only so far.

Releases are built by `scripts/release.sh` (archive, Sparkle update feed, installer, Homebrew cask from `packaging/`), signed with the self-signed certificate named in `NOTCH_SIGN_IDENTITY` so that macOS keeps granted permissions across updates; `README.md` has the steps. The app updates itself through Sparkle (`Sources/NotchApp/AppUpdater.swift`), the only dependency, and only when it was built with `scripts/sparkle-public-key` present, so a development build never does. Sparkle is signed without the hardened runtime on purpose: with it a framework that no Apple team signed would not load.

The landing page is `site/`, an Astro project of its own, published to GitHub Pages by `.github/workflows/site.yml`. Sections are components in `site/src/components`; what the demo shows (the steps of the scene, the mock sessions) is data in `site/src/lib/demo.ts`; what happens after the page loads is `site/src/scripts`. The island at its top is a replica of the app's and takes its colours, sizes and the companion's drawing from `IslandKit.swift` and `Companion.swift`; when those change, `site/src/styles/global.css`, `site/src/lib/marks.ts` and `site/src/scripts/companion.ts` follow by hand.

```bash
cd site
npm install
npm run dev      # http://localhost:4321/notch-orchestrator/
npm run check    # types
npm run build    # into site/dist
```

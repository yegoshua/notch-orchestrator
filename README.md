# Notch Orchestrator

A macOS app that lives in the MacBook notch and keeps an eye on your Claude Code sessions, in the terminal and in the Claude desktop app alike.

- **One list of every live session**, with a state you can trust: what the hooks say is checked against the session's process and transcript, and what cannot be confirmed shows as unknown.
- **Answer from the notch**: allow or deny a tool call, or pick an answer to the agent's question, without switching windows.
- **Jump to the session**: the exact Terminal tab, the session in the Claude desktop app, or the VS Code window.
- **CI of what a session pushed**: the pipeline's state and stage in the session's row, through your own `gh` and `glab` sign-in. The app holds no tokens.
- **Merge requests, after the session**: the merge request a session pushed to stays in the list with its approvals, says when it is ready to merge, and after the merge shows the pipeline and the environments it is deployed to. On GitLab for now.
- **Usage limits** of your account, 5-hour and weekly, as a ring beside the notch.
- **Interruptions that respect you**: loud, smart or quiet, and silent under a Focus.

No telemetry and no backend: nothing leaves your Mac except the questions `gh` and `glab` ask your git host.

Needs macOS 14 or later.

## Install

```sh
curl -fsSL https://github.com/yegoshua/notch-orchestrator/releases/latest/download/install.sh | sh
```

This downloads the latest release, puts the app into `/Applications` (or `~/Applications` where that folder is not yours to write) and starts it. Running it again replaces the app with the latest release.

The app is signed with the project's own certificate and is not notarized by Apple. macOS refuses such an app when a browser downloaded it, and accepts it when `curl` did, which is why the installer is the way in. On a centrally managed Mac the administrator's policy may forbid apps that are not notarized whichever way they arrive; there the app cannot be installed without their consent.

### Homebrew

```sh
brew install --cask yegoshua/tap/notch-orchestrator
```

Homebrew marks what it downloads the way a browser does, so the cask takes that mark off the app again. Homebrew is moving away from casks that are not notarized, so the installer above is the primary way.

### After installing

On first launch the app adds its hooks to `~/.claude/settings.json` (a backup of the file is kept) and wraps your status line so that usage limits reach it. Sessions started before that do not report to it until they are restarted.

macOS asks for two permissions when they are first needed:

- **Automation of Terminal**, to jump to a session's tab and to tell whether that tab is in front.
- **Full Disk Access**, optional, to see whether a Focus is on. Without it a Focus is not respected.

"Start at login" is in the settings, which the app's menu bar menu opens. The GitLab tab there walks through signing `glab` in, so the island can follow pipelines and merge requests.

## Update

The app looks for a newer release by itself, checks the download against the update key it was built with, and installs it. "Check for Updates…" in the menu does it at once. Releases are signed with the same certificate every time, so that macOS treats an update as the same app and keeps the permissions you granted.

## Uninstall

1. Choose **Remove…** on the Connection tab of the settings: it takes the hooks and the status line wrapper out of `~/.claude/settings.json`.
2. Quit the app and delete `Notch Orchestrator.app`.
3. Delete `~/Library/Application Support/notch-orchestrator` if you want its files gone too.

With Homebrew: do step 1, then `brew uninstall --cask notch-orchestrator` (`--zap` for step 3).

## Build from source

```sh
swift build                 # type-check and build everything
swift test                  # session core and connection installer tests
scripts/build-app.sh        # universal, ad-hoc signed bundle in .build/app/
```

`CLAUDE.md` describes the layout and how to run a development build without touching your real Claude Code settings.

The landing page lives in `site/`, an Astro project: `npm install` and `npm run dev` there.

## Release (maintainers)

Once per maintainer machine:

```sh
scripts/create-signing-certificate.sh              # the certificate every release is signed with
.build/artifacts/sparkle/Sparkle/bin/generate_keys # the update key; prints its public half
```

Put the public half of the update key into `scripts/sparkle-public-key` and commit it. The private halves of both stay in your login keychain: back them up, since a release signed with another certificate loses people's permissions, and one signed with another update key is refused by every installed copy.

Then, per release:

```sh
NOTCH_SIGN_IDENTITY="Notch Orchestrator Release" scripts/release.sh 0.1.0
```

It builds the archive, the update feed, the installer and the Homebrew cask into `.build/release/` and prints the `gh release create` command that publishes them.

## Acknowledgements

Self-update is [Sparkle](https://sparkle-project.org) (MIT). The idea of an island growing out of the notch owes much to [NotchDrop](https://github.com/Lakr233/NotchDrop), [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) and [Vibe Notch](https://github.com/farouqaldori/vibe-notch); the code here is written from scratch.

## License

MIT. See [LICENSE](LICENSE).

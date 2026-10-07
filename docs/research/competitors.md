# Competitors: who they are, what they offer, where we can differ

Read on 2026-10-07. Everything was read, nothing was installed, built or run.

Every statement below is tagged by how it was obtained:

- **[docs]** stated in the product's own README, website, pricing page, changelog or documentation (the vendor's claim, not verified by running the product).
- **[meta]** repository metadata from the GitHub API (`gh api repos/OWNER/REPO`, `gh release list`), read on 2026-10-07.
- **[issue]** stated in the product's issue tracker (reporter's claim, not verified by us). `+N` is the number of thumbs-up reactions, `cN` the number of comments, as of 2026-10-07.
- **[code]** read directly in a source or in-repo document at the commit given in the sources table.
- **[inferred]** our conclusion; not verified.

Web pages (not GitHub) were read through a fetch tool that summarises the page, so wording from websites is second-hand; prices and dates were taken from it as reported. Star counts are what the API returned and say nothing about how they were earned.

## 1. Summary

The field moved a lot since the Vibe Notch note was written. Vibe Notch itself has had no commit since 2026-04-20 **[meta]**. The active notch apps are now Coucou (MIT, 4,002 stars ten days after its first release), CodeIsland (MIT, 2,468), Open Island (GPL-3.0, 2,044), Notchi (GPL-3.0, 1,040) and the paid, closed-source Vibe Island ($19.99 once) **[meta][docs]**. All of them answer permission requests and questions from the notch, most support 13 to 30 agents, and three have an iPhone companion. The orchestrator group is dominated by full "agentic IDEs" (Orca 87,070 stars, cmux 27,804, Superset 14,968) and by Anthropic's own Desktop Code tab and `claude agents` view; Vibe Kanban announced its shutdown on 2026-04-10 and Crystal was renamed Nimbalyst **[meta][docs]**. Usage meters are a crowded commodity (CodexBar 22,286 stars, ccusage 18,907).

Strongest differentiation opportunities:

1. **State you can trust.** The most-upvoted bug in the largest agent terminal is "status indicators are flaky and unreliable" (cmux #1027, +42) and every notch app has open "stuck on Working" or "session not detected" reports (section 4.1). Our reconciled state with an explicit "unknown" answers the complaint the field shares.
2. **CI of what a session pushed, per session, GitHub and GitLab, no stored token.** No notch app does this. Coucou's GitHub pill is account-wide and needs a personal access token with `repo` scope **[code]**; the others have nothing. GitLab is a top request elsewhere (Vibe Kanban #1697, +26; Emdash #1096, c10).
3. **A result summary with local checks after a turn.** Competitors show the last reply or a live diff; none reports "what changed and did the checks pass" (section 4.3). This planned feature is open ground.
4. **Quiet by design.** Requests to stop pop-ups, bounces and wrong-time sounds recur (Vibe Notch PR #107, #18, #38; peon-ping #371), and several competitors have open reports of sustained 100 to 200 % CPU (Open Island #618, CodeIsland #357, CodexBar #3247/#3882/#4208). Only CodeIsland documents comparable suppression; none documents reading macOS Focus.
5. **One list for CLI and Desktop sessions is a real first-party gap, but no longer unique.** Anthropic's docs say Desktop and CLI "each keep their own session list" and that agent view shows only background sessions **[docs]**. Open Island, CodeIsland, Coucou and Vibe Island already show Desktop sessions (section 3), so this is table stakes among notch apps, not a differentiator.

## 2. Comparison tables

Legend: **yes**, **no** (the product's own material describes the area and does not offer this, or an open issue asks for it), **part** (see the product section), **?** (not found in what was read; not proven absent).

### 2.1 Notch, menu-bar and overlay apps

| Product | Agents beyond Claude | Answer permissions | Answer questions | Jump to session | Claude Desktop sessions | CI / PR status | Diff or result summary | Usage limits | Usage forecast | Launch sessions | Worktrees | Sounds | Remote / mobile |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **notch-orchestrator** (today) | no | yes | yes | yes (Terminal.app tab, VS Code window, Desktop session) | yes | yes (per session, gh and glab) | no (planned) | yes (5 h, weekly) | no | no (planned) | no | yes | no |
| Vibe Notch | no | yes | ? | part (terminal, tmux) | no | no | part (chat history) | no | no | no | no | yes | no |
| Coucou | yes (10+) | yes, incl. "Always" | yes | yes | yes | part (account-wide GitHub pill, token) | part (live diffs, weekly recap) | yes | ? | ? | no | yes | yes (iPhone) |
| CodeIsland | yes (30+) | yes, incl. always-allow | yes | yes | yes (Code tab; Cowork read-only) | no | part (last reply, recap) | yes | ? | no | part (shows branch and worktree) | yes | yes (iPhone, Watch, SSH, chat pushes) |
| Open Island | yes (13) | yes | yes | yes (15+ terminals and IDEs) | yes | no | no | yes | ? | no | no | yes | part (SSH; Watch in progress) |
| Vibe Island (paid) | yes (25 to 30) | yes | yes, plus plan review | yes (20 terminals and IDEs) | part (Chat and Cowork) | ? | ? | yes | ? | ? | ? | yes | part (SSH, Bark push) |
| Notchi | part (Codex) | no | no | ? | ? | no | no | yes | no | no | no | yes | no |
| MioIsland | part (Codex) | yes | ? | yes | part (issue #47) | ? | part ("output diff") | ? | ? | yes (launch presets, remote launch) | ? | yes | yes (iPhone) |
| AgentBro | yes | yes | yes, plus plan approval | ? | ? | ? | yes (file diff, task summary) | part (tokens, rate limit) | ? | ? | ? | yes | part (SSH, webhooks) |
| peon-ping | yes | no | no | no | no | no | no | no | no | no | no | yes | part (mobile push) |

### 2.2 Orchestrators and the first-party baseline

| Product | Agents beyond Claude | Answer permissions | Jump to session | CI / PR status | Diff review | Usage limits | Launch sessions | Worktrees | Notifications | Remote / mobile |
|---|---|---|---|---|---|---|---|---|---|---|
| Claude Desktop, Code tab | no | yes (in app) | n/a (own sessions only) | yes (CI bar, auto-fix, auto-merge) | yes | yes (usage ring) | yes | yes | yes (OS notification, phone push for Dispatch) | yes (cloud, SSH, Dispatch) |
| Claude Code CLI: agent view, Remote Control | no | yes (peek and reply; from phone) | n/a (attach) | part (PR or MR label coloured by check state) | no | part (`/usage`, status line fields) | yes | yes | yes (terminal channel, phone push) | yes |
| Conductor (closed) | yes (Codex, Cursor) | ? | n/a | yes | yes | ? | yes | yes (workspaces) | ? | yes (iOS, Pro) |
| Orca | yes (any CLI agent) | ? | n/a | yes (GitHub PRs in app) | yes (annotate) | yes | yes | yes | yes | yes (iOS, Android, SSH) |
| Superset | yes | ? | n/a | yes (via gh) | yes | ? | yes | yes | yes (chimes, dock badge) | yes (iPhone, Pro) |
| Emdash | yes | ? | n/a | yes (CI checks) | yes | ? | yes | yes | yes | part (SSH) |
| cmux | yes (any CLI agent) | no (terminal) | yes (notification panel) | part (PR status in sidebar) | no | ? | yes | ? | yes (rings, panel) | yes (SSH; iOS on Pro) |
| Nimbalyst (was Crystal) | yes | ? | n/a | ? | yes | ? | yes | yes | yes | yes (iOS) |
| claude-squad | yes | part (auto-yes only) | yes (attach) | no | yes (diff tab) | no | yes | yes | no | no |
| Vibe Kanban (sunsetting) | yes (10+) | ? | n/a | part (PR creation) | yes | ? | yes | yes | ? | part (self-host) |
| Happy | yes (Codex, Grok) | yes (from phone) | n/a | ? | ? | ? | yes | ? | yes (push) | yes (iOS, Android, web) |
| opcode (was Claudia) | no | ? | n/a | no | ? | part (usage dashboard) | yes | ? | ? | no |

### 2.3 Usage-limit trackers

| Product | Form | Providers | 5 h and weekly limits | Reset times | Forecast or pace | Alerts | Session status too |
|---|---|---|---|---|---|---|---|
| CodexBar | menu bar (macOS), Linux app, CLI | 25+ | yes | yes | ? | ? | no |
| ccusage | CLI | 18+ | part (5-hour blocks from local logs) | part | part (active block) | no | no |
| Claude Code Usage Monitor | terminal UI | Claude | yes (from status line `rate_limits`) | yes | yes | yes | no |
| ccstatusline | status line | Claude | yes | yes | no | no | no |
| Claude Usage Tracker | menu bar, status line, notch HUD (beta) | Claude, Codex | yes | yes | yes (6-tier pace) | yes | part (notch HUD) |
| ClaudeBar | menu bar | 27 | yes | yes | part (pace-aware colours) | yes | part (start/finish notifications) |
| Codenotch | screen-edge notch, phone app | Claude, Cursor, Codex, Antigravity, more | yes | yes | ? | yes (80 % and 100 %) | part (working / done / waiting) |

## 3. Products

### 3.1 Notch, menu-bar and overlay apps

#### Vibe Notch (formerly Claude Island)

- **What.** macOS notch overlay for Claude Code CLI sessions: session list, approve or deny, chat history, hooks auto-installed **[docs]**. Internals are covered in `vibe-notch.md`.
- **Price, license, platform.** Free, Apache-2.0, macOS 15.6+ **[docs][meta]**.
- **Activity.** 2,515 stars, 356 forks. Six releases in total; latest v1.3.2 on 2026-04-20, which is also the last commit. The README still says "Actively maintained" and describes a 4-month break before v1.3 **[meta][docs]**. **[inferred]** Stalled for the second time; 56 open issues and PRs.
- **Complaints and requests.** Hook as a plugin instead of editing `~/.claude` (#7, +4); UI too large, covers content (#41, +3); cursor moves (#32, +2); sounds when Claude needs action (#50, +2); menu-icon mode instead of island (#58, +2); OpenCode support (#6); "No session detected" (#11, c10); stuck on "Processing…" (#98); Claude Desktop support (#92) **[issue]**.
- **Lacks relative to us.** Desktop sessions, question answering (not in README), usage limits, CI, interruption modes, honest state. Ships Mixpanel analytics **[docs]**.

#### Coucou

- **What.** A notch companion ("Mochi") for macOS, with Tauri builds for Windows and Linux and a native iPhone app **[docs]**.
- **Features [docs].** Claude Code, Cursor, Codex, Gemini CLI, Antigravity, Copilot CLI, Muse Code, OpenCode, Amp, Hermes, plus any agent through a `--agent` flag. Permission cards with Allow / Deny / Always; `AskUserQuestion` with single or multi-select, up to four questions. Jump to the exact terminal window. Per-edit file name with +N −M and a readable diff. Claude plan usage pill (5-hour and weekly; "Pro and Max plans only"; GitHub build only) and a Codex pill. Chat with Claude, Gemini, OpenAI or local models using the user's own API key. File drop on the notch. Service pills: Stripe, n8n, GitHub (open PRs, reviews requested, CI status), Vercel, Resend, Notion, Cal.com. 28 sounds, wardrobe, desktop mode for the character. Keyboard shortcuts. Weekly recap. 10 languages. "No telemetry, no account". Hooks: backs up `settings.json`, merges, shows the diff before writing; "If Coucou isn't running, the hook exits immediately".
- **iPhone [docs].** Live Activity and Dynamic Island, Allow / Deny from the Lock Screen with Face ID, answer questions, send the next instruction by text or voice, widgets, Siri. Sync through the user's private CloudKit database; Live Activity pushes go through a stateless Cloudflare Worker that "only sees the agent's name and state". TestFlight beta.
- **Claude Desktop [code].** `docs/AGENTS.md`: sessions started from the Desktop Code tab carry `CLAUDE_CODE_ENTRYPOINT=claude-desktop`; the relay tags them as their own pill; a button opens the Claude app.
- **CI [code].** `docs/INTEGRATIONS.md`: the GitHub pill uses a classic token with `repo` scope, or a fine-grained token with read access to pull requests, commit statuses and Actions, stored in the Keychain, and queries the GitHub GraphQL API. **[inferred]** It is an account-wide feed, not tied to what a given session pushed; no GitLab was found in the README or docs.
- **Hook transport [code].** Unix socket in the app's support directory, directory 0700, socket 0600, same-user check with `getpeereid`; the hook gives up after 300 ms if the app does not answer.
- **Price, license, platform.** Free. Code MIT; name, character, sounds all rights reserved. macOS 15+ to build; App Store build announced, sandboxed, without plan usage **[docs]**.
- **Activity.** Repository created 2026-09-27; 4,002 stars, 668 forks; 13 macOS releases in ten days, latest v0.2.1 on 2026-10-07; top contributor has 117 commits, the `claude` account 15 **[meta]**.
- **Complaints and requests.** Linux version (#8, +12, shipped as beta since); more agents (#9, +3); WSL (#52, +2); voice (#116, +2); "Multi-session support: track multiple Claude Code terminals simultaneously" (#18); sessions launched from Ghostty are ignored (#239); VS Code hard-coded as editor (#51); custom `ANTHROPIC_BASE_URL` (#26) **[issue]**.
- **Lacks relative to us.** Per-session CI and GitLab; token-free CI; interruption modes based on Focus and the front window (not in README); reconciliation against process and transcript (not described). **[inferred]** It is the closest competitor in spirit (character, sounds, approvals, usage) and is ahead on agents, diffs, "Always", iPhone and distribution.

#### CodeIsland

- **What.** Notch status panel for "30+ AI coding tools", native Swift **[docs]**.
- **Features [docs].** Live status, current tool, latest reply rendered as Markdown; the agent's task checklist as a progress bar; Claude Code's "while you were away" recap; git branch and worktree on each card; Claude usage stats and opt-in plan limits (5-hour and weekly). Approve, deny or always-allow; multi-question prompts; one click to the exact terminal tab, IDE window, or tmux / zellij / Herdr pane; global shortcuts; auto-proceed for YOLO-mode agents. "Smart suppress: no ping while you're already looking at that session's tab"; quiet hours; per-event sounds; hides in full screen; silence rules per directory; mutes while the screen is locked; opt-in follow-up reminders. SSH remote hosts. iPhone and Apple Watch app (free on the App Store, local network and Bluetooth, "no account, no server"); ESP32 desk device; pushes to Bark, ntfy, DingTalk, Lark, WeCom, Slack, Telegram "only while you're away"; webhook forwarding. Several Claude config directories (multiple accounts). Signed, notarized, Sparkle, Homebrew tap.
- **Claude Desktop [docs].** Code tab covered through hooks. Cowork is read from `~/Library/Application Support/Claude/local-agent-mode-sessions/` read-only, because hooks do not fire in its sandbox.
- **Price, license, platform.** Free, MIT, macOS **[docs][meta]**.
- **Activity.** 2,468 stars; 35 releases since April 2026, latest v1.0.35 on 2026-09-24; only 12 open issues and PRs **[meta]**.
- **Complaints and requests.** Main thread at 100 % CPU in a layout loop (#357); hook install breaks Codex startup with a duplicate table (#354); Windows (#351); more tools (#355) **[issue]**. Open issues carry almost no reactions.
- **Lacks relative to us.** CI status (nothing in README; code search found nothing, see section 7); usage forecast; Focus (not mentioned; it has its own quiet hours); a result summary with checks.

#### Open Island (`open-vibe-island`)

- **What.** "An open-source Vibe Island": notch or top-bar control surface, native Swift package with four targets **[docs]**.
- **Features [docs].** 13 agents; jump-back for 15+ terminals and IDEs with per-terminal precision listed (TTY for Terminal.app, IDs for Ghostty and iTerm2, pane targeting for tmux, WezTerm, Zellij, Warp; workspace level for VS Code, Cursor, JetBrains); permission and question flows; usage dashboard; sounds; session discovery from local transcripts, persisted across launches; hooks "fail open"; Sparkle; signed and notarized; Homebrew cask; "No server, no telemetry, no account".
- **Claude Desktop [docs].** "Claude Desktop runs Claude Code as a TTY-less subprocess invisible to process discovery, so liveness follows the running desktop app"; jump-back activates Claude; the usage panel "is account-wide but seeded by the CLI status line". **[inferred]** Liveness of a Desktop session is therefore approximate, and jump goes to the app, not the session.
- **Price, license, platform.** Free, GPL-3.0, macOS 14+ **[docs][meta]**.
- **Activity.** 2,044 stars; 55 releases, latest v1.2.1 on 2026-09-15 (last commit the same day); 216 open issues and PRs **[meta]**.
- **Complaints and requests.** Focus the parent app instead of opening a new terminal (#173, +4); Copilot CLI (#308, +3); iTerm2 jump always goes to the first window (#379); wrong workspace in cmux (#607); click on a session does nothing (#314, #273); Claude conversations not persisted in the list (#125, c3); Codex Desktop stop leaves the session running (#403); sustained 150 to 206 % CPU (#618); clean uninstall (#497); iPhone disconnects on lock, Watch haptics fail (#505) **[issue]**.
- **Lacks relative to us.** CI, result summary, exact Desktop session jump, interruption modes.

#### Vibe Island (paid, closed source)

- **What.** The commercial product the open clones copy. Its GitHub repository holds only issues and discussions **[docs]**.
- **Features [docs].** 25 agents in the README, 30 on the website; approve or deny; answer questions; plan review with Markdown and feedback; "precise jump-back" to tab, split pane or IDE window across 20 terminals and IDEs; subscription usage per provider; SSH Remote; 8-bit sounds; "under 50 MB RAM"; "No cloud, no accounts, no telemetry"; Homebrew cask. Changelog: Claude Desktop Chat and Cowork on the island (v1.0.48, 2026-08-28); iPhone alerts through Bark with Watch mirroring and Codex Desktop approvals (v1.0.44); follow-up reminders (v1.0.49).
- **Price.** $19.99 one-time for one Mac, with two- and three-Mac options and a free trial **[docs]**. macOS 14+.
- **Activity.** Latest v1.0.51 on 2026-09-26; roughly two to three releases a month **[docs]**. Issue repository: 152 stars, 96 open.
- **Complaints and requests.** No notifications over SSH (#53, c7); the app takes over Claude's `statusLine` and output style in `settings.json` (#137, c7); stale Codex entries (#56); "Claude Desktop Chat stuck on Working" (#253); jump silently does nothing for sessions hosted by the background daemon (#166); multi-screen (#10); usage always visible without opening the panel (#26); reposition along the menu bar (#180); disable pixel art when idle (#213) **[issue]**.
- **Lacks relative to us.** CI, result summary (neither mentioned); source availability.

#### Notchi

- **What.** A notch companion that reacts to Claude Code and Codex events with sprites; a status toy more than a control surface **[docs]**.
- **Features [docs].** One sprite per session; prompt sentiment through the user's Anthropic or OpenAI key; session time and usage quota; daily cost and tokens for 30 days; sounds "auto-muted when terminal is focused"; Sparkle. No approving, no jump described.
- **Price, license, platform.** Free (sponsors), GPL-3.0, macOS 15+, notch required **[docs]**.
- **Activity.** 1,040 stars; 19 releases, latest v1.2.7 on 2026-09-19 **[meta]**.
- **Requests.** Remote servers (#33, +2); skins (#49, +2); external monitor (#24); only one sprite with several sessions (#9, c7) **[issue]**.

#### Others, briefly

- **MioIsland.** Fork of Claude Island with an iPhone app ("Code Light"), launch presets, remote launch, pixel cat; license CC BY-NC 4.0 (non-commercial); 540 stars; latest v3.1.3 on 2026-08-13 **[docs: README is images, facts taken from their alt text][code: `LICENSE.md`][meta]**. `TODOS.md` mentions redeem codes and a "paid path" **[code]**. Requests: no notifications when Claude Code runs over SSH (#77, +2), more CLIs (#29), macOS 13 (#31) **[issue]**.
- **AgentBro.** Tauri (Rust) island for macOS and Windows, Apache-2.0, 203 stars, latest v3.1.0 on 2026-08-03. Approvals, questions, plan approval, file diff, task summary, context pressure, tokens and rate limit, do-not-disturb hours, SSH, DingTalk and Lark webhooks, plus management of hooks, skills, MCP and API providers **[docs]**. Open bug: polling the front app every 250 ms through `osascript` deadlocks the App Store purchase sheet (#102) **[issue]**.
- **Atoll** (4,865 stars, GPL-3.0). A general Dynamic Island for macOS (media, calendar, shelf). No agent features in the README; requests for terminal permission prompts (#390, +4) and an "AI Agent Hub" (#539, +2) are open **[docs][issue]**. **[inferred]** General notch apps may add agent status; none of the ones read has.
- **peon-ping** (5,066 stars, MIT). Game-voice sounds and on-screen banners for Claude Code and many other agents through hooks; mobile push; no approving (#166 asks about a permission hook) **[docs][issue]**. Complaints: sound interrupts Spotify (#371), overlapping sounds (#340), cannot silence teammates separately from the lead (#481).
- **Claude Usage Tracker** has a "Dynamic Island (Beta)" notch HUD since v3.2.0; see 3.3.

### 3.2 Orchestrators

#### First-party baseline: Claude Desktop Code tab

All **[docs]**, `code.claude.com/docs/en/desktop.md`:

- Parallel sessions in a sidebar; optional git worktree per session, stored under `<project-root>/.claude/worktrees/`.
- Diff view and code review.
- "After you open a pull request, a CI status bar appears in the session. Claude Code uses the GitHub CLI to poll check results and surface failures", with optional auto-fix and auto-merge.
- "Click the usage ring next to the model picker to see your current context window usage and your plan usage for the period."
- "The desktop app sends an OS notification when a Code session finishes a task and you aren't currently viewing that session."
- Local, cloud, SSH and WSL sessions; scheduled tasks; Dispatch from the phone with a push "when it finishes or needs your approval".
- The gap we fill: Desktop and CLI "each keeps its own session list"; a session inside Desktop "doesn't see cloud sessions, or sessions you started from the terminal CLI or the VS Code extension". A CLI session can be moved into Desktop with `/desktop` or `claude --desktop` (v2.1.285+), which ends the CLI session.
- macOS, Windows, Linux (beta). Included in Claude subscriptions.

#### First-party baseline: Claude Code CLI

- **Agent view [docs].** `claude agents`: "one screen for all your background sessions: what's running, what needs your input, and what's done". States: working, needs input, idle, completed, failed, stopped. Peek panel to read the question and reply without attaching. Shows `#1234` for a pull request and `!1234` for a GitLab merge request, coloured by check and review state. Research preview, v2.1.212+. "Interactive sessions you have open in other terminals don't appear until you background them."
- **Remote Control [docs].** Continue a local session from claude.ai/code or the mobile apps; Pro, Max, Team, Enterprise; server mode with `--spawn worktree` and `--capacity` (default 32). Mobile push "when actions required" for permission prompts and questions. Push is skipped while the terminal is focused; presence elsewhere needs a user-maintained `CLAUDE_CLIENT_PRESENCE_FILE`.
- **Hooks [docs].** `PermissionRequest` hooks may return `allow` or `deny`, and on allow may add `addRules` "so the user won't be prompted again" (this is the mechanism for "always allow"). HTTP hooks are supported. `Notification` matchers include `permission_prompt`, `idle_prompt`, `agent_needs_input`, `agent_completed`. Default hook timeout 600 s.
- **Status line [docs].** `rate_limits.five_hour` and `rate_limits.seven_day` with `used_percentage` and `resets_at`; present "only for claude.ai Pro and Max subscribers" and only after the first API response.

**[inferred]** First-party already covers launching, worktrees, diff review, CI and remote approval inside its own surfaces. What it does not provide is one always-visible place across CLI terminals, Desktop sessions and background sessions.

#### Conductor (closed source)

- "Run parallel Claude Code, Codex, and Cursor agents in isolated workspaces on your Mac" **[docs]**. Changelog entries name a diff viewer, PR creation, PR checks, "View GitHub Actions in Conductor", "Forward Failing Checks to Claude", setup scripts, Linear **[docs]**.
- Price: Free ($0, local workspaces, own subscriptions); Pro $50/month (cloud workspaces, collaboration, API, mobile app); Teams $60/user/month; Enterprise **[docs]**.
- Activity: v0.90.0 "Conductor for iOS" on 2026-10-02; six releases in the preceding two weeks **[docs]**. macOS only.
- Lacks relative to us: it manages only sessions it starts. Open Island detects sessions running inside Conductor through `CONDUCTOR_SESSION_ID` **[docs: Open Island README]**, which shows the two categories coexist.

#### Orca

- "The ADE for working with a fleet of parallel agents." Parallel worktrees, terminal splits, GitHub and Linear in-app, SSH worktrees, diff annotation, account switcher with Claude and Codex usage and reset times, notifications and unread state, iOS and Android companion, CLI **[docs]**.
- Free, MIT, macOS, Windows, Linux **[docs][meta]**.
- 87,070 stars; created 2026-03-17; release v1.4.222 on 2026-10-07, roughly one every one to two days **[meta]**.
- Requests: Jujutsu workspaces (#1082, +43); multi-repo workspaces (#1099, +42); LSP (#961, +37); multiple windows (#6074, +28); headless mode (#4280, +20) **[issue]**.

#### Superset

- Agentic IDE: workspaces on worktrees, diff viewer, PR review with feedback to agents (uses `gh`), in-app browser, agent monitoring "with working indicators, completion chimes, and dock badges", automations, remote access, iPhone app **[docs]**.
- Elastic License 2.0 (source-available) **[code: LICENSE]**. Free plan local; Pro $20/user/month ($15 yearly) for remote access, automations, mobile, Linear and Slack **[docs]**. macOS primary, Linux experimental.
- 14,968 stars; desktop v1.36.0 on 2026-10-06 **[meta]**.
- Requests: Linux (#405, +16); Windows (#2692, +14); name the workspace and branch at creation (#7168 +13, #7318 +10, #6398 +7); "Drop the sign-in requirement; make it work offline" (#4894, +11); input lag from git subprocesses (#4198) **[issue]**.

#### Emdash

- Desktop app for parallel agents in worktrees; tickets from Linear, GitHub, Jira, GitLab and others; "Review diffs, create pull requests, inspect CI checks, and merge"; SSH projects; telemetry optional **[docs]**.
- Free, Apache-2.0, macOS, Windows, Linux; 5,928 stars; v1.2.7 on 2026-09-27 **[meta]**.
- Requests: "Diff mode to view changes since last turn" (#1635, +4); submodules (#1104, +4); GitLab integration (#1096, +3, c10); local merge without PR (#1269) **[issue]**.

#### cmux

- Ghostty-based macOS terminal with vertical tabs. "Panes get a blue ring and tabs light up when coding agents need your attention"; a notification panel with jump to the latest unread; the sidebar shows branch, "linked PR status/number", ports and the latest notification text; SSH workspaces; Claude Code teams as native splits **[docs]**.
- App GPL-3.0-or-later; server parts under BUSL-1.1 **[code: LICENSE]**. Free app; Pro $40 to $50/month for cloud VMs and iOS app; Max $200/month; Team $60/user/month **[docs]**.
- 27,804 stars; commits on 2026-10-07 **[meta]**.
- Complaints: Linux (#330, +166); Windows (#1012, +50); **"Sidebar 'Running' and 'Needs Input' status indicators are flaky and unreliable" (#1027, +42)**; "Claude notifications are flaky — inconsistent delay between task completion and notification delivery" (#2322, +22); Codex wrapper bypasses hook trust globally (#8136, +19) **[issue]**.

#### Nimbalyst (formerly Crystal)

- Crystal's repository description now reads "(Crystal is now Nimbalyst)"; its last release was v0.3.5 on 2026-02-26 **[meta]**.
- Nimbalyst: Electron-class workspace with visual editors, red/green diff review, parallel sessions in worktrees, session kanban, task trackers, iOS companion with push "when an agent is waiting". Anonymous PostHog analytics with opt-out **[docs]**.
- Free, MIT, macOS, Windows, Linux; 1,848 stars; v0.80.0 on 2026-10-05, several releases a week **[meta]**.
- Requests: remote SSH (#49, +11); Android app (#95, +11); WSL (#26, +8); "extremely token-greedy" (#889, +4, c13) **[issue]**.

#### claude-squad

- Terminal UI on tmux: several agents, each in its own git worktree; preview and diff tabs; commit and push; `--autoyes` to accept prompts **[docs]**. Requires tmux and gh.
- Free, AGPL-3.0; 8,576 stars; v1.0.20 on 2026-08-20, a release every one to three months **[meta]**.
- Requests: worktree setup hook (#260, +8); multiple repos (#56, +6); new session in another repo without relaunching (#299, +4) **[issue]**.
- Lacks: notifications, usage, CI, sessions it did not start.

#### Vibe Kanban

- README banner: "Vibe Kanban is sunsetting." The announcement (2026-04-10) says the company is closing, remote services end after 30 days, local workspaces keep working, and the project continues "open source and community maintained"; stated reason: "The vast majority are free users and we couldn't find a business model" **[docs]**.
- Apache-2.0; 28,277 stars; last release 2026-04-24, last commit 2026-09-19 **[meta]**.
- Requests: self-hosted GitLab (#1697, +26); keep the kanban board (#2509 +15, #2730 +15); automatic worktree cleanup (#765, +8) **[issue]**.

#### Happy and opcode

- **Happy** (MIT, 24,048 stars, CLI 1.2.5 on 2026-09-22): wraps Claude Code and Codex and continues the session on iOS, Android and web with end-to-end encryption; now also a desktop app and its own harness **[docs]**. Requests: OpenCode (#265, +53), Pi (#1213, +30), self-hosting broken (#246, +10) **[issue]**.
- **opcode**, formerly Claudia (AGPL-3.0, 22,419 stars): GUI for Claude Code sessions and custom agents. Two releases ever, the last v0.2.0 on 2025-08-31 **[meta]**. Requests: remote sessions over SSH (#163, +34), other agents (#66, +15) **[issue]**. **[inferred]** Effectively unmaintained as a product.

### 3.3 Usage-limit trackers

- **CodexBar** (MIT, 22,286 stars, v0.73.0 on 2026-10-07, a release every one to three days). Menu-bar limits for 25+ providers with reset countdowns, credits and spend, provider status. Claude source: "OAuth API, browser cookies, or CLI PTY fallback". macOS 14+, Linux app, CLI **[docs]**. Complaints: disappeared from the menu bar (#1711, +13); "OAuth credentials not found" after login (#3395, +5); sustained ~92 % CPU and 2.2 GB memory (#3247), 80 to 134 % CPU (#3882), two CLI processes at 46 GB and 29 GB (#1999) **[issue]**.
- **ccusage** (MIT per LICENSE, 18,907 stars, v20.0.26 on 2026-09-27). CLI reports from local logs for Claude Code and 17 other agents; 5-hour block report; beta status line **[docs]**. It reports tokens and cost, not the account's limit percentages. Few open issues (19).
- **Claude Code Usage Monitor** (MIT, 8,734 stars, v4.0.0 on 2026-06-27 after eleven months without a release). Terminal monitor combining local logs with the official status line `rate_limits`; "reset-aware pace" and forecasts; P90-based custom plan **[docs]**. Complaints: "monitor dosnt look accurate" (#212, +6); wrong cost after resume (#158, c11) **[issue]**.
- **ccstatusline** (MIT, 13,211 stars, v2.2.30 on 2026-09-17). Configurable status line with session and weekly usage widgets and reset timers; reads Keychain credentials for the usage API **[docs]**. Complaints: high CPU with several concurrent sessions (#397, +7); wrong worktree shown with several worktrees (#190, +4) **[issue]**.
- **Claude Usage Tracker** (MIT, 3,621 stars, v3.3.0 on 2026-08-29). Native menu-bar app: session, weekly and per-model limits, history charts, multi-profile, threshold notifications, 6-tier pace markers, status line integration, notch HUD (beta) "showing what Claude Code is doing in real time". Needs a claude.ai session key or browser sign-in; "minimal anonymous analytics (version-only heartbeat)" **[docs]**. Requests: external-browser auth (#227, +3); exclude weekends from weekly pace (#326); show active worktree (#286) **[issue]**.
- **ClaudeBar** (Apache-2.0, 1,527 stars, v0.5.9 on 2026-10-07, near-daily releases). Menu-bar quotas for 27 providers "with reset countdowns and a notification before you run out"; pace-aware colours; Claude Code started / finished notifications through session hooks **[docs]**. macOS 15+.
- **Codenotch** (MIT, 2,761 stars, created 2026-09-05, v1.22.0 on 2026-10-06, 21 releases in a month). A black notch pinned to a screen edge with one ring per provider and "whether it is still working, done, or waiting on you"; alerts at 80 % and 100 %; phone app over local Wi-Fi; Windows port **[docs]**. Its Claude source order is notable: first "Claude Desktop's own cached usage response", read from the Chromium HTTP cache under `~/Library/Application Support/Claude` (zstd-encoded body of `/api/organizations/<id>/usage`), then `claude "/usage"`, then the OAuth token in the Keychain **[docs]**. Requests: hide in Dock (#378, +2); stuck on "waiting for first reading" (#178) **[issue]**.

## 4. What nobody does well

### 4.1 Session state that can be trusted

- cmux #1027 (+42): status indicators "flaky and unreliable"; #2322 (+22): notification delay inconsistent **[issue]**.
- Vibe Notch #11 (c10) "No session detected"; #98 stuck on "Processing…" **[issue]**.
- Vibe Island #253 Claude Desktop Chat stuck on "Working"; #56 stale entries; #166 jump no-op for daemon-hosted sessions **[issue]**.
- Open Island #403 Codex Desktop stop leaves the session running; #125 conversations vanish from the list; Desktop liveness tied to the app running, by its own README **[issue][docs]**.
- Coucou #18 and #239: sessions in some terminals not tracked **[issue]**.
- **[inferred]** All of these are hook-only or hook-first designs. None documents an "unknown" state; they show the last hook's claim. Our reconciliation against process and transcript is the direct answer, and it is cheap to demonstrate.

### 4.2 CI tied to the session

- Among notch apps only Coucou shows CI, as an account-wide GitHub feed behind a `repo`-scope token **[code]**.
- Orchestrators and Claude Desktop show CI only for sessions they launched **[docs]**. Agent view shows a coloured PR / MR label only for background sessions **[docs]**.
- GitLab demand: Vibe Kanban #1697 (+26), Emdash #1096 (c10) **[issue]**.
- **[inferred]** "What this session pushed, on GitHub or GitLab, without handing over a token" is not offered by anyone for sessions the tool did not start.

### 4.3 Telling the user what a turn produced

- CodeIsland shows the latest reply and Claude's own recap; Coucou and AgentBro show diffs; Vibe Notch shows chat history **[docs]**.
- Emdash #1635 (+4) asks for "changes since last turn" **[issue]**.
- Nobody was found reporting local check results (tests, lint, build) next to the change summary.

### 4.4 Interrupting well

- Vibe Notch: PR #107 "Stop auto-opening and bouncing", #18 sound on context resume, #38 sound suppression by focus (see `vibe-notch.md`) **[issue]**.
- peon-ping #371 sound interrupts Spotify; #481 cannot silence teammates separately **[issue]**.
- Vibe Island #213 disable pixel art when idle; #192 disable the blinking cursor (c3) **[issue]**.
- First-party push suppression knows only whether the terminal is focused; anything more needs a user-written presence file **[docs]**.
- CodeIsland is the exception with tab-aware suppression, quiet hours, lock detection and per-directory silence **[docs]**. No product's material mentions macOS Focus.

### 4.5 Staying light and leaving settings alone

- CPU and memory: Open Island #618 (150 to 206 %), CodeIsland #357 (100 %), CodexBar #3247 / #3882 / #4208 / #1999, ccstatusline #397, AgentBro #102 (250 ms `osascript` polling) **[issue]**.
- Settings ownership: Vibe Island #137 (takes over `statusLine` and output style, c7); CodeIsland #354 (breaks Codex config); cmux #8136 (+19, bypasses hook trust); Vibe Notch #7 (+4, do not edit my `.claude`) and #85 **[issue]**; Open Island #497 asks how to uninstall cleanly.
- Telemetry: Vibe Notch (Mixpanel), Nimbalyst and Vibe Kanban (PostHog), Claude Usage Tracker (heartbeat), Emdash (optional) **[docs]**. Coucou, Open Island and Vibe Island state none.

### 4.6 Sessions on other machines

- The single most repeated request across groups: opcode #163 (+34), cmux #1664 (+38), Nimbalyst #49 (+11), Crystal #26 (+8), Vibe Island #53 (c7), MioIsland #77, Notchi #33 **[issue]**. CodeIsland, Vibe Island, AgentBro, Orca, Emdash and cmux ship SSH support; reports suggest it is fragile.

## 5. Where notch-orchestrator is behind

| Area | Who has it | Evidence |
|---|---|---|
| Distribution: signed and notarized build, Homebrew cask, self-update | CodeIsland, Open Island, Vibe Island, Notchi, Codenotch, ClaudeBar, CodexBar | **[docs]** each README. We have a build script and an ad-hoc signature. |
| Agents other than Claude Code (Codex first) | every notch competitor except Vibe Notch | **[docs]**; top request where missing: Happy #265 (+53), opcode #66 (+15), Open Island #308, Vibe Notch #6 **[issue]** |
| "Always allow" from the notch | Coucou, CodeIsland | **[docs]**; first-party mechanism exists (`addRules`) **[docs]** |
| Terminals for jump: iTerm2, Ghostty, Warp, WezTerm, kitty, tmux and zellij panes, JetBrains | Open Island, CodeIsland, Vibe Island, Coucou | **[docs]**. Our `SessionWhereabouts.swift` handles Terminal.app tabs, VS Code windows and Desktop sessions only **[code]**. Jump failures are a top complaint even where supported (Open Island #173, #379, #607). |
| Phone: approve away from the Mac | Coucou, CodeIsland, MioIsland; first-party Remote Control and Dispatch | **[docs]** |
| Sessions over SSH | CodeIsland, Vibe Island, AgentBro | **[docs]** |
| Diffs and plan review in the panel | Coucou (diff), AgentBro (diff, plan), Vibe Island (plan) | **[docs]** |
| Usage pace, forecast and alerts; several accounts | Claude Usage Tracker, ClaudeBar, Claude Code Usage Monitor, Codenotch (alerts), CodeIsland (accounts) | **[docs]**. No forecast in `UsageLimits.swift` or `LimitRing.swift` **[code]**. |
| Reset times for Desktop-only users | Codenotch (Desktop's cached usage response) | **[docs]**. Our `plan-usage-history.json` source has no reset times (CLAUDE.md). |
| Launching sessions | MioIsland (presets); all orchestrators; first-party | **[docs]** |
| Screens without a notch, display choice | Coucou, Open Island, CodeIsland | **[docs]**. Not checked in our code. |
| A license | all open competitors | Our repository has no LICENSE file **[code]**. |
| Localization, community, releases | Coucou (10 languages), CodeIsland (7) | **[docs]** |

The companion character and sounds are not a differentiator: Coucou, Notchi, CodeIsland, MioIsland and Vibe Island all ship a mascot, and Coucou's is far more elaborate **[docs]**.

## 6. Recommended priorities

In order. Each item names the evidence it rests on.

1. **Make it installable: signed and notarized build, Homebrew cask, self-update, a license.** Every active competitor has this (section 5). Without it none of the differentiators reach a user. Vibe Notch shows what a stalled cadence costs: forks and clones overtook it within months **[meta]**.
2. **Lead with trustworthy state, and prove it.** Section 4.1 is the field's most consistent complaint, with the highest-voted bug among them (cmux #1027, +42). Keep the "unknown" state visible, keep the fixture tests for the known failure sequences, and say so in the README.
3. **Result summary after a turn, including local checks.** Open ground (4.3). Reuse what exists: last message, changed files with counts, and check results; link to the session's CI row. Do not build a diff viewer; Desktop, Orca, Superset and Coucou have one.
4. **"Always allow" through `addRules`.** Parity with Coucou and CodeIsland, and the hook contract supports it directly **[docs]**. Show and allow removal of the rules written, since settings ownership is a sore point (4.5).
5. **Widen jump targets: iTerm2, Ghostty, tmux panes first.** Jump is a core promise and the commonest failure report in Open Island and Vibe Island. Coucou's #239 (Ghostty sessions ignored) shows the cost of skipping it.
6. **Usage: add pace and a threshold alert; get reset times for Desktop users.** Pace and alerts are standard in section 3.3. Codenotch documents a read-only source for Desktop's own usage response that carries reset data; evaluate it against our undocumented `plan-usage-history.json` (Chromium cache format is private and may change, by Codenotch's own note).
7. **Keep the per-session CI feature and state its properties plainly:** GitHub and GitLab, through `gh` and `glab`, no token stored. It is unique among notch apps (4.2).
8. **Launching sessions: thin, and delegate.** Start a session in a chosen repository by handing off to first-party entry points (`claude` in a terminal tab, `claude --desktop`, or a background session). First-party and every orchestrator already own worktrees and dispatch (section 3.2).
9. **Codex support, later and only Codex.** It is the one non-Claude agent requested everywhere. Design the session core so a second source is an adapter; do not chase the 25-agent lists.

### What not to build

- **A worktree, diff-review or PR-management workspace.** Orca (87k stars, MIT, free), Conductor, Superset, Emdash and Claude Desktop cover it, and Vibe Kanban closed because "we couldn't find a business model" there **[docs]**.
- **An iPhone app with its own relay.** Coucou and CodeIsland already ship one free; Remote Control and Dispatch are first-party and push permission prompts to the phone **[docs]**. A cheaper step, if wanted, is to surface that a session is Remote Control-enabled.
- **Thirty agents, Windows, Linux.** Breadth is where CodeIsland, Vibe Island and Coucou compete with daily releases.
- **Service pills (Stripe, Vercel, music), chat with models, file drop, wardrobe.** Coucou's territory; unrelated to orchestration.
- **A general usage meter for many providers, or scraping with browser cookies and session keys.** CodexBar and ClaudeBar do this with 25+ providers; their issue trackers show the auth and CPU cost (#3395, #3247).
- **Telemetry, or taking over `statusLine` without restoring it.** Both are recorded complaints (4.5) and "no telemetry" is already a claim the leaders make.
- **SSH remote sessions, for now.** Heavily requested (4.6) but fragile in every implementation read, and it conflicts with reconciling against a local process and transcript. Revisit after items 1 to 6.

## 7. Sources and what could not be verified

### Sources

All read on 2026-10-07. For repositories, the README, release list, license and issue list were read at the head commit given; issue rankings used `gh issue list --search "sort:reactions-+1-desc"` and `sort:comments-desc` on open issues.

| Product | Source | Commit or version read |
|---|---|---|
| Vibe Notch | https://github.com/farouqaldori/vibe-notch | `10f1d24` (2026-04-20), v1.3.2 |
| Coucou | https://github.com/Louis-CFM/coucou (`README.md`, `docs/AGENTS.md`, `docs/INTEGRATIONS.md`) | `89477b4` (2026-10-07), v0.2.1 |
| CodeIsland | https://github.com/wxtsky/CodeIsland | `b444ae2` (2026-09-24), v1.0.35 |
| Open Island | https://github.com/Octane0411/open-vibe-island | `b50f87a` (2026-09-15), v1.2.1 |
| Vibe Island | https://vibeisland.app , https://vibeisland.app/changelog/ , https://github.com/vibeislandapp/vibe-island (issues only) | v1.0.51 (2026-09-26) |
| Notchi | https://github.com/sk-ruban/notchi | `e6f8b8a` (2026-10-04), v1.2.7 |
| MioIsland | https://github.com/MioMioOS/MioIsland (`README.md`, `LICENSE.md`, `TODOS.md`) | `a76df90` (2026-08-14), v3.1.3 |
| AgentBro | https://github.com/shirenchuang/agentbro | `06fe149` (2026-08-03), v3.1.0 |
| Atoll | https://github.com/Ebullioscopic/Atoll | branch `dev`, pushed 2026-10-07 |
| peon-ping | https://github.com/PeonPing/peon-ping | `de4ada7` (2026-10-06), v2.37.0 |
| Claude Desktop Code tab | https://code.claude.com/docs/en/desktop.md | page as served 2026-10-07 |
| Claude Code agent view | https://code.claude.com/docs/en/agent-view.md | same |
| Claude Code Remote Control | https://code.claude.com/docs/en/remote-control.md | same |
| Claude Code hooks | https://code.claude.com/docs/en/hooks.md | same |
| Claude Code status line | https://code.claude.com/docs/en/statusline.md | same |
| Conductor | https://www.conductor.build , `/pricing`, `/changelog` | v0.90.0 (2026-10-02) |
| Orca | https://github.com/stablyai/orca , https://onorca.dev | `0f9f199` (2026-10-07), v1.4.222 |
| Superset | https://github.com/superset-sh/superset , https://superset.sh/pricing | `c9a3078` (2026-10-07), desktop v1.36.0 |
| Emdash | https://github.com/generalaction/emdash | `3a44063` (2026-10-07), v1.2.7 |
| cmux | https://github.com/manaflow-ai/cmux , https://cmux.com/pricing | `022f1cc` (2026-10-07) |
| Nimbalyst | https://github.com/nimbalyst/nimbalyst | `69c456d` (2026-10-07), v0.80.0 |
| Crystal | https://github.com/stravu/crystal | v0.3.5 (2026-02-26) |
| claude-squad | https://github.com/smtg-ai/claude-squad | `ce1ffb4` (2026-08-20), v1.0.20 |
| Vibe Kanban | https://github.com/BloopAI/vibe-kanban , https://www.vibekanban.com/blog/shutdown | `d5cbb53` (2026-09-19) |
| Happy | https://github.com/slopus/happy | `18ae87e` (2026-10-07), cli-1.2.5 |
| opcode | https://github.com/winfunc/opcode | `d1ca30a` (2026-09-18), v0.2.0 |
| CodexBar | https://github.com/steipete/CodexBar | `36bf01a` (2026-10-07), v0.73.0 |
| ccusage | https://github.com/ccusage/ccusage | `35e9822` (2026-10-07), v20.0.26 |
| Claude Code Usage Monitor | https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor | `c59a83b` (2026-06-27), v4.0.0 |
| ccstatusline | https://github.com/sirmalloc/ccstatusline | `3b60234` (2026-10-06), v2.2.30 |
| Claude Usage Tracker | https://github.com/hamed-elfayome/Claude-Usage-Tracker | `588775e` (2026-08-31), v3.3.0 |
| ClaudeBar | https://github.com/tddworks/ClaudeBar | `c3eb332` (2026-10-07), v0.5.9 |
| Codenotch | https://github.com/vinzdg/codenotch | `bcb2889` (2026-10-06), v1.22.0 |
| notch-orchestrator (own) | `CLAUDE.md`, `Sources/NotchApp/SessionWhereabouts.swift`, `Sources/SessionCore/UsageLimits.swift`, `Sources/NotchApp/LimitRing.swift` | working tree, 2026-10-07 |

Names found only through search results (a web search and GitHub repository search), used for discovery and not as evidence: the long tail of small notch and menu-bar projects (for example `agent-isle`, `Buddi`, `Notch-Pilot`, `notch-agent-hud`, `claudecodeusage`, `Lucarne`, `AgentHub`). None was read; all had under 500 stars on 2026-10-07.

### Could not be verified

- **Anything about behaviour.** No product was installed or run. Feature rows are vendor claims; bug rows are reporter claims.
- **"No" and "?" cells.** A "no" means the README or docs describe the area without the feature, or an open issue requests it. A "?" means it was not found. GitHub code search for CI and Focus handling in Coucou, CodeIsland and Open Island returned nothing, but the same search also returned nothing for Coucou's CI feature that its own docs describe, so the index is incomplete and absence of CI or Focus handling in CodeIsland and Open Island is not proven.
- **Closed-source products.** Conductor and Vibe Island internals; whether Conductor has usage display, notifications or permission cards; whether Vibe Island shows Desktop Code-tab sessions (the changelog names Chat and Cowork only).
- **Web pages.** Website content came through a summarising fetch tool. Prices (Vibe Island $19.99; Conductor $50 and $60; Superset $20 and $15; cmux $40 to $200), changelog dates and the Vibe Kanban quotes are as that tool reported them and were not cross-checked against a second reading. `onorca.dev/pricing` returned 404; "free" is from the home page.
- **MioIsland.** Its README is six images; facts come from the images' alt text, `LICENSE.md` and `TODOS.md`. What its paid path covers was not established.
- **Star counts and growth.** Orca's 87,070 stars in under seven months and Coucou's 4,002 in ten days are API values; whether they reflect real use was not assessed. No download or active-user numbers were found for any product.
- **Discussions, Discord and chat groups.** Only issue trackers were read. Vibe Kanban and Vibe Island direct feature requests to Discussions, which were not ranked.
- **Vibe Notch question answering, Notchi jump and Desktop support, Open Island's iPhone and Watch status.** Not stated in the READMEs read.
- **Coucou's App Store and TestFlight availability, CodeIsland's App Store listing.** Links exist in the READMEs; the listings were not opened.
- **Whether Coucou can start a new session from the iPhone or Siri**, or only send an instruction to a running one. The README wording allows both.
- **Our own gaps for non-notch screens and localization** were not checked in our code.

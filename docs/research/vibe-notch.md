# Vibe Notch: what to reuse and what to avoid

Research for spec #1 ("Implementation Decisions") and ticket #4. Read on 2026-10-07.

Every statement below is tagged by how it was obtained:

- **[code]** read directly in the source at the pinned commit.
- **[issue]** stated in the upstream issue tracker or a pull request (reporter's claim, not verified by us).
- **[inferred]** our conclusion from the code; not verified by running anything. The upstream app was not built or run.

## Source

| | |
|---|---|
| Repository | https://github.com/farouqaldori/vibe-notch (not redirected; `full_name` is still `farouqaldori/vibe-notch`). Formerly "Claude Island"; the Xcode project, targets, bundle id and all source paths are still `ClaudeIsland`. |
| Commit read | `10f1d240e2b4965c2e3c82a3a916458d0541b2be` (2026-04-20, `main`, 67 commits, latest tag `v1.3.2`) |
| License | Apache-2.0 (`LICENSE.md`; appendix reads "Copyright 2025 Farouq Aldori") |
| NOTICE file | None. No `NOTICE`, no `THIRD_PARTY_LICENSES`, no acknowledgements in `README.md`. |
| Per-file headers | Only Xcode-style `// File.swift // ClaudeIsland // <description>` comments. No copyright or license header in any source file. |
| Deployment target | macOS 15.6 (`ClaudeIsland.xcodeproj/project.pbxproj:212,270`). We target 14. |
| Dependencies | Swift packages: Sparkle, swift-markdown, mixpanel-swift (`project.pbxproj:374-393`). Nothing is vendored as source. |

All line numbers below refer to that commit, under `ClaudeIsland/`.

## License and attribution

### What Apache 2.0 section 4 requires of us

If we copy or adapt upstream files and distribute the result (source or binary):

1. **4(a)** Ship a copy of the Apache License 2.0 text with the app and in the repo.
2. **4(b)** Every file we took and modified must carry a prominent notice that we changed it.
3. **4(c)** Keep all copyright, patent, trademark and attribution notices from the upstream source. Upstream files carry none, so the only notice to preserve is the copyright line from the license appendix: "Copyright 2025 Farouq Aldori".
4. **4(d)** Carry the upstream NOTICE content. Upstream has no NOTICE file, so nothing is required here. Writing our own NOTICE is still the cleanest place to put attribution.

Section 6 gives no right to the names "Vibe Notch" or "Claude Island" beyond describing origin.

### Provenance problem: the repo is not purely Apache-2.0 material

This is the most important finding of the research. The overlay and animation code, which is exactly what the spec proposes to reuse, is itself derived from three other projects, and upstream credits none of them in a license file.

| Upstream part | Derived from | That project's license | Evidence |
|---|---|---|---|
| Window, screen extension, event monitors, view model skeleton | [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) (read at `e70b3d7`) | MIT, "Copyright (c) 2024 Lakr Aream" | **[code]** `UI/Window/NotchWindow.swift:6` says "Following NotchDrop's approach". Same file names (`NotchWindow`, `NotchWindowController`, `NotchViewController`, `NotchViewModel`, `EventMonitor`, `EventMonitors`, `Ext+NSScreen`), same `collectionBehavior` set in the same order, same `notchSize` algorithm, same `Status { closed, opened, popping }` and `OpenReason` enums, same `mouseLocation` / `mouseDown` Combine subjects. The files are rewritten rather than copied verbatim. |
| `UI/Components/NotchShape.swift` | [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (read at `cd0b3e5`), via boring.notch | MIT, "Copyright (c) 2025 Kai Azim" | **[code]** The path-building body is the same code as `Sources/DynamicNotchKit/Views/NotchShape.swift`, with comments added. The 6 / 14 default radii come from boring.notch's copy, whose header reads "Original source: DynamicNotchKit". |
| Open/close springs, corner radius table, "expanding activity" coordinator, the `+ 4` notch width correction | [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) (read at `e2654ee`) | **GPL-3.0** | **[code]** `Core/Ext+NSScreen.swift:28` says "+4 to match boring.notch's calculation". `UI/Views/NotchView.swift:13-16` has the same `cornerRadiusInsets` table as `boringNotch/sizing/matters.swift:18`. `NotchView.swift:131-132` has the same two springs, with the same names, as `boringNotch/ContentView.swift:123-124`. `Core/NotchActivityCoordinator.swift:22-48` mirrors `ExpandedItem` and `expandingView` in `boringNotch/BoringViewCoordinator.swift:42-47,280-292`. |

**[inferred]** Consequences:

- Code that traces to NotchDrop or DynamicNotchKit is MIT. Reusing it obliges us to keep those copyright lines and the MIT permission text, which upstream does not do. Taking it "under Apache 2.0 from Vibe Notch" would repeat their omission.
- Code that traces to boring.notch is GPL-3.0. An Apache-2.0 label on Vibe Notch cannot relicense it. Individual numbers (spring parameters, radii, `+ 4`) are very unlikely to be protected expression, but the animation modifier block and the coordinator are structural copies. We should not copy those parts as code. This is an engineering reading, not legal advice.
- The safe scope for literal reuse is small. The practical position: **reuse techniques, write the files ourselves, and credit all three sources.**

## 1. Overlay window

**[code]** `UI/Window/NotchWindow.swift`, class `NotchPanel: NSPanel` (lines 13-121).

- Style mask is forced in `init`, ignoring the argument: `[.borderless, .nonactivatingPanel]` (line 22).
- Level and collection behaviour (lines 42-50):

  ```swift
  collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
  level = .mainMenu + 3
  ```

- Other flags (lines 28-61): `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `isMovable = false` (commented as required so the window does not move during space switches), `ignoresMouseEvents = true`, `acceptsMouseMovedEvents = false`, `isReleasedWhenClosed = true`.
- `canBecomeKey` is `true`, `canBecomeMain` is `false` (lines 64-65).
- The app is an agent: `LSUIElement` in `Info.plist:15` and `setActivationPolicy(.accessory)` in `App/AppDelegate.swift:71`. There is no real SwiftUI scene, only an empty `Settings` scene (`App/ClaudeIslandApp.swift:14-19`).

**Click-through, three layers. [code]**

1. Window level. `UI/Window/NotchWindowController.swift:67-84` subscribes to `viewModel.$status`: `ignoresMouseEvents = true` while closed or popping, `false` while opened.
2. View level. `PassThroughHostingView` (`UI/Window/NotchViewController.swift:13-23`) overrides `hitTest` and returns `nil` outside a rectangle computed by a closure (lines 42-76): the opened panel rect, or the notch rect padded by 10 pt horizontally and 5 pt vertically.
3. Event level. `NotchPanel.sendEvent` (`NotchWindow.swift:69-93`) catches mouse down/up events whose hit test is `nil`, sets `ignoresMouseEvents = true`, and re-posts a synthetic `CGEvent` at `.cghidEventTap` (lines 95-120). `NotchViewModel.repostClickAt` (`Core/NotchViewModel.swift:209-236`) does the same for a click outside the opened panel.

Because the window ignores the mouse while closed, hover and click on the closed notch come from global monitors, not from the view: `Events/EventMonitor.swift:25-36` installs a global plus a local `NSEvent` monitor, and `Events/EventMonitors.swift:25-39` publishes `mouseMoved`, `leftMouseDown` and `leftMouseDragged`.

**Focus. [code]** The panel is non-activating, but `NotchWindowController.swift:75-78` calls `NSApp.activate(ignoringOtherApps: false)` and `makeKey()` on every open except when `openReason == .notification`. So hover-open and click-open take keyboard focus.

**SwiftUI hosting. [code]** `NotchViewController.loadView` (lines 38-79) sets the controller's view to `PassThroughHostingView(rootView: NotchView(viewModel:))`, and the controller becomes the panel's `contentViewController` (`NotchWindowController.swift:59-60`).

**[inferred]**

- The SwiftUI `.onHover` and `.onTapGesture` in `NotchView.swift:176-185` cannot fire while closed, since the window ignores mouse events. They are leftovers.
- Synthetic `CGEvent` posting needs the Accessibility permission. The menu has a row for it (`UI/Views/NotchMenuView.swift:83`).
- Both re-post paths flip the Y coordinate using `NSScreen.main.frame.height` (`NotchWindow.swift:97-99`, `NotchViewModel.swift:212-214`). `NSScreen.main` is the screen with the key window, not the primary screen that defines the global origin, so on stacked displays the click lands at the wrong place and the cursor jumps. This matches issue #32 ("cursor occasionally moves when window retracts", one commenter: "when the notch is on a monitor that's below another").

## 2. Notch geometry

**[code]** `Core/Ext+NSScreen.swift`.

- `notchSize` (lines 12-31): height is `safeAreaInsets.top`; width is `frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width + 4`.
- `hasPhysicalNotch` (lines 50-52) is `safeAreaInsets.top > 0`.
- `isBuiltinDisplay` (lines 34-39) uses `CGDisplayIsBuiltin` on the `NSScreenNumber`.
- Hard-coded fallbacks: `224 x 38` when there is no notch (line 15), `180 x safeAreaInsets.top` when the auxiliary areas are missing (line 25).

**[code]** `UI/Window/NotchWindowController.swift:20-46` turns that into a window-local `deviceNotchRect`, centred horizontally. `Core/NotchGeometry.swift` is a small `Sendable` value type that converts to screen coordinates and answers hit tests (`notchScreenRect` 18-25, `openedScreenRect(for:)` 28-38, `isPointInNotch` 41-43).

**Screens without a notch. [code]** There is no separate design. The same black shape is drawn at the fake 224 x 38 size and kept permanently visible (`NotchView.swift:193-196`, guards at 396 and 416). On a real notch the view fades to opacity 0 when there is nothing to show (`NotchView.swift:188`, `handleProcessingChange` 381-404).

**Shape. [code]** `UI/Components/NotchShape.swift:10-115`: a SwiftUI `Shape` with `topCornerRadius` and `bottomCornerRadius`, animatable through `AnimatablePair`. The path is four quadratic curves: the top corners flare outward into the screen edge, the bottom corners are ordinary rounded corners. Radii are 6 / 14 closed and 19 / 24 opened (`NotchView.swift:13-16`). The content is black, clipped with the shape, plus a 1 pt black strip along the top to hide the seam (`NotchView.swift:152-159`).

**[inferred]**

- `openedScreenRect` subtracts magic numbers ("tuned to match visual output", `NotchGeometry.swift:29-31`), while the hit-test closure in `NotchViewController.swift:55` adds 52. Two hand-tuned approximations of one rectangle; upstream needed PRs #15 and #16 and issue #67 to align them.
- The quadratic curves are not the continuous-curvature corner of the hardware notch. Our design brief asks for a continuous curve.
- Collapsed content sits right against the notch edge. Issue #79 reported icons clipped by the camera housing; the fix was 4 pt of trailing padding (`NotchView.swift:287`).

## 3. Expand and collapse animation

**State. [code]** `Core/NotchViewModel.swift`.

- `status: NotchStatus` with `closed`, `opened`, `popping` (lines 12-16, 44). `popping` is dead: `notchPop` and `notchUnpop` (269-277) are never called.
- `openReason`: `click`, `hover`, `notification`, `boot`, `unknown` (18-24).
- `contentType`: `instances`, `menu`, `chat` (26-38). `openedSize` depends on it (66-92): 480 x 320 for the list, up to 600 x 580 for chat.
- A second, independent axis lives in `Core/NotchActivityCoordinator.swift`: `expandingActivity` widens the closed notch sideways while something is happening.

**Window versus content. [code]** The window never resizes. It is created once at full screen width and 750 pt tall, pinned to the top (`NotchWindowController.swift:23-30`). Only the SwiftUI content animates inside it; the hit-test rectangle is recomputed from `status` on each event.

**Animations. [code]** `UI/Views/NotchView.swift`.

- Open: `.spring(response: 0.42, dampingFraction: 0.8)`. Close: `.spring(response: 0.45, dampingFraction: 1.0)` (131-132), selected by `status` (169). The open spring also drives size changes between content types (170).
- Sideways activity changes: `.smooth` (171-173).
- Bounce on "finished": `.spring(response: 0.3, dampingFraction: 0.5)`, toggling a 16 pt width bump for 0.15 s (174, 278, 475-481).
- Content insertion: scale 0.8 from the top combined with opacity, `.smooth(duration: 0.35)`; removal: opacity, `.easeOut(duration: 0.15)` (232-239).
- Corner radii animate because `NotchShape` is animatable.
- `matchedGeometryEffect` moves the icon and spinner between the closed and opened headers (253, 258, 285, 291, 313).

**Triggers and timing. [code]**

- Mouse position is throttled to 50 ms (`NotchViewModel.swift:135-137`).
- Hover inside the padded notch rect for 1.0 s opens (159-184).
- A click on the notch opens (201-204).
- Close happens only on a click outside the panel, or on the notch itself when not in chat (188-199). **There is no close on mouse exit.**
- A new session needing attention opens the panel with `reason: .notification` if no terminal window is on the current space (`NotchView.swift:425-436`). Nothing closes it afterwards.
- Boot animation: open 0.3 s after launch, close 1.0 s later (`NotchWindowController.swift:90-94`, `NotchViewModel.swift:298-305`).
- Fade-out after close is delayed 0.35 s to 0.5 s (`NotchView.swift:397, 417`).

**[inferred]**

- A fixed oversized window is the right call: no window-frame animation, no desync between AppKit and SwiftUI. The cost is that correct click-through becomes mandatory, and upstream gets it only approximately right (section 1).
- While opened, the window covers the full screen width and 750 pt of height with `ignoresMouseEvents = false`. Every click in that band outside the panel depends on the synthetic re-post.

## 4. Multi-display behaviour

**[code]**

- One window on one screen. `App/WindowManager.swift:20-53` holds a single `NotchWindowController`.
- Choice of screen: `Core/ScreenSelector.swift:112-126`. Automatic means built-in display, else `NSScreen.main`. A specific screen is persisted as display id plus localized name (19-45) and falls back to automatic when missing.
- Configuration changes: `App/ScreenObserver.swift:28-50` listens to `NSApplication.didChangeScreenParametersNotification` with a 0.5 s debounce, then `AppDelegate.handleScreenChange` (`App/AppDelegate.swift:90-92`) calls `setupNotchWindow()`.
- `setupNotchWindow` skips the rebuild if `screen.frame` is unchanged (`WindowManager.swift:30-36`). Otherwise it closes the old window and builds a new controller, without the boot animation (38-50).
- The screen picker forces a rebuild by posting the same notification (`UI/Components/ScreenPickerRow.swift:125`).
- No handling of space changes, sleep/wake, or fullscreen beyond the `collectionBehavior` flags. A search for `activeSpaceDidChange`, `didWakeNotification` and fullscreen detection finds nothing.

**[issue]** #22 (closed): the window expanded and retracted several times on wake. Fixed by exactly the three measures above (debounce, no boot animation on rebuild, skip when unchanged; PR #23).

**[inferred]**

- Rebuilding the controller rebuilds `NotchViewModel` and `NotchView`. `NotchView` owns `ClaudeSessionMonitor` as a `@StateObject` and starts the hook server from `.onAppear` (`NotchView.swift:20, 192`). So UI state (opened or closed, timers for the "finished" checkmark) is lost on every display change, and session monitoring is coupled to a view's lifetime.
- The frame-equality shortcut does not detect a change of notch size at the same frame (for example a scaled resolution change that keeps the point size), nor a different screen that happens to have the same frame.
- Clamshell: the built-in screen disappears, automatic mode falls back to `NSScreen.main`, and the fake 224 x 38 notch is drawn permanently on the external display. Issues #41, #58 and #100 complain about exactly this overlay on external monitors; #19 asks for main-display priority.
- Fullscreen: `.fullScreenAuxiliary` plus `.canJoinAllSpaces` at a level above the menu bar keeps the overlay on top of fullscreen apps. On the notched display that is harmless (the band beside the notch is black). On a non-notched display the always-visible shape covers fullscreen content.
- `NSScreen.main` is the key-window screen, so "automatic" without a built-in display can move between displays depending on where focus was at the last rebuild.

## 5. Events, session state, permissions: weaknesses only

**How it works. [code]**

- `Services/Hooks/HookInstaller.swift:13-97` copies `Resources/claude-island-state.py` into `~/.claude/hooks/` and rewrites the user `settings.json`, registering a `python3 <script>` command hook for each event (177-214). `PermissionRequest` gets a hook timeout of 86400 s (line 44).
- The script (`Resources/claude-island-state.py`) maps each hook event to a `status` string (98-226), spawns `ps` to find the TTY (16-49), and writes JSON to the Unix socket `/tmp/claude-island.sock` (12, 52-71). For `PermissionRequest` it blocks on `recv` for up to 300 s and prints the allow or deny decision (139-179).
- `Services/Hooks/HookSocketServer.swift` accepts connections (GCD read source, 188), reads for up to 0.5 s (370-399), and for permission events keeps the client socket open in `pendingPermissions` keyed by `tool_use_id` (448-464). `PermissionRequest` carries no `tool_use_id`, so it is recovered from a cache filled on `PreToolUse`, keyed by session, tool name and input (293-343).
- `Services/State/SessionStore.swift` is an actor. `processHookEvent` (124-176) applies `HookEvent.determinePhase()` (`Models/SessionEvent.swift:131-163`) if `SessionPhase.canTransition` allows it (`Models/SessionPhase.swift:88-146`). Phases: `idle`, `processing`, `waitingForInput`, `waitingForApproval`, `compacting`, `ended`.
- A 3 s timer removes sessions whose pid fails `kill(pid, 0)` (1050-1115). JSONL transcripts are parsed for chat content and to detect interrupts (`Services/Session/ConversationParser.swift`, `JSONLInterruptWatcher.swift`).

**Known weaknesses, mapped to the spec's list.**

| Symptom | Cause | Evidence |
|---|---|---|
| Stuck on "Processing…" | `PostToolUse` always maps to `processing` (`claude-island-state.py:112-119`) and `waitingForInput → processing` is a legal transition (`SessionPhase.swift:117-118`). A `PostToolUse` for a background Bash command arrives after `Stop` and flips the session back. Only the next hook, an interrupt found in the transcript, or process death leaves `processing`; there is no reconciliation against the turn having ended. | **[code]**, **[issue]** #98 (open, log with `Stop` 1.1 s before `PostToolUse`), PRs #99 and #109 (unmerged). Earlier: #29. |
| Stuck after compaction or subagents | `PostCompact`, `SubagentStart` and `SubagentStop` also force `processing` (`claude-island-state.py:202-223`). A manual `/compact` on an idle session ends in `processing` with no `Stop` to follow. | **[code]** for the mapping; the stuck outcome is **[inferred]**. |
| Sessions not detected | Detection is hook-only: a session exists only after a hook reaches the socket. Failure points: `python3` resolved through `which` in the app's environment (`HookInstaller.swift:283-300`), a `ps` subprocess per event, a fixed socket path in `/tmp`, silent `except` in the script (70-71), and `settings.json` rewritten with `try?` and no error surfaced (91-96). Sessions already running when the app starts stay invisible until their next event. | **[code]**; **[issue]** #11 (open, 10 comments, several terminals), #47 (crash without `gettext`), PR #104 (hook crash in `subprocess`), #27/PR #28 (archived session never returns). |
| Settings damage | No backup, whole-file rewrite with sorted keys, existing malformed JSON silently replaced by `{}` plus hooks (`HookInstaller.swift:35-39`). Unknown hook keys made Claude Code skip the entire settings file. | **[code]**; **[issue]** #85 (closed, fixed by version gating at 169-214). |
| Sounds at the wrong time | Sound and bounce fire on every transition into `waitingForInput` (`NotchView.swift:438-491`), which is driven by `Stop`, `StopFailure` and `SessionStart` alike (`claude-island-state.py:193-212`). A `SessionStart` on a fresh session is rejected by the phase machine (`idle → waitingForInput` is not listed), but one arriving while `processing` or `compacting` is accepted; that it fires on resume and compaction is **[inferred]** and matches #18. Suppression needs the terminal app to be frontmost, by a hard-coded name list (`Utilities/TerminalVisibilityDetector.swift:46-67`). | **[code]**; **[issue]** #36 (closed: sound on every subagent completion), #18 (open: sound on context resume), #38, #24. |
| Island pops open on activity | Auto-open on any new "needs attention" session, which includes `waitingForInput`, not only permission requests (`NotchView.swift:425-436`, `SessionPhase.swift:154-161`). The gate is "is any terminal window on this space", not "is this session in front". Opened panels never close by themselves. Plus the sideways expansion on every `processing` phase and a bounce on every finish. | **[code]**; **[issue]** PR #107 (open, "Stop auto-opening and bouncing"), #22, #32. |
| Focus stealing | `NSApp.activate` and `makeKey` on hover-open and click-open (`NotchWindowController.swift:75-78`). | **[code]**; **[issue]** PR #10 (merged, notification case only), PR #105 (open). |
| Permission path can be hijacked | Socket at a fixed path in `/tmp` with `chmod 0600` and no token or peer check (`HookSocketServer.swift:110, 143-177`). Any process of the same user can inject events or connect as a fake hook. | **[code]**; **[issue]** PR #48 (open since early 2026, "Harden socket security"). Conflicts with our story 59. |
| Permission matching is heuristic | `tool_use_id` recovered from a `PreToolUse` cache keyed by tool name and input; identical parallel calls are FIFO-guessed, and a cache miss drops the request (`HookSocketServer.swift:293-343, 425-434`). | **[code]** |
| Timeouts disagree | Hook timeout 86400 s in settings, 300 s in the script, 0.5 s read window in the server. After 300 s the script exits silently and Claude Code shows its own prompt while the app still shows a pending request. | **[code]** for the numbers; the stale-request outcome is **[inferred]**. |
| Telemetry | Mixpanel with a machine-derived id (`IOPlatformUUID`) on launch and per session (`AppDelegate.swift:44-68, 100-126`, `SessionStore.swift:130-132`). Conflicts with our story 58. | **[code]** |
| No desktop app support | Session focus, liveness and messaging all assume a TTY, a pid and a terminal or tmux (`Services/Tmux/`, `Services/Window/`, `ProcessTreeBuilder`). | **[code]**; **[issue]** #92, #9, #102. |

## What to carry over

Carry over techniques, written as our own code. None of these need a file copied.

| Technique | Where upstream | Notes for us |
|---|---|---|
| Borderless non-activating `NSPanel`, the four `collectionBehavior` flags, level above the main menu, `isMovable = false`, no shadow, clear background | `UI/Window/NotchWindow.swift:13-62` | Standard AppKit configuration, originally NotchDrop's. Keep `canBecomeMain` false. Make `canBecomeKey` conditional (only when a text field needs it, for "deny with an explanation"). |
| Fixed oversized window, SwiftUI content animates inside | `UI/Window/NotchWindowController.swift:23-30` | Size it to our maximum (about 560 x 420 plus shadow margin), not full width by 750. |
| `NSHostingView` subclass with `hitTest` limited to the live content rect | `UI/Window/NotchViewController.swift:13-23` | Derive the rect from the same layout values the view uses, one source of truth. |
| Notch size from `safeAreaInsets.top` and the two `auxiliaryTop…Area` widths; `CGDisplayIsBuiltin` for the built-in screen | `Core/Ext+NSScreen.swift:12-39` | Public AppKit API, available on macOS 12+. Decide the width correction ourselves by measuring, do not import the `+ 4`. |
| Pure geometry value type, separated from views | `Core/NotchGeometry.swift` | Good seam for unit tests. |
| Animatable two-radius notch `Shape` | `UI/Components/NotchShape.swift` | Take the idea from DynamicNotchKit (MIT), or draw our own continuous-curve path as the design brief asks. |
| Separate, asymmetric springs for open and close | `UI/Views/NotchView.swift:131-132, 169` | Tune our own values against the design. |
| Debounced `didChangeScreenParametersNotification`, skip when nothing changed, never replay launch animation | `App/ScreenObserver.swift`, `App/WindowManager.swift:30-40` | Compare screen id, frame and notch size, not only frame. |
| Agent app: `LSUIElement` plus `.accessory` | `Info.plist:15`, `AppDelegate.swift:71` | |

### Proposed attribution

If we follow the recommendation (own code, borrowed techniques), section 4 is not strictly triggered, but we credit anyway. Add a `NOTICE` file at the repo root and bundle it in the app's resources:

```
notch-orchestrator

The overlay window approach (non-activating panel above the menu bar,
click-through hosting view, notch geometry from NSScreen) is informed by:

  Vibe Notch (formerly Claude Island), https://github.com/farouqaldori/vibe-notch
  Copyright 2025 Farouq Aldori. Licensed under the Apache License, Version 2.0.

  NotchDrop, https://github.com/Lakr233/NotchDrop
  Copyright (c) 2024 Lakr Aream. MIT License.

  DynamicNotchKit, https://github.com/MrKai77/DynamicNotchKit
  Copyright (c) 2025 Kai Azim. MIT License.
```

If any file is actually copied or adapted from Vibe Notch, then additionally:

- Add `LICENSES/Apache-2.0.txt` (full text) and, for NotchDrop- or DynamicNotchKit-derived code, `LICENSES/MIT.txt` with both MIT copyright lines.
- Put this header at the top of each such file:

  ```swift
  // Portions adapted from Vibe Notch (https://github.com/farouqaldori/vibe-notch),
  // commit 10f1d24, file ClaudeIsland/<path>. Copyright 2025 Farouq Aldori.
  // Licensed under the Apache License, Version 2.0.
  // Modified by the notch-orchestrator authors: <one line describing the change>.
  ```

- Change the NOTICE wording from "is informed by" to "includes code adapted from", and list the files.

Our repo has no license of its own yet. That is a separate decision; Apache-2.0 and MIT material can be included in a project under either of those licenses or a proprietary one.

## What is done poorly: do not copy

| Do not copy | Reason |
|---|---|
| The spring/radius block in `NotchView.swift:13-16, 131-174`, `NotchActivityCoordinator.swift`, and the `+ 4` line as code | Traces to GPL-3.0 boring.notch (see provenance). |
| `NSApp.activate` + `makeKey` on open (`NotchWindowController.swift:75-78`) | Steals keyboard focus; our spec says "without leaving my current window". |
| Synthetic click re-posting (`NotchWindow.swift:69-120`, `NotchViewModel.swift:209-236`) | Needs Accessibility permission, moves the cursor, wrong coordinates on stacked displays (#32), and is only needed because the window is far larger than the content. |
| Full-width by 750 pt window | Turns a small panel into a large click-interception band. |
| Global `mouseMoved` monitor as the only hover source, 1 s open delay, no close on exit | Runs for every mouse move system-wide; panel stays open until a click elsewhere. Prefer an `NSTrackingArea` or a small always-interactive strip over the notch, with close on exit after a short grace period. |
| Two hand-tuned copies of the panel rect (`NotchGeometry.swift:29-31`, `NotchViewController.swift:55`) | Drift between visual and hit area (#67, PRs #15, #16). |
| Session monitor owned by the view, started in `.onAppear`; view model rebuilt on screen change | Couples the session core to window lifetime and loses UI state on every display change. |
| Singletons everywhere (`ScreenSelector.shared`, `EventMonitors.shared`, `SessionStore.shared`, `HookSocketServer.shared`, `NotchActivityCoordinator.shared`) | Blocks the tested seams ticket #4 asks for. |
| Fake 224 x 38 notch, always visible, on screens without one | Covers content on external displays (#41, #58, #100). Our design has a separate pill variant. |
| Dead `popping` state, dead SwiftUI hover/tap handlers | Confusing leftovers from NotchDrop. |
| The whole event pipeline: Python command hook, `ps` per event, unauthenticated `/tmp` socket, hook-supplied `status` strings, permissive phase machine, `PreToolUse` cache to guess `tool_use_id` | Source of every reliability issue in section 5. The spec already decides on HTTP hooks with a secret token and our own state model. |
| `HookInstaller` write path | No backup, no malformed-file guard, whole-file rewrite, errors swallowed (#85). Ticket #4 requires the opposite on each point. |
| Mixpanel and the machine-derived id | Violates "no telemetry". |

## Recommendations for ticket #4

1. Write the overlay ourselves. Use the `NSPanel` configuration from section 1 as the starting point: `[.borderless, .nonactivatingPanel]`, the four collection behaviours, a level above `.mainMenu`, `isMovable = false`, `hasShadow = false`, clear background.
2. Never call `NSApp.activate` or `makeKey` when the overlay opens. For ticket #4 the overlay is display-only (counters), so set `ignoresMouseEvents = true` permanently and skip hit testing, monitors and re-posting entirely. Interaction arrives with later tickets.
3. Create the window once per screen, at the maximum content size plus margin, top-centred. Animate only SwiftUI content. Do not animate the window frame.
4. Put notch measurement behind one pure type (input: screen frame, safe-area top inset, the two auxiliary widths; output: notch rect or "no notch") and unit-test it with recorded values from real machines. Verify the width on 14-inch, 16-inch and Air hardware before adding any correction constant.
5. Treat "no notch" as a distinct layout (the pill from the design brief) or show nothing in ticket #4. Do not draw a fake notch.
6. Keep the session core and the hook server in app-level objects that outlive any window. The window layer observes them. On `didChangeScreenParametersNotification` (debounced about 0.5 s) reposition or rebuild the window only; compare screen id, frame and notch size.
7. Default to the built-in display. Do not use `NSScreen.main` for anything geometric; use `NSScreen.screens.first` when the primary screen is meant.
8. Leave side padding between collapsed content and the notch edge from the start (upstream needed 4 pt, issue #79), and hide the overlay completely when there are no live sessions, as acceptance criterion 2 requires.
9. Take nothing from upstream's hook script, socket server, installer or phase machine. For the session core's tests, include the sequences behind the known upstream failures: `Stop` followed by a late `PostToolUse` (#98), `SubagentStop` mid-turn (#36), compaction and resume (#18), and a process that dies without `SessionEnd` (#29).
10. Add the `NOTICE` file with the three credits in the same change that introduces the overlay. Check the app's minimum of macOS 14: everything in the "carry over" table is available there (upstream's 15.6 target is not caused by the overlay code, as far as the APIs it calls show).

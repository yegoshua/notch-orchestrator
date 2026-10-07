# Design brief for Claude Design

Paste everything below the line into Claude Design. Full product spec: issue #1.

---

## What I need

Design the interface of a native macOS app that lives in the MacBook notch, the way Dynamic Island lives at the top of an iPhone. The app watches and controls Claude Code sessions (an AI coding agent that runs in terminals and in a desktop app). A developer typically has 3 to 8 sessions running at once.

I need every state listed under "Screens" drawn on one canvas, at real size, on a MacBook desktop background so the scale is honest. I will hand these frames to an engineer to build in SwiftUI.

## The one job of this interface

Answer, in half a second and in peripheral vision: **"does any session need me right now?"**

Everything else is secondary. If a choice makes the interface richer but makes that answer slower to read, choose the plainer option.

## Who uses it and when

A developer who is busy in another window (editor, browser). They are not looking at the notch. They glance at it, or it gets their attention when a session is blocked. Interactions are short: one click or one keystroke, then back to work.

## Physical constraints

- The island is a black shape that extends the hardware notch. It is always black, in both light and dark system themes, so that it reads as part of the hardware.
- Hardware notch on a 14-inch MacBook Pro is roughly 185 pt wide and 32 pt tall; the menu bar is about 37 pt tall. Nothing can be drawn inside the notch itself, only to its left and right and below it.
- **Collapsed:** about 80 to 100 pt of usable width on each side of the notch, at menu bar height. Content here is tiny: think 11 to 12 pt text and 8 pt marks.
- **Expanded:** grows downward and outward from the notch. Keep it within about 560 pt wide and 420 pt tall. It covers other windows while open, so it must be compact.
- Bottom corners are rounded with a continuous curve; the top edge is flush with the screen edge.
- On screens without a notch the same content lives in a pill at the top centre. Draw this variant too.

## Session states and their meaning

Use one consistent colour and shape per state everywhere. State must never be carried by colour alone.

| State | Meaning | Urgency |
|---|---|---|
| Waiting for me | Blocked on a permission request or a question | The only urgent one |
| Working | The agent is running | Calm |
| Just finished | Turn completed in the last few minutes | Informational |
| Failed | The session errored | Noticeable, not alarming |
| Unknown | State cannot be confirmed | Deliberately muted |

## Screens

### 1. Collapsed

- **1a. Idle.** No live sessions. Only a usage ring on the right. The left side is empty.
- **1b. Working.** For example 3 working, 1 just finished. Counters by state on the left of the notch, usage ring on the right.
- **1c. Needs me.** For example 2 waiting, 3 working. The waiting counter must be the most visible element.
- **1d. Usage ring states.** 23 percent, 78 percent, 96 percent, and "no data yet".
- **1e. Many sessions.** 2 waiting, 9 working, 4 finished. The layout must not change shape compared with 1b.

Counters are numbers next to a state mark, not one dot per session.

### 2. Transient line (appears by itself for a few seconds, no sound)

- **2a.** "frontoffice finished" with a one-line summary.
- **2b.** "payments-api failed".

One line, slightly wider than the collapsed state, then it collapses.

### 3. Permission request card (appears by itself with a sound)

Shows: session title, project, origin (CLI or desktop app), the tool, and exactly what is being asked.

- **3a. Shell command.** `git push origin feature/deposit-limits`, shown in full in monospace.
- **3b. Long command.** A command of about 300 characters. Show how it truncates and how the user sees the rest.
- **3c. File edit.** File path plus a 4 to 6 line excerpt of the change with added and removed lines.
- **3d. Deny with explanation.** The same card after choosing "deny with explanation": a short text field and a send action.
- **3e. Queue.** A second request from another session is waiting behind this one. Show that there is more and how many.

Actions on every card: **Allow**, **Deny**, **Deny with explanation**, and a quieter **Open in session**. Allow and Deny need visible keyboard hints. Allow must not be so prominent that it invites approving without reading.

### 4. Agent question card

- **4a.** A multiple-choice question with 3 options, each with a one-line description, answerable with one click.
- **4b.** The same question in a read-only variant where the only action is "Open in session".

### 5. Expanded session list (on hover or hotkey)

- **5a. Typical.** 5 sessions. Each row: state mark, title, project, origin, current activity ("Editing validation.ts"), elapsed time. Sessions that need me are at the top.
- **5b. With subagents.** One session expanded to show 3 running subagents and what each is doing.
- **5c. Row hover.** Shows where a click leads: "Open terminal tab", "Open in Claude", "Open VS Code window".
- **5d. Usage section.** Five-hour and weekly limits with percentage, reset time, and how fresh the data is ("updated 2 min ago").
- **5e. Empty.** No live sessions.
- **5f. Long list.** 12 sessions. Show scrolling or grouping.

### 6. Settings (a regular macOS settings window, not in the notch)

- **6a. General.** Start at login, hotkey, which screen shows the island, how long finished sessions stay visible.
- **6b. Interruptions.** Three modes: Loud, Smart (default), Quiet, each with a one-line description; sound choice; respect Focus.
- **6c. Connection.** Connection status to Claude Code, "Repair connection", "Remove completely" with a clear description of what is removed.

### 7. First launch

- **7a.** One screen that explains what the app will change in Claude Code settings, that a backup is taken, and a single action to connect.
- **7b.** Connected, with a hint to start a session.

### 8. No-notch variant

- **8a.** Collapsed pill at the top centre of an external monitor.
- **8b.** The same pill expanded with a permission request.

## Motion (describe in notes next to the frames)

- How the collapsed shape grows into the card and into the list, and how it returns.
- How a counter changes when a session moves between states.
- How the transient line appears and leaves.

Motion should feel like the hardware notch stretching, not like a popover opening.

## Sample content to use

Session titles and projects: "Deposit limit validation" in frontoffice, "Fix flaky webhook test" in payments-api, "Migrate to Zustand stores" in cashier-lite, "Poker room filters" in poker-planning, "Refactor QR component" in cashier-lite.

Use realistic commands, file paths and activity lines. No lorem ipsum.

## Visual direction

- Quiet, dense, precise. A system component, not a branded app.
- Black surface, off-white text, one accent reserved for "waiting for me". Other states use restrained colours.
- System font for interface text, a monospace font for commands, paths and code.
- No mascots, no gradients, no glow, no illustration.
- Text must stay readable at 11 pt on black.

## What to avoid

- One dot per session in the collapsed state.
- Anything that animates continuously while sessions are simply working.
- Decorative elements that compete with the waiting counter.
- Layouts that shift when the number of sessions changes.
- Using the name or logo of Claude or Anthropic as branding. The product has a working code name only.

## Deliverables

1. All frames above on one canvas, grouped and labelled by the numbers used here, at 1x on a MacBook desktop mock.
2. A small component sheet: state marks, counters, usage ring, buttons, session row, card.
3. A token list: colours, type sizes, spacing, corner radii.
4. Motion notes beside the relevant frames.

Start with screens 1 and 3, since they define the visual language. Show me two distinct directions for those before drawing the rest.

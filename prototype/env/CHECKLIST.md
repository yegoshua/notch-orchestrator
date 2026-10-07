# Manual checklist for ticket #3 (prototype findings 3, 4, 6)

Throwaway prototype. Each check: **Do**, **Look at**, **Write down**. CLI first, then the desktop app.
All paths are relative to the repo root. Nothing here touches `~/.claude/settings.json`: the status
line is registered only in `sandbox/.claude/settings.json` and so runs only for sessions opened in `sandbox/`.

Before you start:
- `cat sandbox/.claude/settings.json` must show a `statusLine` pointing at `prototype/env/statusline-logger.sh`.
- The terminal CLI on this machine was **not logged in** when this was prepared ("Not logged in · Run /login").
  Log in with the subscription account first, otherwise `rate_limits` can never appear.
- To start from a clean log: `rm prototype/env/logs/statusline.jsonl`.

## A. Status line in the CLI (finding 3)

1. **Status line runs at session start**
   - Do: in a terminal, `cd sandbox && claude`. Accept the trust dialog if one is shown. Type nothing yet.
   - Look at: the line under the prompt, expected `[proto-sl] no rate_limits | sid xxxxxxxx`.
   - Write down: shown or not; whether a trust dialog appeared; the `sid`.

2. **When `rate_limits` first appear**
   - Do: send one short message (`say ok`), wait for the answer. Then run `prototype/env/statusline-summary.sh`.
   - Look at: the status line changing to `5h N% 7d N%`; in the summary, the line
     `rate_limits: first present in record #K (K-1 record(s) before it)` and `shape:` for that session.
   - Write down: K; whether it appeared right after the first answer; the exact shape (which of
     `five_hour` / `seven_day` / others exist, number types, `resets_at` unit); the plan of this account.

3. **Updates and reset times**
   - Do: send two more messages; run the summary again.
   - Look at: `first value` vs `last value`; convert one `resets_at` with `date -r <resets_at>`.
   - Write down: whether percentages are integers or fractions, whether they change per message, and
     whether the reset times match what `/usage` shows.

4. **Print mode does not run the status line** (expected)
   - Do: `wc -l prototype/env/logs/statusline.jsonl`; then `cd sandbox && claude -p "say ok"`; count again.
   - Write down: whether the count changed (expected: no).

## B. Status line in the desktop app (finding 3)

5. **Does the command run at all in a desktop Code session**
   - Do: note `wc -l prototype/env/logs/statusline.jsonl`. In the Claude desktop app start a new Code
     session with the folder `sandbox/` (local folder, **no worktree**: `sandbox/.claude/settings.json`
     is not committed, so a worktree copy would not contain it). Send `say ok`.
   - Look at: `prototype/env/statusline-summary.sh`: is there a session with `entrypoint: claude-desktop`?
     Does the app UI show the `[proto-sl]` text anywhere?
   - Write down: runs / does not run; if it runs, `host_session_id(env)` value (empty or `local_...`).

6. **Does it receive `rate_limits` there**
   - Do: send two more messages in that desktop session; run the summary.
   - Look at: the `rate_limits:` line of the desktop session.
   - Write down: present or `NEVER present`; shape compared with check 2. If the command never ran,
     write that the notch needs another limits source for desktop-only use (see README, "Surprises").

## C. Hook session id -> desktop record (finding 4)

7. **Desktop session resolves to its record**
   - Do: take the `session_id` of the desktop session from check 5 (summary output, or agent A's hook log
     in `prototype/hooks/logs/`). Run `prototype/env/find-desktop-session.py <session_id>`.
   - Look at: `desktop sessionId`, `title`, `cwd`, `match`.
   - Write down: found or not; is the title the one shown in the app sidebar; the `local_...` id.

8. **CLI session does not resolve**
   - Do: run the resolver with the `session_id` from check 1.
   - Look at: `NO desktop record references ...`, exit code 1 (`echo $?`).
   - Write down: confirmed or not.

9. **Is the record there in time, and does the id move**
   - Do: start another desktop session in `sandbox/`; immediately take the first `session_id` from the hook
     log (`SessionStart`) and run the resolver. Then in that session run `/clear` (or `/compact`), send a
     message, and run the resolver with the old and the new `session_id`.
   - Look at: found at once or only after a moment; `match:` (`current:cliSessionId` vs `lineage:...`).
   - Write down: delay if any; whether `session_id` changed after `/clear`; whether the old id still resolves.

10. **Environment shortcut**
    - Do: `prototype/env/statusline-summary.sh` (if check 5 ran), and look into agent A's command-hook log
      if it records the environment.
    - Write down: are `CLAUDE_CODE_ENTRYPOINT=claude-desktop` and `CLAUDE_CODE_HOST_SESSION_ID=local_...`
      available to commands run by a desktop session.

## D. Deep links (finding 4)

Prepare: keep two desktop Code sessions, **T** (target, from check 5) and **O** (any other one). Before each
link click on O so that T is not on screen. Get the commands: `prototype/env/deeplinks.sh <session_id of T>`.
Run **one** `open` line, observe, write down, then the next. Outcome vocabulary: *opened exactly T* /
*only activated the app* / *opened another or a new session* / *nothing*.

11. `open 'claude://code/continue?session=local_...'` — expected: opened exactly T. Write down the outcome.
12. `open 'claude://claude.ai/epitaxy/local_...'` — expected: opened exactly T. Write down the outcome.
13. `open 'claude://code/needs-input?session=local_...'` while T is **not** waiting, then again while T shows
    a permission request (ask it to run a shell command). Write down both outcomes.
14. `open 'claude://claude.ai/code/local_...'` — unknown. Write down the outcome.
15. Negative controls: `open 'claude://code/local_...'` and `open 'claude://code/continue?session=<CLI uuid>'`
    — expected: nothing. Write down the outcome (does the app even come to the front?).
16. Positive control: `open 'claude://code/continue?session=last'` — expected: the most recently active session.
17. `open 'claude://resume?session=<CLI uuid of T>'` — expected: opens T without creating anything.
    Look at the sidebar: no new session must appear. Write down the outcome.
18. `open 'claude://resume?session=<session_id of the CLI session from check 1>'` — expected: the CLI session
    is **imported** as a new desktop session. Only do this if you accept that side effect (the new session
    can be deleted afterwards). Write down: imported or not, its new `local_...` id (`find-desktop-session.py --list 3`).
19. Cold start: quit the desktop app, run the winning link from 11-12 again.
    Write down: does it start the app and land on T.
20. Conclusion — write down: which URL shape to use, which identifier it expects, and what happens for an unknown id.

## E. Signing and Automation permission (finding 6)

Scripts are in `prototype/env/signing/`. The app asks Terminal for its window count and shows an alert
`AE test <variant> v<version>` with `OK: ...` or `ERROR -1743 ...`; every run also appends a line to
`prototype/env/signing/.build/aetest.log`. Always launch with the printed `open -n '...'` command or from
Finder, never by running the binary from a terminal (TCC would then judge the terminal, not the app).
Installed path: `prototype/env/signing/.build/installed/NotchAETest-<variant>.app` (set `INSTALL_DIR=~/Applications`
for all commands if you prefer a more realistic place). Keep Terminal.app running during the checks.

Ad-hoc:

21. **Grant with ad-hoc v1.0**
    - Do: `signing/build.sh adhoc`, `tccutil reset AppleEvents dev.notch-orchestrator.aetest.adhoc`,
      `signing/install.sh adhoc 1.0`, then the printed `open -n` command. Click **Allow** in the system prompt.
    - Look at: alert `v1.0` + `OK`; System Settings > Privacy & Security > Automation lists NotchAETest -> Terminal.
    - Write down: prompt shown (yes/no), result.
22. **Same build again** (baseline)
    - Do: run the same `open -n` command again.
    - Write down: prompt shown again? (expected: no)
23. **Replace with ad-hoc v1.1**
    - Do: `signing/install.sh adhoc 1.1`, then `open -n ...`.
    - Look at: alert must say `v1.1`. Is the Automation prompt shown again, or an error -1743 without a prompt?
    - Write down: prompt again (yes/no), result code, and whether the Automation list now shows one or two entries.

Self-signed:

24. **Create the certificate** (once, by hand)
    - Do: open **Keychain Access** (Spotlight; on recent macOS it lives in
      `/System/Library/CoreServices/Applications/`). Menu Keychain Access > Certificate Assistant >
      **Create a Certificate...** Name: `Notch Orchestrator Dev`; Identity Type: **Self Signed Root**;
      Certificate Type: **Code Signing**. Optionally tick "Let me override defaults" to set a longer validity
      (default 365 days). Create; keep it in the **login** keychain. No need to mark it as trusted.
    - Look at: `security find-identity -p codesigning | grep "Notch Orchestrator Dev"` prints one line
      (without `-v`: an untrusted self-signed identity is not listed as "valid", codesign still uses it).
    - Write down: the certificate SHA-1 from that line.
25. **Build self-signed**
    - Do: `signing/build.sh selfsigned`. macOS asks to let `codesign` use the key: enter the login password,
      **Always Allow**. Then `signing/show-requirements.sh`.
    - Look at: ad-hoc bundles show `designated => cdhash H"..."` (different for 1.0 and 1.1); self-signed ones
      should show `designated => identifier "dev.notch-orchestrator.aetest.selfsigned" and certificate leaf = H"..."`,
      **identical** for 1.0 and 1.1.
    - Write down: the four designated requirements.
26. **Grant with self-signed v1.0**
    - Do: `tccutil reset AppleEvents dev.notch-orchestrator.aetest.selfsigned`, `signing/install.sh selfsigned 1.0`,
      `open -n ...`, click **Allow**.
    - Write down: prompt shown, result.
27. **Replace with self-signed v1.1**
    - Do: `signing/install.sh selfsigned 1.1`, `open -n ...`.
    - Look at: alert must say `v1.1`. Prompt again?
    - Write down: prompt again (yes/no), result. Expected if the idea holds: no prompt, `OK`.
28. **Conclusion** — write down: does self-signed keep the grant across an update while ad-hoc loses it.
    Optional extra: log out/in or reboot and launch v1.1 once more.
29. **Clean up**
    - `tccutil reset AppleEvents dev.notch-orchestrator.aetest.adhoc`
    - `tccutil reset AppleEvents dev.notch-orchestrator.aetest.selfsigned`
    - `rm -rf prototype/env/signing/.build`
    - Remove the certificate: Keychain Access > login > My Certificates > delete `Notch Orchestrator Dev`
      (certificate **and** its private key), or `security delete-identity -c "Notch Orchestrator Dev"`.
      Keep it if the real app is going to be signed with it: a new certificate means a new requirement
      and every user re-granting permissions.

## F. Quarantine and Gatekeeper (finding 6, installer path)

30. **curl download has no quarantine attribute**
    - Do: `prototype/env/quarantine-check.sh` in a normal terminal.
    - Look at: the `>>> com.apple.quarantine:` lines (archive, app, executable) and the `spctl` verdict.
    - Write down: present/absent for each; the `spctl` line (expected `rejected`: Gatekeeper would refuse this
      app if it were quarantined).
31. **It launches without a Gatekeeper prompt**
    - Do: double-click the app at the path printed at the end (`.build/quarantine/curl/NotchAETest.app`).
    - Look at: does the `AE test` alert come up directly, or a "cannot be opened / Apple could not verify" dialog first.
      (An Automation prompt may appear: that is TCC, not Gatekeeper.)
    - Write down: Gatekeeper dialog yes/no; macOS version (`sw_vers -productVersion`).
32. **Comparison: browser download is quarantined**
    - Do: `prototype/env/quarantine-check.sh --serve`, open the printed URL in Safari or Chrome, download,
      unpack in Finder, `xattr -l ~/Downloads/NotchAETest-adhoc.zip`, `xattr -l ~/Downloads/NotchAETest.app`,
      double-click the unpacked app. Ctrl-C the server afterwards.
    - Write down: quarantine present on zip and app; the exact Gatekeeper dialog text; whether
      System Settings > Privacy & Security offers "Open Anyway".
33. Optional: repeat 30-32 with `selfsigned` (`quarantine-check.sh selfsigned`) and write down whether anything differs.

## G. Wrap up

34. Write findings 3, 4 and 6 into the "Prototype findings" section of issue #1, and tick the acceptance criteria of #3.

import Foundation
import Testing
import SessionCore

private func record(
    _ sessionID: String, cli: String? = nil, prior: [String] = [], title: String? = nil
) -> DesktopSessionRecord {
    DesktopSessionRecord(sessionID: sessionID, cliSessionID: cli, priorCLISessionIDs: prior, title: title)
}

/// Telling desktop app sessions from CLI ones by the desktop app's own session records.
@Suite struct DesktopSessionRecords {
    @Test func aRecordIsReadFromTheDesktopAppsFile() throws {
        let json = """
            {"sessionId": "local_11111111-2222", "cliSessionId": "aaaa", "priorCliSessionIds": ["9999"],
             "preClearCliSessionId": "8888", "title": "Deposit limit validation", "isArchived": false,
             "cwd": "/Users/me/project", "lastActivityAt": 1790000300000}
            """
        let record = try #require(DesktopSessionRecord(json: Data(json.utf8)))

        #expect(record.sessionID == "local_11111111-2222")
        #expect(record.cliSessionID == "aaaa")
        #expect(record.priorCLISessionIDs == ["9999", "8888"])
        #expect(record.title == "Deposit limit validation")
    }

    @Test func theRequestsTheDesktopAppTiedToTheSessionAreRead() throws {
        // As the desktop app wrote them; older records carry no provider.
        let json = """
            {"sessionId": "local_1", "prs": [
              {"prNumber": 95, "repo": "me/shop", "host": "github.com", "provider": "github",
               "url": "https://github.com/me/shop/pull/95", "branch": "feat/testimonials", "baseRef": "main",
               "state": "MERGED", "dismissed": true},
              {"prNumber": 12, "url": "https://gitlab.com/group/shop/-/merge_requests/12", "repo": "group/shop",
               "host": "gitlab.com", "branch": "feat/size-chart", "baseRef": "main", "state": "OPEN"},
              {"repo": "me/shop", "branch": "no-number"}]}
            """
        let record = try #require(DesktopSessionRecord(json: Data(json.utf8)))

        #expect(record.requests == [
            RequestLink(number: 95, url: "https://github.com/me/shop/pull/95", branch: "feat/testimonials", state: "MERGED"),
            RequestLink(number: 12, url: "https://gitlab.com/group/shop/-/merge_requests/12", branch: "feat/size-chart", state: "OPEN"),
        ])
    }

    @Test func aRecordWithoutATitleHasNone() throws {
        let record = try #require(DesktopSessionRecord(json: Data(#"{"sessionId": "local_1", "title": "  "}"#.utf8)))

        #expect(record.title == nil)
        #expect(record.cliSessionID == nil)
        #expect(record.requests.isEmpty)
    }

    @Test func whatIsNotASessionRecordIsNotRead() {
        #expect(DesktopSessionRecord(json: Data("not json".utf8)) == nil)
        #expect(DesktopSessionRecord(json: Data(#"{"tasks": []}"#.utf8)) == nil)
        #expect(DesktopSessionRecord(json: Data(#"{"sessionId": 7}"#.utf8)) == nil)
        #expect(DesktopSessionRecord(json: Data()) == nil)
    }

    @Test func aSessionIsFoundByItsCurrentCLIIdentifier() {
        let records = [record("local_a", cli: "one"), record("local_b", cli: "two", title: "Second")]

        #expect(DesktopSessionRecord.owning("two", among: records)?.title == "Second")
    }

    @Test func aSessionIsFoundByAnIdentifierItHadEarlier() {
        let records = [record("local_a", cli: "now", prior: ["before", "long-before"])]

        #expect(DesktopSessionRecord.owning("long-before", among: records)?.sessionID == "local_a")
    }

    @Test func theCurrentOwnerWinsOverOneThatHadTheIdentifierEarlier() {
        let records = [record("local_fork", cli: "x", prior: ["shared"]), record("local_owner", cli: "shared")]

        #expect(DesktopSessionRecord.owning("shared", among: records)?.sessionID == "local_owner")
    }

    @Test func aSessionImportedFromTheCLIIsFoundByItsOwnName() {
        let records = [record("local_imported")]

        #expect(DesktopSessionRecord.owning("imported", among: records)?.sessionID == "local_imported")
    }

    @Test func theDesktopIdentifierTheProcessReportsWinsOverEverythingElse() {
        let records = [record("local_other", cli: "id"), record("local_host", cli: "moved-on")]

        #expect(DesktopSessionRecord.owning("id", hostSessionID: "local_host", among: records)?.sessionID == "local_host")
    }

    @Test func aSessionNoRecordMentionsHasNoOwner() {
        #expect(DesktopSessionRecord.owning("cli-only", among: [record("local_a", cli: "one")]) == nil)
        #expect(DesktopSessionRecord.owning("cli-only", among: []) == nil)
    }
}

@Suite struct SessionOriginAndLocation {
    @Test func aSessionNothingIsKnownAboutIsACLISessionWithNowhereToJump() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-killed").play(into: &core) { $0.event.name == "PreToolUse" }

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.location == .unknown)
        #expect(session.origin == .cli)
        #expect(session.location.jumpTarget == nil)
    }

    @Test func aDesktopSessionCarriesItsOriginAndTheTitleOfTheSidebar() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core) { $0.event.name == "PreToolUse" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(
            Observation(sessionID: id, process: .alive, title: "Deposit limit validation",
                        location: .desktopApp(sessionID: "local_1")),
            observedAt: at)

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.origin == .desktop)
        #expect(session.location == .desktopApp(sessionID: "local_1"))
        #expect(session.title == "Deposit limit validation")
    }

    @Test func whereASessionRunsIsRememberedWhenALaterLookFindsNothing() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core) { $0.event.name == "PreToolUse" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(
            Observation(sessionID: id, process: .alive, location: .terminalApp(tty: "/dev/ttys011")), observedAt: at)
        core.reconcile(Observation(sessionID: id, process: .unknown), observedAt: at + 5)

        #expect(core.snapshot(at: at + 5).sessions.first?.location == .terminalApp(tty: "/dev/ttys011"))
    }

    @Test func aDesktopSessionIdleForLongerThanTheThresholdIsNotLive() {
        var core = SessionCore(settings: Settings(livenessThreshold: 600))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func found(_ id: String, endedAgo: TimeInterval) -> Observation {
            Observation(
                sessionID: id, process: .alive,
                transcript: TranscriptTail(turn: .ended(pendingBackgroundAgents: 0), at: now - endedAgo),
                location: .desktopApp(sessionID: "local_\(id)"))
        }

        // Its process is still there: the desktop app keeps sessions open for days.
        core.reconcile(found("idle", endedAgo: 3 * 86400), observedAt: now)
        core.reconcile(found("recent", endedAgo: 60), observedAt: now)

        let snapshot = core.snapshot(at: now)
        #expect(snapshot.sessions.map(\.id) == ["recent"])
        #expect(snapshot.counters == Counters(finished: 1))
    }

    @Test func aRequestSaysWhereItsSessionRunsAndWhatTheCallIsFor() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-allow")
        let id = fixture.steps[0].event.sessionID
        let started = fixture.play(into: &core) { $0.event.name == "UserPromptSubmit" }
        core.reconcile(
            Observation(sessionID: id, process: .alive, location: .terminalApp(tty: "/dev/ttys011")), observedAt: started)
        let at = fixture.play(into: &core, after: started) { $0.event.name == "PermissionRequest" }

        let request = try #require(core.snapshot(at: at).requests.first)
        #expect(request.location == .terminalApp(tty: "/dev/ttys011"))
        #expect(request.summary == "Run hello.sh")
    }
}

/// What a click on a session does, said before the click.
@Suite struct JumpTargets {
    @Test func aTerminalSessionOpensItsExactTab() throws {
        let target = try #require(SessionLocation.terminalApp(tty: "/dev/ttys011").jumpTarget)

        #expect(target.label == "Open terminal tab")
        #expect(target.precision == .exact)
    }

    @Test func aDesktopSessionOpensInTheDesktopApp() throws {
        let target = try #require(SessionLocation.desktopApp(sessionID: "local_1").jumpTarget)

        #expect(target.label == "Open in Claude")
        #expect(target.precision == .exact)
    }

    @Test func aVSCodeSessionOpensTheWindowOfItsProjectOnly() throws {
        let target = try #require(SessionLocation.vsCode(bundleID: "com.microsoft.VSCode").jumpTarget)

        #expect(target.label == "Open VS Code window")
        #expect(target.precision == .window)
    }

    @Test func anotherTerminalIsOnlyBroughtForward() throws {
        let target = try #require(SessionLocation.application(name: "iTerm2", bundleID: "com.googlecode.iterm2").jumpTarget)

        #expect(target.label == "Bring iTerm2 forward")
        #expect(target.precision == .application)
    }

    @Test func everyTargetSaysHowCloseItGetsInAFewWords() {
        #expect(SessionLocation.terminalApp(tty: "/dev/ttys011").jumpTarget?.reach == "exact tab")
        #expect(SessionLocation.vsCode(bundleID: "com.microsoft.VSCode").jumpTarget?.reach == "project window")
        #expect(SessionLocation.application(name: "Ghostty", bundleID: "x").jumpTarget?.reach == "app only")
        // Whether the desktop app opens the session itself was never confirmed on a live system.
        #expect(SessionLocation.desktopApp(sessionID: "local_1").jumpTarget?.reach == "this session, else the app")
    }

    @Test func everyTargetExplainsHowCloseItGets() {
        let locations: [SessionLocation] = [
            .terminalApp(tty: "/dev/ttys011"), .desktopApp(sessionID: "local_1"),
            .vsCode(bundleID: "com.microsoft.VSCode"), .application(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        ]
        for location in locations {
            #expect(location.jumpTarget?.explanation.isEmpty == false)
        }
    }

    @Test func originIsNamedTheWayTheListAndTheCardShowIt() {
        #expect(SessionLocation.unknown.originLabel == "CLI")
        #expect(SessionLocation.terminalApp(tty: "/dev/ttys011").originLabel == "CLI")
        #expect(SessionLocation.desktopApp(sessionID: "local_1").originLabel == "Desktop")
        #expect(SessionLocation.vsCode(bundleID: "com.microsoft.VSCode").originLabel == "VS Code")
        #expect(SessionLocation.terminalApp(tty: "/dev/ttys011").originDescription == "Terminal (CLI)")
        #expect(SessionLocation.desktopApp(sessionID: "local_1").originDescription == "Desktop app")
        #expect(SessionLocation.vsCode(bundleID: "com.microsoft.VSCode").originDescription == "VS Code (CLI)")
        #expect(SessionLocation.application(name: "iTerm2", bundleID: "x").originDescription == "iTerm2 (CLI)")
        #expect(SessionLocation.unknown.originDescription == "CLI")
    }
}

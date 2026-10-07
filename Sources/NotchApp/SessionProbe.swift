import Darwin
import Foundation
import SessionCore

/// Looks at the system for what the hooks did not say: is the session's process there, and what
/// does the end of its transcript show. The session core decides what to make of the answers.
protocol SessionProbe: Sendable {
    /// One observation per tracked session. With `discover`, also one per session that has a live
    /// process but is not tracked, so the list can be rebuilt after the app restarts.
    func observe(tracked: [(id: String, transcriptPath: String?)], discover: Bool) -> [Observation]
}

extension AppConfig {
    /// Where Claude Code keeps its process records and transcripts. The app only reads there.
    /// `-claudeDataDirectory …` points it elsewhere.
    var claudeDataDirectory: URL {
        UserDefaults.standard.string(forKey: "claudeDataDirectory").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
}

/// Reads what Claude Code keeps on disk: a record per running process in `sessions/<pid>.json`
/// and a transcript per session under `projects/`, and the desktop app's session records. None of
/// these formats is documented, so everything here degrades to "unknown" rather than fail.
///
/// Not safe for concurrent use: one `observe` at a time.
final class ClaudeSessionProbe: SessionProbe, @unchecked Sendable {
    /// The Claude Code data directory, `~/.claude` unless overridden. Only ever read.
    private let directory: URL
    /// The process each session was last seen alive in. The record of a killed session does not
    /// stay around forever, and then this is all that says the session ever had a process.
    private var lastSeenAlive: [String: ProcessRecord] = [:]
    private let desktopRecords: DesktopSessionRecords
    /// The program each live process was found to run in. It does not change while the process lives.
    private var hosts: [pid_t: SessionLocation] = [:]

    init(directory: URL, desktopSessionsDirectory: URL) {
        self.directory = directory
        desktopRecords = DesktopSessionRecords(directory: desktopSessionsDirectory)
    }

    func observe(tracked: [(id: String, transcriptPath: String?)], discover: Bool) -> [Observation] {
        let records = processRecords()
        for (id, found) in records {
            if let live = found.first(where: \.isAlive) { lastSeenAlive[id] = live }
        }
        let known = Set(tracked.map(\.id))
        // Read anew every time: the identifier a desktop session runs under changes over its life.
        let desktop = desktopRecords.read()
        var observations = tracked.map { session in
            observation(session.id, among: records, desktop: desktop, transcriptPath: session.transcriptPath)
        }
        if discover {
            for (id, found) in records where !known.contains(id) && found.contains(where: \.isAlive) {
                observations.append(observation(id, among: records, desktop: desktop, transcriptPath: nil))
            }
        }
        lastSeenAlive = lastSeenAlive.filter { known.contains($0.key) || records[$0.key] != nil }
        let livePIDs = Set(records.values.joined().map(\.pid))
        hosts = hosts.filter { livePIDs.contains($0.key) }
        return observations
    }

    private func observation(
        _ id: String, among records: [String: [ProcessRecord]], desktop: [DesktopSessionRecord],
        transcriptPath: String?
    ) -> Observation {
        let process = process(of: id, among: records)
        let live = records[id]?.first(where: \.isAlive)
        let record = live ?? records[id]?.first ?? lastSeenAlive[id]
        let owner = DesktopSessionRecord.owning(id, hostSessionID: record?.hostSessionID, among: desktop)
        // A record that only used to run this session, or was imported from it, says less than
        // the program the session's own process is found in: it may have gone back to a terminal.
        let ownsNow = record?.hostSessionID != nil || owner?.cliSessionID == id
        var location = SessionLocation.unknown
        if !ownsNow, let pid = live?.pid {
            location = hosts[pid] ?? ProcessHost.location(of: pid)
            // Not finding the program is no answer to keep.
            if location != .unknown { hosts[pid] = location }
        }
        if location == .unknown, let desktopID = record?.hostSessionID ?? owner?.sessionID {
            location = .desktopApp(sessionID: desktopID)
        }
        let transcript = transcriptPath.map { URL(fileURLWithPath: $0) }
            ?? locateTranscript(id, cwd: record?.cwd)
        let text = process == .dead ? nil : transcript.flatMap(Self.end(of:))
        return Observation(
            sessionID: id, process: process,
            transcript: text.flatMap(TranscriptReader.tail(of:)),
            cwd: record?.cwd,
            // The desktop sidebar's title first, so that the session can be found there.
            title: (location.origin == .desktop ? owner?.title : nil) ?? record?.userGivenName ?? text.flatMap(TranscriptReader.title(in:)),
            transcriptPath: transcript?.path, location: location)
    }

    private func process(of id: String, among records: [String: [ProcessRecord]]) -> Observation.Process {
        if let found = records[id] {
            return found.contains(where: \.isAlive) ? .alive : .dead
        }
        // No record. A session never seen with a process stays a question; one that had a
        // process is judged by it.
        guard let last = lastSeenAlive[id] else { return .unknown }
        if !last.isAlive { return .dead }
        // `/clear` keeps the process and gives it a new session: the old one is over.
        let takenOver = records.values.joined().contains { $0.pid == last.pid }
        return takenOver ? .dead : .unknown
    }

    // MARK: Process records

    private struct ProcessRecord {
        var pid: pid_t
        var sessionID: String
        var cwd: String?
        var userGivenName: String?
        /// The desktop app's identifier for the session, when the desktop app started the process.
        var hostSessionID: String?
        /// When Claude Code wrote the record, shortly after the process started.
        var startedAt: Date?

        /// The process exists and is not a later one that was handed the same pid.
        var isAlive: Bool {
            guard kill(pid, 0) == 0 || errno == EPERM else { return false }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard let startedAt, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return true }
            return TimeInterval(info.pbi_start_tvsec) <= startedAt.timeIntervalSince1970 + 5
        }
    }

    private func processRecords() -> [String: [ProcessRecord]] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("sessions"), includingPropertiesForKeys: nil)) ?? []
        var records: [String: [ProcessRecord]] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = object["pid"] as? Int, pid > 0, let id = object["sessionId"] as? String
            else { continue }
            records[id, default: []].append(ProcessRecord(
                pid: pid_t(pid), sessionID: id, cwd: object["cwd"] as? String,
                userGivenName: object["nameSource"] as? String == "user" ? object["name"] as? String : nil,
                hostSessionID: (object["hostSessionId"] as? String).flatMap { $0.hasPrefix("local_") ? $0 : nil },
                startedAt: (object["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }))
        }
        return records
    }

    // MARK: Transcripts

    private func locateTranscript(_ id: String, cwd: String?) -> URL? {
        let projects = directory.appendingPathComponent("projects")
        let name = "\(id).jsonl"
        if let cwd {
            // Claude Code names the project folder after the path, every other character a dash.
            let folder = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
            let file = projects.appendingPathComponent(folder).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.map { $0.appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The last part of a file, enough to hold the entries that close or continue a turn.
    private static func end(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let window: UInt64 = 512 * 1024
        guard let size = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: size > window ? size - window : 0)) != nil,
              let data = try? handle.readToEnd()
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

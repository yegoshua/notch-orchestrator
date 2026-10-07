// Throwaway prototype (ticket #3, finding 6). Automation-permission probe.
// Sends one Apple event to Terminal.app ("count windows") and reports the result
// together with its own version, in an alert, on stdout and in a log file.
//
// IMPORTANT: launch it through Finder or `open`, never by running the binary from a
// terminal: in that case TCC holds the *terminal* responsible and the test is meaningless.
import AppKit

let info = Bundle.main.infoDictionary ?? [:]
let version = info["CFBundleShortVersionString"] as? String ?? "?"
let bundleId = Bundle.main.bundleIdentifier ?? "?"
let variant = info["AETestVariant"] as? String ?? "?"
let logPath = info["AETestLogPath"] as? String ?? (NSTemporaryDirectory() + "notch-aetest.log")

func appendLog(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = ("\(stamp) \(line)\n").data(using: .utf8)!
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(data); h.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

var errorInfo: NSDictionary?
let script = NSAppleScript(source: "tell application \"Terminal\" to count windows")!
let result = script.executeAndReturnError(&errorInfo)

let outcome: String
let hint: String
if let err = errorInfo {
    let code = err[NSAppleScript.errorNumber] as? Int ?? 0
    let msg = err[NSAppleScript.errorMessage] as? String ?? "?"
    outcome = "ERROR \(code): \(msg)"
    switch code {
    case -1743: hint = "Not permitted: Automation access was denied (or a stale denial is stored)."
    case -1744: hint = "Consent would be required but could not be asked."
    case -600:  hint = "Terminal is not running."
    default:    hint = ""
    }
} else {
    outcome = "OK: Terminal has \(result.int32Value) window(s)"
    hint = "Apple event was delivered: permission is granted."
}

let line = "bundle=\(bundleId) variant=\(variant) version=\(version) result=\(outcome)"
print(line)
appendLog(line)

app.activate(ignoringOtherApps: true)
let alert = NSAlert()
alert.messageText = "AE test \(variant) v\(version)"
alert.informativeText = "\(outcome)\n\(hint)\n\nbundle id: \(bundleId)\nlog: \(logPath)"
alert.alertStyle = errorInfo == nil ? .informational : .warning
alert.addButton(withTitle: "Quit")
alert.runModal()

import Foundation

public enum SessionOrigin: Equatable, Sendable {
    case cli
    case desktop
}

/// Where a session runs, which is also where a click on it can lead.
public enum SessionLocation: Equatable, Sendable {
    /// A Code session of the Claude desktop app, under the identifier the app knows it by.
    case desktopApp(sessionID: String)
    /// A tab of Terminal.app, known by its terminal device.
    case terminalApp(tty: String)
    /// The integrated terminal of VS Code. Which of its terminals cannot be told from outside.
    case vsCode(bundleID: String)
    /// Some other application the session's process descends from, usually another terminal.
    case application(name: String, bundleID: String)
    case unknown

    public static let terminalBundleID = "com.apple.Terminal"
    public static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    /// The application whose window shows the session.
    public var bundleID: String? {
        switch self {
        case .desktopApp: Self.claudeDesktopBundleID
        case .terminalApp: Self.terminalBundleID
        case .vsCode(let bundleID), .application(_, let bundleID): bundleID
        case .unknown: nil
        }
    }

    public var origin: SessionOrigin {
        if case .desktopApp = self { return .desktop }
        return .cli
    }

    /// A word for a row of the list.
    public var originLabel: String {
        switch self {
        case .desktopApp: "Desktop"
        case .vsCode: "VS Code"
        case .terminalApp, .application, .unknown: "CLI"
        }
    }

    /// The same with room to say which program the CLI runs in.
    public var originDescription: String {
        switch self {
        case .desktopApp: "Desktop app"
        case .terminalApp: "Terminal (CLI)"
        case .vsCode: "VS Code (CLI)"
        case .application(let name, _): "\(name) (CLI)"
        case .unknown: "CLI"
        }
    }

    /// Where a click leads. Nil when there is nowhere to go.
    public var jumpTarget: JumpTarget? {
        switch self {
        case .terminalApp:
            JumpTarget(
                label: "Open terminal tab", precision: .exact, reach: "exact tab",
                explanation: "Brings Terminal forward on the exact tab this session runs in")
        case .desktopApp:
            JumpTarget(
                label: "Open in Claude", precision: .exact, reach: "this session, else the app",
                explanation: "Opens this session in the Claude desktop app, or brings the app forward if it cannot")
        case .vsCode:
            JumpTarget(
                label: "Open VS Code window", precision: .window, reach: "project window",
                explanation: "Brings forward the VS Code window of this project, not the terminal inside it")
        case .application(let name, _):
            JumpTarget(
                label: "Bring \(name) forward", precision: .application, reach: "app only",
                explanation: "Brings \(name) forward; the window or tab has to be found by hand")
        case .unknown:
            nil
        }
    }
}

/// What a click on a session does, to be said before the click.
public struct JumpTarget: Equatable, Sendable {
    public enum Precision: Equatable, Sendable {
        /// The session itself: its tab, or the session inside the desktop app.
        case exact
        /// The window of the session's project.
        case window
        /// The application only.
        case application
    }

    public var label: String
    public var precision: Precision
    /// How close the jump gets, in a few words to show beside the label.
    public var reach: String
    /// One sentence on how close the jump gets.
    public var explanation: String
}

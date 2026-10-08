import Foundation
import Sparkle

/// Self-update through Sparkle: it looks for a newer release, checks the archive against the
/// update key the app was built with, replaces the app and starts it again. That key is the
/// updater's own and has nothing to do with how the app is signed for macOS.
@MainActor
final class AppUpdater {
    private let controller: SPUStandardUpdaterController?

    init() {
        // Only an app that was built with a feed and a key updates itself. A development build
        // has neither, and must not replace itself with a release.
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["SUFeedURL"] is String, info["SUPublicEDKey"] is String else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var isAvailable: Bool { controller != nil }

    /// The version the user runs, for the menu. Nil outside an app bundle.
    var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

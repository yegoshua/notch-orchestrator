import Foundation
import Sparkle

/// Self-update through Sparkle: it looks for a newer release, checks the archive against the
/// update key the app was built with, replaces the app and starts it again. That key is the
/// updater's own and has nothing to do with how the app is signed for macOS.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        // Only an app that was built with a feed and a key updates itself. A development build
        // has neither, and must not replace itself with a release.
        let info = Bundle.main.infoDictionary ?? [:]
        guard info["SUFeedURL"] is String, info["SUPublicEDKey"] is String else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var isAvailable: Bool { controller != nil }

    /// The version the user runs, for the menu. Nil outside an app bundle.
    var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Sparkle would install a downloaded update when the app quits, and an app that lives in
    /// the notch is never quit. So it is installed at once: the app is gone for a moment and the
    /// sessions are found again when it is back.
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Not from inside Sparkle's own call.
        Task { @MainActor in immediateInstallHandler() }
        return true
    }
}

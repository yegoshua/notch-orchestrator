import SessionCore
import SwiftUI

/// The island at rest: counters by state on the left wing and the usage ring on the right, or
/// both in a top-centre pill on screens without a notch. With no live sessions the left side is
/// empty. Nothing in it moves while sessions simply work.
struct CollapsedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presence: IslandPresence
    let geometry: NotchGeometry

    /// After "Remove Completely" nothing of the app should be left on screen.
    private var isVisible: Bool {
        let counters = model.snapshot.counters
        let hasSessions = counters.waiting + counters.failed + counters.working + counters.finished > 0
        return hasSessions || model.connectionStatus != .notConnected
    }

    var body: some View {
        BandRow(
            counters: model.snapshot.counters, limit: model.limits.fiveHour,
            showsRing: model.connectionStatus != .notConnected)
            .padding(.horizontal, (geometry.hasNotch ? Island.shoulder : 0) + Island.wingPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IslandBody(radius: geometry.collapsedRadius, hasShoulders: geometry.hasNotch))
            .padding(.top, geometry.hasNotch ? 0 : Island.pillDrop)
            // An open island draws the same band in the same place and takes over from here.
            .opacity(isVisible && !presence.isOpen ? 1 : 0)
            .animation(Island.quick, value: isVisible)
    }
}

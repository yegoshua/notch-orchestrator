import SessionCore
import SwiftUI

/// The island at rest: counters by state on the left wing and the usage ring on the right, or
/// both in a top-centre pill on screens without a notch. With no live sessions the left side is
/// empty. Nothing in it moves while sessions simply work.
struct CollapsedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presence: IslandPresence
    let geometry: NotchGeometry

    private var hasSessions: Bool {
        let counters = model.snapshot.counters
        return counters.waiting + counters.failed + counters.working + counters.finished > 0
    }

    /// After "Remove Completely" nothing of the app should be left on screen.
    private var isVisible: Bool {
        hasSessions || model.connectionStatus != .notConnected
    }

    /// How far the body draws in from each side while there is nothing to count. At the notch the
    /// empty wing goes altogether, its edge hidden behind the hardware; the pill shrinks evenly.
    private var idleInsets: (leading: CGFloat, trailing: CGFloat) {
        guard !hasSessions else { return (0, 0) }
        let spare = Island.wingWidth - Island.idleWingWidth
        return geometry.hasNotch ? (Island.wingWidth + Island.shoulder + Island.idleTuck, spare) : (spare, spare)
    }

    var body: some View {
        BandRow(
            counters: model.snapshot.counters, limit: model.limits.fiveHour,
            showsRing: model.connectionStatus != .notConnected)
            .padding(.horizontal, (geometry.hasNotch ? Island.shoulder : 0) + Island.wingPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IslandBody(radius: geometry.collapsedRadius, hasShoulders: geometry.hasNotch))
            .padding(.leading, idleInsets.leading)
            .padding(.trailing, idleInsets.trailing)
            .padding(.top, geometry.hasNotch ? 0 : Island.pillDrop)
            // An open island draws the same band in the same place and takes over from here.
            .opacity(isVisible && !presence.isOpen ? 1 : 0)
            .animation(Island.quick, value: isVisible)
            .animation(Island.settle, value: hasSessions)
    }
}

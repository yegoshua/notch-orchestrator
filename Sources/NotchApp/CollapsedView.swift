import SessionCore
import SwiftUI

/// The island at rest: the companion and counters by state left of the notch and the usage ring
/// right of it, or both in a top-centre pill on screens without a notch. It reaches only as far
/// as what it shows: without a connection nothing is drawn left of the notch. Only the companion
/// moves while sessions simply work.
struct CollapsedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presence: IslandPresence
    let geometry: NotchGeometry

    private var counters: Counters { model.snapshot.counters }
    private var showsRing: Bool { model.connectionStatus != .notConnected }

    private var hasSessions: Bool {
        counters.waiting + counters.failed + counters.working + counters.finished > 0
    }

    /// After "Remove Completely" nothing of the app should be left on screen.
    private var isVisible: Bool { hasSessions || showsRing }

    /// The companion is there as long as the app is: asleep when nothing runs.
    private var showsLeft: Bool { isVisible }

    /// A wing has room for two kinds of counter; what is merely done gives way to the others.
    private var showsFinished: Bool {
        [counters.waiting, counters.working, counters.failed].filter { $0 > 0 }.count <= 1
    }

    /// What lies between the two sides: the notch, or the gap of the pill.
    private var middle: CGFloat {
        geometry.hasNotch ? geometry.notchWidth : (showsLeft && showsRing ? Island.pillGap : 0)
    }

    var body: some View {
        let edge = geometry.collapsedEdge
        let gap = geometry.hasNotch ? Island.notchGap : 0
        HStack(spacing: 0) {
            if showsLeft {
                HStack(spacing: Island.companionGap) {
                    Companion(mood: CompanionMood(counters: counters))
                    if hasSessions { BandCounters(counters: counters, showsFinished: showsFinished) }
                }
                .padding(.leading, edge)
                .padding(.trailing, gap)
            }
            Color.clear.frame(width: middle)
                .alignmentGuide(.notchCentre) { $0[HorizontalAlignment.center] }
            if showsRing {
                LimitRing(window: model.limits.fiveHour)
                    .padding(.leading, gap)
                    .padding(.trailing, edge)
            }
        }
        .frame(maxHeight: .infinity)
        .background(IslandBody(radius: geometry.collapsedRadius, hasShoulders: geometry.hasNotch))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: DrawnSpan.self, value: proxy.frame(in: .global))
        })
        // The window is centred on the notch; so is the gap left for it, whatever stands beside
        // it. The pill is simply centred.
        .frame(maxWidth: .infinity, alignment: geometry.hasNotch
            ? Alignment(horizontal: .notchCentre, vertical: .center) : .center)
        .onPreferenceChange(DrawnSpan.self) { frame in
            presence.collapsedSpan = isVisible && !frame.isNull ? frame.minX...frame.maxX : nil
        }
        .padding(.top, geometry.hasNotch ? 0 : Island.pillDrop)
        // An open island draws the same band in the same place and takes over from here.
        .opacity(isVisible && !presence.isOpen ? 1 : 0)
        .animation(Island.quick, value: isVisible)
        .animation(Island.settle, value: counters)
    }
}

/// Where the island is drawn inside its window.
private struct DrawnSpan: PreferenceKey {
    static let defaultValue = CGRect.null
    // Views that say nothing count as an empty rectangle and must not wipe out the one that does.
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = value.union(nextValue()) }
}

private extension HorizontalAlignment {
    /// The middle of the notch.
    enum NotchCentre: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[HorizontalAlignment.center] }
    }

    static let notchCentre = HorizontalAlignment(NotchCentre.self)
}

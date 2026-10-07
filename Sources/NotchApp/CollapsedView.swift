import SessionCore
import SwiftUI

/// The island at rest: counters by state left of the notch and the usage ring right of it, or
/// both in a top-centre pill on screens without a notch. It reaches only as far as what it shows:
/// with no live sessions nothing is drawn left of the notch. Nothing in it moves while sessions
/// simply work.
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

    /// A wing has room for two kinds of counter; what is merely done gives way to the others.
    private var showsFinished: Bool {
        [counters.waiting, counters.working, counters.failed].filter { $0 > 0 }.count <= 1
    }

    /// What lies between the two sides: the notch, or the gap of the pill.
    private var middle: CGFloat {
        geometry.hasNotch ? geometry.notchWidth : (hasSessions && showsRing ? Island.pillGap : 0)
    }

    var body: some View {
        let edge = (geometry.hasNotch ? Island.shoulder : 0) + Island.collapsedEdge
        let gap = geometry.hasNotch ? Island.notchGap : 0
        HStack(spacing: 0) {
            if hasSessions {
                BandCounters(counters: counters, showsFinished: showsFinished)
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
        .padding(.horizontal, geometry.hasNotch ? 0 : Island.collapsedEdge)
        .frame(maxHeight: .infinity)
        .background(IslandBody(radius: geometry.collapsedRadius, hasShoulders: geometry.hasNotch))
        // The window is centred on the notch; so is the gap left for it, whatever stands beside it.
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .notchCentre, vertical: .center))
        .padding(.top, geometry.hasNotch ? 0 : Island.pillDrop)
        // An open island draws the same band in the same place and takes over from here.
        .opacity(isVisible && !presence.isOpen ? 1 : 0)
        .animation(Island.quick, value: isVisible)
        .animation(Island.settle, value: counters)
    }
}

private extension HorizontalAlignment {
    /// The middle of the notch.
    enum NotchCentre: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[HorizontalAlignment.center] }
    }

    static let notchCentre = HorizontalAlignment(NotchCentre.self)
}

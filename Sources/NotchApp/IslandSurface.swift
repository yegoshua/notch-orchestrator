import SessionCore
import SwiftUI

/// Which open islands are on screen. While one is, it draws the band itself and the collapsed
/// island steps aside.
@MainActor
final class IslandPresence: ObservableObject {
    @Published var listIsOpen = false
    @Published var cardIsOpen = false
    @Published var lineIsOpen = false
    /// How far the collapsed island is drawn, left to right inside its window. Nil while it is
    /// not drawn at all.
    var collapsedSpan: ClosedRange<CGFloat>?

    var isOpen: Bool { listIsOpen || cardIsOpen || lineIsOpen }
}

/// Keeps the window of an open island just larger than the island: room for its shadow and the
/// overshoot of the spring, and no more, since a window takes the clicks meant for what is under
/// it. It grows at once and shrinks only after the island has had time to settle.
@MainActor
final class IslandWindowSizer {
    private static let margin: CGFloat = 48
    private var shrinking: DispatchWorkItem?

    func fit(_ panel: NSPanel, to islandSize: CGSize, geometry: NotchGeometry, on screenFrame: CGRect) {
        let size = CGSize(
            width: islandSize.width + 2 * Island.shoulder + 2 * Self.margin,
            height: islandSize.height + Island.pillDrop + Self.margin)
        let frame = geometry.windowFrame(ofSize: size, on: screenFrame)
        shrinking?.cancel()
        shrinking = nil
        guard frame.height < panel.frame.height || frame.width < panel.frame.width else {
            panel.setFrame(frame, display: true)
            return
        }
        let work = DispatchWorkItem { [weak panel] in
            MainActor.assumeIsolated { panel?.setFrame(frame, display: true) }
        }
        shrinking = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Island.closeDuration, execute: work)
    }
}

/// The link between an open island and the window controller that shows it.
@MainActor
final class IslandStage: ObservableObject {
    /// Flipped by the controller; the island grows out of the notch or returns into it.
    @Published var isOpen = false
    /// The user asked for the island to stay open; the band says so with a pin.
    @Published var isPinned = false
    /// The band of the open island was clicked.
    var onBandClick: (() -> Void)?
    /// The island's size once it has grown, for telling whether the pointer is over it.
    private(set) var openSize = CGSize.zero
    var onOpenSizeChange: (() -> Void)?

    fileprivate func report(_ size: CGSize) {
        guard size != openSize else { return }
        openSize = size
        // Reported from inside a view update, where a window must not be resized.
        DispatchQueue.main.async { [weak self] in self?.onOpenSizeChange?() }
    }
}

/// An island that opens below the notch: the band on top, `content` under it. It starts as the
/// collapsed island exactly as that is drawn, which is only as wide as what it shows and so
/// seldom centred on the notch, and stretches to its content, so that opening reads as the notch growing and
/// not as a popover appearing. It is drawn hanging from the top centre of a window that is
/// somewhat larger than it.
struct IslandSurface<Content: View>: View {
    @ObservedObject var model: AppModel
    @ObservedObject var stage: IslandStage
    /// Read for where the collapsed island is drawn, which is where this one grows from and
    /// returns to.
    let presence: IslandPresence
    let geometry: NotchGeometry
    /// The width of the content, and of the island once open.
    let width: CGFloat
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0
    @State private var isTall = false
    @State private var isWide = false
    @State private var isRevealed = false

    private var bandHeight: CGFloat { geometry.frame.height }
    private var outline: CGFloat { geometry.hasNotch ? 2 * Island.shoulder : 0 }
    private var openHeight: CGFloat { min(bandHeight + contentHeight, maxHeight) }
    private var islandWidth: CGFloat { isWide ? width + outline : restWidth }

    /// The width of the collapsed island as drawn; its whole room while it is not drawn.
    private var restWidth: CGFloat {
        presence.collapsedSpan.map { $0.upperBound - $0.lowerBound } ?? geometry.frame.width + outline
    }

    /// How far the collapsed island's middle lies from the notch's.
    private var restOffset: CGFloat {
        presence.collapsedSpan.map { ($0.lowerBound + $0.upperBound - geometry.collapsedWindowFrame.width) / 2 } ?? 0
    }
    private var islandHeight: CGFloat { isTall ? openHeight : bandHeight }

    var body: some View {
        ZStack(alignment: .top) {
            IslandBody(radius: isTall ? Island.openRadius : geometry.collapsedRadius, hasShoulders: geometry.hasNotch)
                .shadow(color: .black.opacity(isTall ? 0.4 : 0), radius: 12, y: 14)
            VStack(spacing: 0) {
                BandRow(
                    counters: model.snapshot.counters, limit: model.limits.fiveHour,
                    showsRing: model.connectionStatus != .notConnected, isPinned: stage.isPinned)
                    .padding(.horizontal, isWide ? outline / 2 + Island.openPadding : geometry.collapsedEdge)
                    .frame(height: bandHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { stage.onBandClick?() }
                content
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                    })
                    .opacity(isRevealed ? 1 : 0)
                    .offset(y: isRevealed ? 0 : -10)
                    .scaleEffect(isRevealed ? 1 : 0.96, anchor: .top)
                    .blur(radius: isRevealed ? 0 : 5)
                    .frame(height: max(0, islandHeight - bandHeight), alignment: .top)
            }
            .frame(width: islandWidth, height: islandHeight, alignment: .top)
            .clipShape(IslandShape(
                radius: isTall ? Island.openRadius : geometry.collapsedRadius, hasShoulders: geometry.hasNotch))
        }
        .frame(width: islandWidth, height: islandHeight)
        .offset(x: isWide ? 0 : restOffset)
        .padding(.top, geometry.hasNotch ? 0 : Island.pillDrop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Content and edge move together when a card grows or the next one takes its place.
        .animation(Island.content, value: contentHeight)
        .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
        .onChange(of: stage.isOpen, initial: true) { _, isOpen in isOpen ? grow() : shrink() }
        .onChange(of: CGSize(width: width + outline, height: openHeight), initial: true) { _, size in
            stage.report(size)
        }
    }

    /// Height first, so the notch appears to pull downward; width follows; then the content.
    private func grow() {
        withAnimation(Island.stretch) { isTall = true }
        withAnimation(Island.stretch.delay(Island.widthLag)) { isWide = true }
        withAnimation(Island.content.delay(Island.contentDelay)) { isRevealed = true }
    }

    /// Content leaves first, the shape follows without overshoot.
    private func shrink() {
        guard isTall || isWide || isRevealed else { return }
        withAnimation(Island.quick) { isRevealed = false }
        withAnimation(Island.settle.delay(Island.shapeLag)) {
            isTall = false
            isWide = false
        }
    }
}

private struct ContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

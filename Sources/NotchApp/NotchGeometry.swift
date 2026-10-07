import AppKit

/// Where the island goes on a screen, in screen coordinates.
struct NotchGeometry: Equatable {
    static let fallbackHeight: CGFloat = 24

    /// The most room the collapsed island may take: the notch plus one wing on each side, or the
    /// pill. The shoulders at the notch reach a little further out on each side. What is drawn
    /// is as wide as its content only.
    var frame: CGRect
    /// Zero on screens without a notch, where the island is a top-centre pill instead.
    var notchWidth: CGFloat

    var hasNotch: Bool { notchWidth > 0 }

    var collapsedRadius: CGFloat { hasNotch ? Island.collapsedRadius : Island.pillRadius }

    /// The window of the collapsed island.
    var collapsedWindowFrame: CGRect {
        hasNotch
            ? frame.insetBy(dx: -Island.shoulder, dy: 0)
            : CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + Island.pillDrop)
    }

    /// The window of an open island of `size`, hanging from the top edge and centred on the notch.
    func windowFrame(ofSize size: CGSize, on screenFrame: CGRect) -> CGRect {
        CGRect(x: frame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Where an open island of `size` is drawn inside such a window.
    func openFrame(ofSize size: CGSize, on screenFrame: CGRect) -> CGRect {
        let top = screenFrame.maxY - (hasNotch ? 0 : Island.pillDrop)
        return CGRect(x: frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    init(screenFrame: CGRect, safeAreaTop: CGFloat, leftOfNotch: CGRect?, rightOfNotch: CGRect?, menuBarHeight: CGFloat) {
        if safeAreaTop > 0, let leftOfNotch, let rightOfNotch, rightOfNotch.minX > leftOfNotch.maxX {
            notchWidth = rightOfNotch.minX - leftOfNotch.maxX
            frame = CGRect(
                x: leftOfNotch.maxX - Island.wingWidth, y: screenFrame.maxY - safeAreaTop,
                width: notchWidth + 2 * Island.wingWidth, height: safeAreaTop)
        } else {
            notchWidth = 0
            let height = menuBarHeight > 0 ? menuBarHeight : Self.fallbackHeight
            let width = 2 * Island.wingWidth + Island.pillGap
            frame = CGRect(
                x: screenFrame.midX - width / 2, y: screenFrame.maxY - Island.pillDrop - height,
                width: width, height: height)
        }
    }

    /// How far the notch reaches down, in points. Displays with a notch are 16:10 below it: the
    /// strip that holds the notch is what the screen is taller than that (74 of 2234 pixels on a
    /// 16-inch MacBook Pro, so 37 points at its default scale). The system's safe area follows
    /// the menu bar instead and was seen to stop short of the hardware (32 points there).
    static func notchHeight(screenFrame: CGRect, safeAreaTop: CGFloat) -> CGFloat {
        guard safeAreaTop > 0 else { return 0 }
        // To the half point, which is a whole pixel on these displays; and two pixels short of
        // the strip, where the edge of the hardware was seen to lie.
        let strip = ((screenFrame.height - screenFrame.width * 10 / 16) * 2).rounded() / 2 - 1
        // Should a display not follow the rule, the system's figure is the better guess.
        return strip > safeAreaTop && strip <= safeAreaTop + Island.notchBeyondSafeArea ? strip : safeAreaTop
    }

    /// The part of `frame` the pointer has to rest on to open the list: what is drawn of the
    /// collapsed island, given as its span inside the collapsed window, and the notch itself.
    func hoverFrame(drawn span: ClosedRange<CGFloat>?) -> CGRect {
        guard let span else { return hasNotch ? notchFrame : .zero }
        let drawn = CGRect(
            x: collapsedWindowFrame.minX + span.lowerBound, y: frame.minY,
            width: span.upperBound - span.lowerBound, height: frame.height)
        return hasNotch ? drawn.union(notchFrame) : drawn
    }

    private var notchFrame: CGRect {
        CGRect(x: frame.midX - notchWidth / 2, y: frame.minY, width: notchWidth, height: frame.height)
    }

    init(screen: NSScreen) {
        // `defaults write <bundle id> notchHeightAdjust -float 1` adds that much to the island's
        // height at the notch, should a display not follow the rule; a negative value takes it off.
        let height = Self.notchHeight(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top)
        let adjust = max(-8, min(12, UserDefaults.standard.double(forKey: "notchHeightAdjust")))
        self.init(
            screenFrame: screen.frame, safeAreaTop: height > 0 ? height + adjust : 0,
            leftOfNotch: screen.auxiliaryTopLeftArea, rightOfNotch: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

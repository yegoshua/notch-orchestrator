import AppKit

/// Where the overlay goes on a screen, in screen coordinates.
struct NotchGeometry: Equatable {
    /// Room for the counters beside the notch.
    static let earWidth: CGFloat = 96
    static let pillWidth: CGFloat = 120
    static let fallbackHeight: CGFloat = 24

    /// The window: the notch plus one ear on each side, or the pill.
    var frame: CGRect
    /// Zero on screens without a notch, where the content is a top-centre pill instead.
    var notchWidth: CGFloat

    var hasNotch: Bool { notchWidth > 0 }

    init(screenFrame: CGRect, safeAreaTop: CGFloat, leftOfNotch: CGRect?, rightOfNotch: CGRect?, menuBarHeight: CGFloat) {
        if safeAreaTop > 0, let leftOfNotch, let rightOfNotch, rightOfNotch.minX > leftOfNotch.maxX {
            notchWidth = rightOfNotch.minX - leftOfNotch.maxX
            frame = CGRect(
                x: leftOfNotch.maxX - Self.earWidth, y: screenFrame.maxY - safeAreaTop,
                width: notchWidth + 2 * Self.earWidth, height: safeAreaTop)
        } else {
            notchWidth = 0
            let height = menuBarHeight > 0 ? menuBarHeight : Self.fallbackHeight
            frame = CGRect(
                x: screenFrame.midX - Self.pillWidth / 2, y: screenFrame.maxY - height,
                width: Self.pillWidth, height: height)
        }
    }

    init(screen: NSScreen) {
        self.init(
            screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            leftOfNotch: screen.auxiliaryTopLeftArea, rightOfNotch: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

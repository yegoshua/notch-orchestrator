import AppKit

/// Where the island goes on a screen, in screen coordinates.
struct NotchGeometry: Equatable {
    static let fallbackHeight: CGFloat = 24

    /// The collapsed island: the notch plus one wing on each side, or the pill. The shoulders at
    /// the notch reach a little further out on each side.
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

    init(screen: NSScreen) {
        // The system's figure for the notch follows the menu bar and can differ from what the
        // hardware shows. `defaults write <bundle id> notchHeightAdjust -float 6` adds that much
        // to the island's height at the notch; a negative value takes it off.
        let inset = screen.safeAreaInsets.top
        let adjust = max(-8, min(12, UserDefaults.standard.double(forKey: "notchHeightAdjust")))
        self.init(
            screenFrame: screen.frame, safeAreaTop: inset > 0 ? inset + adjust : 0,
            leftOfNotch: screen.auxiliaryTopLeftArea, rightOfNotch: screen.auxiliaryTopRightArea,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

import AppKit
import SessionCore
import SwiftUI

/// The design tokens of the island: one place for every colour, size, radius and spring.
enum Island {
    // MARK: Colour

    static let well = Color(hex: 0x0B0B0B)
    static let wellRaised = Color(hex: 0x111111)
    static let buttonTop = Color(hex: 0x262626)
    static let buttonBottom = Color(hex: 0x1C1C1C)
    static let text = Color(hex: 0xF2F1EE)
    static let text2 = Color(hex: 0xA9A8A4)
    static let text3 = Color(hex: 0x8A8986)
    static let text4 = Color(hex: 0x6B6A66)
    static let text5 = Color(hex: 0x4A4946)
    /// Lines inside the island: between sections and around wells.
    static let divider = Color(hex: 0x1E1E1E)
    /// The only accent: something waits for the user.
    static let waiting = Color(hex: 0xF2B441)
    static let working = Color(hex: 0xC8C7C2)
    static let finished = Color(hex: 0x7FB79A)
    static let failed = Color(hex: 0xCF7F73)
    static let unknown = Color(hex: 0x6B6A66)
    /// "Failed" and a limit nearly reached, as text: lighter than the mark so that it reads at 11 pt.
    static let failedText = Color(hex: 0xE3A49A)
    /// A usage figure at rest, and one that deserves a look.
    static let usageCalm = Color(hex: 0xB4B3AE)
    static let usageHigh = Color(hex: 0xECEBE7)
    static let ringTrack = Color(hex: 0x2A2A2A)
    static let barTrack = Color(hex: 0x222222)
    /// The line that ties a subagent to its session.
    static let branch = Color(hex: 0x2C2C2C)
    static let rowHover = [Color(hex: 0x1A1A1A), Color(hex: 0x151515)]
    static let option = Color(hex: 0x0E0E0E)
    static let optionLit = [Color(hex: 0x1C1C1C), Color(hex: 0x161616)]
    static let field = Color(hex: 0x0D0D0D)

    static func color(_ state: SessionState) -> Color {
        switch state {
        case .waitingForPermission, .waitingForAnswer: waiting
        case .working: working
        case .finishedTurn: finished
        case .failed: failed
        case .unknown: unknown
        }
    }

    // MARK: Type

    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let meta = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let small = Font.system(size: 11)
    static let detail = Font.system(size: 11.5)
    static let label = Font.system(size: 11, weight: .semibold)
    static let smallCode = Font.system(size: 10.5, design: .monospaced)
    static let waitingCounter = Font.system(size: 12, weight: .bold).monospacedDigit()
    static let listTitle = Font.system(size: 12.5, weight: .semibold)
    static let code = Font.system(size: 11.5, design: .monospaced)
    static let keycap = Font.system(size: 10, design: .monospaced)
    /// Lines of code sit this far apart, which takes `codeLineSpacing` on top of the font's own.
    static let codeLineHeight: CGFloat = 18
    static let codeLineSpacing: CGFloat = 4

    // MARK: Size and spacing

    static let wingWidth: CGFloat = 92
    static let wingPadding: CGFloat = 10
    /// The collapsed island reaches only as far as what it shows: this much past it on the
    /// outside, and this much between it and the notch.
    static let collapsedEdge: CGFloat = 8
    static let notchGap: CGFloat = 7
    /// The companion's height, and the room between it and the counters.
    static let companionSize: CGFloat = 20
    static let companionGap: CGFloat = 8
    /// How much further down than the system's safe area a notch is believed to reach.
    static let notchBeyondSafeArea: CGFloat = 6
    static let openPadding: CGFloat = 16
    static let cardWidth: CGFloat = 520
    static let listWidth: CGFloat = 540
    static let maxHeight: CGFloat = 420
    /// Taller than the list may get: a card never scrolls as a whole.
    static let cardMaxHeight: CGFloat = 520
    static let buttonHeight: CGFloat = 28
    static let rowHeight: CGFloat = 42
    static let subagentHeight: CGFloat = 26
    /// The gap between the wings of the pill on a screen without a notch.
    static let pillGap: CGFloat = 16
    /// How far the pill hangs below the top edge.
    static let pillDrop: CGFloat = 5
    /// The row of the transient line, and how much wider than the collapsed island it is.
    static let lineHeight: CGFloat = 32
    static let lineGrowth: CGFloat = 36

    // MARK: Radii

    static let collapsedRadius: CGFloat = 11
    static let pillRadius: CGFloat = 16
    static let openRadius: CGFloat = 24
    static let shoulder: CGFloat = 7
    static let wellRadius: CGFloat = 9
    static let buttonRadius: CGFloat = 8
    static let optionRadius: CGFloat = 10
    static let keycapRadius: CGFloat = 4.5
    static let chipRadius: CGFloat = 5

    // MARK: Motion

    /// The shape growing out of the notch.
    static let stretch = Animation.spring(response: 0.46, dampingFraction: 0.78)
    /// The shape going back: no overshoot, so it settles like hardware.
    static let settle = Animation.spring(response: 0.34, dampingFraction: 1.0)
    static let content = Animation.spring(response: 0.30, dampingFraction: 0.92)
    static let quick = Animation.spring(response: 0.16, dampingFraction: 1.0)
    static let digit = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let ring = Animation.spring(response: 0.90, dampingFraction: 1.0)
    /// Width follows height when growing; content waits for the shape.
    static let widthLag: TimeInterval = 0.03
    static let contentDelay: TimeInterval = 0.09
    /// On the way back the shape waits for the content to leave.
    static let shapeLag: TimeInterval = 0.04
    /// From the start of closing until nothing of the open island is left to see.
    static let closeDuration: TimeInterval = 0.42
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Shape

/// The black body. At the notch its top edge is flush with the screen and flares into concave
/// shoulders, so it reads as part of the hardware; as a pill all four corners are rounded.
struct IslandShape: Shape {
    var radius: CGFloat
    var hasShoulders: Bool

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let s = hasShoulders ? Island.shoulder : 0
        let x0 = rect.minX + s, x1 = rect.maxX - s, top = rect.minY, bottom = rect.maxY
        // A continuous corner: it starts turning earlier than a circular one of the same radius.
        let k = min(radius * 1.35, rect.height / 2, (x1 - x0) / 2), q = min(radius * 0.22, k)
        var path = Path()
        if hasShoulders {
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: top))
            path.addQuadCurve(to: CGPoint(x: x1, y: top + s), control: CGPoint(x: x1, y: top))
        } else {
            path.move(to: CGPoint(x: x0 + k, y: top))
            path.addLine(to: CGPoint(x: x1 - k, y: top))
            path.addCurve(
                to: CGPoint(x: x1, y: top + k), control1: CGPoint(x: x1 - q, y: top), control2: CGPoint(x: x1, y: top + q))
        }
        path.addLine(to: CGPoint(x: x1, y: bottom - k))
        path.addCurve(
            to: CGPoint(x: x1 - k, y: bottom), control1: CGPoint(x: x1, y: bottom - q), control2: CGPoint(x: x1 - q, y: bottom))
        path.addLine(to: CGPoint(x: x0 + k, y: bottom))
        path.addCurve(
            to: CGPoint(x: x0, y: bottom - k), control1: CGPoint(x: x0 + q, y: bottom), control2: CGPoint(x: x0, y: bottom - q))
        if hasShoulders {
            path.addLine(to: CGPoint(x: x0, y: top + s))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: x0, y: top))
        } else {
            path.addLine(to: CGPoint(x: x0, y: top + k))
            path.addCurve(
                to: CGPoint(x: x0 + k, y: top), control1: CGPoint(x: x0, y: top + q), control2: CGPoint(x: x0 + q, y: top))
        }
        path.closeSubpath()
        return path
    }
}

/// The body filled, with a faint rim of light on its lower edge so that it stays a solid object
/// on a dark wallpaper.
struct IslandBody: View {
    var radius: CGFloat
    var hasShoulders: Bool

    var body: some View {
        let shape = IslandShape(radius: radius, hasShoulders: hasShoulders)
        shape.fill(LinearGradient(colors: [.black, Color(hex: 0x070707)], startPoint: .top, endPoint: .bottom))
            .overlay(
                // Drawn twice as wide and cut at the edge, so only the inner half shows.
                shape.stroke(Color.white.opacity(0.14), lineWidth: 1.5)
                    .clipShape(shape)
                    .mask(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 26)
                    })
    }
}

// MARK: - State marks

/// A state as a shape, 8 pt: the shape carries the state, colour only reinforces it. Nothing here
/// moves: sessions that simply work must not draw the eye.
struct StateMark: View {
    let state: SessionState
    var size: CGFloat = 8

    var body: some View {
        let color = Island.color(state)
        Group {
            switch state {
            case .waitingForPermission, .waitingForAnswer:
                Circle().fill(color)
            case .working:
                Circle().strokeBorder(color, lineWidth: 1.5)
            case .finishedTurn:
                MarkPath(points: [(0.11, 0.525), (0.38, 0.81), (0.89, 0.19)])
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            case .failed:
                ZStack {
                    MarkPath(points: [(0.15, 0.15), (0.85, 0.85)]).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    MarkPath(points: [(0.85, 0.15), (0.15, 0.85)]).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            case .unknown:
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [1.7, 1.7]))
            }
        }
        .frame(width: state == .finishedTurn ? size * 1.125 : size, height: size)
    }
}

private struct MarkPath: Shape {
    /// In units of the frame.
    let points: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let at = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }
        return path
    }
}

// MARK: - The band

/// The companion and counters by state on the left and the usage ring on the right: the content
/// of the collapsed island, and the top row of every open one.
struct BandRow: View {
    let counters: Counters
    let limit: LimitWindow
    /// Without a connection no figure can arrive, so no ring is drawn.
    var showsRing = true
    /// The open island was told to stay open.
    var isPinned = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Island.companionGap) {
                Companion(mood: CompanionMood(counters: counters))
                BandCounters(counters: counters)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Island.text3)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                    .accessibilityLabel("Stays open")
            }
            if showsRing { LimitRing(window: limit) }
        }
        .animation(Island.quick, value: isPinned)
    }
}

/// The counters by state. Empty when there is nothing to count.
struct BandCounters: View {
    let counters: Counters
    /// Nil leaves it to the room there is.
    var showsFinished: Bool?

    var body: some View {
        if let showsFinished {
            counterRow(showsFinished: showsFinished)
        } else {
            ViewThatFits(in: .horizontal) {
                counterRow(showsFinished: true)
                // Too many kinds at once for a wing: what is merely done gives way.
                counterRow(showsFinished: false)
            }
        }
    }

    private func counterRow(showsFinished: Bool) -> some View {
        HStack(spacing: 7) {
            if counters.waiting > 0 {
                // The one counter that asks for something: the only filled capsule.
                HStack(spacing: 4) {
                    Circle().fill(.black).frame(width: 7, height: 7)
                    Text("\(counters.waiting)")
                        .font(Island.waitingCounter)
                        .foregroundStyle(.black)
                        .contentTransition(.numericText(value: Double(counters.waiting)))
                }
                .padding(.leading, 6)
                .padding(.trailing, 7)
                .frame(height: 20)
                .background(Capsule().fill(LinearGradient(
                    colors: [Color(hex: 0xF8C96A), Color(hex: 0xEFAE37)], startPoint: .top, endPoint: .bottom)))
                .transition(.scale(scale: 0.55, anchor: .leading).combined(with: .opacity))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(counters.waiting) waiting for you")
            }
            if counters.working > 0 { counter(counters.working, .working, "working") }
            if showsFinished, counters.finished > 0 { counter(counters.finished, .finishedTurn, "just finished") }
            if counters.failed > 0 { counter(counters.failed, .failed, "failed") }
        }
        .fixedSize()
        .animation(Island.digit, value: counters)
    }

    private func counter(_ count: Int, _ state: SessionState, _ name: String) -> some View {
        HStack(spacing: 4) {
            StateMark(state: state)
            Text("\(count)")
                .font(Island.meta)
                .foregroundStyle(Island.working)
                .contentTransition(.numericText(value: Double(count)))
        }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(name)")
    }
}

// MARK: - Controls

/// A key, drawn as one.
struct Keycap: View {
    let text: String
    /// On the light body of a primary button.
    var onLight = false

    var body: some View {
        Text(text)
            .font(Island.keycap)
            .foregroundStyle(onLight ? Color(hex: 0x3A3936) : Island.text2)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 17)
            .background {
                let shape = RoundedRectangle(cornerRadius: Island.keycapRadius, style: .continuous)
                if onLight {
                    shape.fill(Color.black.opacity(0.08))
                } else {
                    shape.fill(LinearGradient(
                        colors: [Color(hex: 0x2E2E2E), Color(hex: 0x232323)], startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
                }
            }
    }
}

/// A word naming what kind of thing a card is about.
struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Island.smallCode)
            .foregroundStyle(Island.text2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: Island.chipRadius, style: .continuous).fill(Color(hex: 0x181818)))
            .overlay(RoundedRectangle(cornerRadius: Island.chipRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct IslandButtonStyle: ButtonStyle {
    enum Kind {
        /// The tactile default. Allow and Deny look alike on purpose: neither invites a click.
        case standard
        /// For a single forward action, such as sending what was typed.
        case primary
        /// No body until hovered: an action that is there but does not ask to be taken.
        case quiet
    }

    var kind = Kind.standard
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Body(kind: kind, isPressed: configuration.isPressed, isEnabled: isEnabled, label: configuration.label)
    }

    private struct Body<Label: View>: View {
        let kind: Kind
        let isPressed: Bool
        let isEnabled: Bool
        let label: Label
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Island.buttonRadius, style: .continuous)
            let isLit = isHovered && isEnabled
            label
                .font(.system(size: 12, weight: kind == .primary ? .semibold : .medium))
                .foregroundStyle(foreground(isLit: isLit))
                .lineLimit(1)
                .padding(.horizontal, kind == .quiet ? 7 : 11)
                .frame(height: Island.buttonHeight)
                .background {
                    switch kind {
                    case .standard:
                        shape.fill(isPressed ? AnyShapeStyle(Color(hex: 0x141414)) : AnyShapeStyle(LinearGradient(
                            colors: isLit ? [Color(hex: 0x2D2D2D), Color(hex: 0x232323)] : [Island.buttonTop, Island.buttonBottom],
                            startPoint: .top, endPoint: .bottom)))
                            .overlay(shape.strokeBorder(Color.white.opacity(isPressed ? 0.06 : 0.09), lineWidth: 0.5))
                            .shadow(color: .black.opacity(isPressed ? 0 : 0.7), radius: 1, y: 1)
                    case .primary:
                        shape.fill(isPressed ? AnyShapeStyle(Color(hex: 0xD6D5D0)) : AnyShapeStyle(LinearGradient(
                            colors: [Color(hex: 0xFBFAF7), Color(hex: 0xE3E2DD)], startPoint: .top, endPoint: .bottom)))
                            // Unavailable, it must not look like the one thing to press.
                            .opacity(isEnabled ? 1 : 0.16)
                    case .quiet:
                        shape.fill(Color.white.opacity(isLit ? 0.05 : 0))
                    }
                }
                .scaleEffect(isPressed && isEnabled ? 0.965 : 1)
                .contentShape(shape)
                .background(HoverArea { isHovered = $0 })
                .animation(Island.quick, value: isPressed)
                .animation(Island.quick, value: isHovered)
        }

        private func foreground(isLit: Bool) -> Color {
            if !isEnabled { return kind == .primary ? Island.text3 : Island.text4 }
            switch kind {
            case .primary: return Color(hex: 0x0A0A0A)
            case .quiet: return isLit ? Island.text : Island.text2
            case .standard: return Island.text
            }
        }
    }
}

/// The label of a button with the key that does the same, when there is one.
struct ButtonLabel: View {
    let title: String
    var key: String?
    var onLight = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
            if let key { Keycap(text: key, onLight: onLight).opacity(isEnabled ? 1 : 0.35) }
        }
    }
}

/// A sunken box for a command, a diff or a text field.
struct Well<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(LinearGradient(
                colors: [Island.well, Island.wellRaised], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Color(hex: 0x232323)))
            .clipShape(shape)
    }
}

/// Tells whether the pointer is over a view. The island's windows are never key, and SwiftUI's
/// own hover only follows the pointer in a key window.
struct HoverArea: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) { view.onChange = onChange }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        // Only watches: clicks belong to what is drawn on top.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Buttons in a window that is not key answer the first click instead of swallowing it.
final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

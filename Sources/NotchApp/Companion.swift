import SessionCore
import SwiftUI

/// What the companion is up to. One mood for all sessions: the one that matters most wins, so
/// a session waiting for the user is never hidden behind others that merely work.
enum CompanionMood: Equatable {
    /// No live sessions.
    case asleep
    case working
    /// A session waits for the user.
    case waiting
    /// Sessions are done and none works.
    case finished
    case failed

    init(counters: Counters) {
        if counters.waiting > 0 {
            self = .waiting
        } else if counters.failed > 0 {
            self = .failed
        } else if counters.working > 0 {
            self = .working
        } else if counters.finished > 0 {
            self = .finished
        } else {
            self = .asleep
        }
    }

    var label: String {
        switch self {
        case .asleep: "No live sessions"
        case .working: "Sessions are working"
        case .waiting: "A session waits for you"
        case .finished: "Sessions have finished"
        case .failed: "A session failed"
        }
    }
}

/// The small orange character that lives in the band: asleep when nothing runs, typing on its
/// laptop while sessions work, hopping and waving when one waits for the user, swaying when the
/// work is done, and slumped with a drop of sweat when something failed. Drawn in a canvas and
/// driven by the clock, so it costs no view updates.
struct Companion: View {
    let mood: CompanionMood
    var size: CGFloat = Island.companionSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                CompanionDrawing(mood: mood, t: t, s: size).draw(in: &context, size: canvasSize)
            }
        }
        // Room around the body for hops, a waving arm and the z's; the box itself never changes
        // size, so the band around it stays put.
        .frame(width: size * 1.5, height: size * 1.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mood.label)
    }
}

/// One frame of the companion at time `t`, in a box `s` points tall.
private struct CompanionDrawing {
    let mood: CompanionMood
    let t: TimeInterval
    let s: CGFloat

    private static let skin = Color(hex: 0xE07A52)
    private static let skinShade = Color(hex: 0xC9643F)
    private static let eye = Color(hex: 0x1B1410)
    private static let laptop = Color(hex: 0x4A4A4A)
    private static let screen = Color(hex: 0x9CC4E8)
    private static let sweat = Color(hex: 0x7FB3E6)

    // The body in units of `s`: a rounded block standing on two short legs.
    private var bodyWidth: CGFloat { 0.74 * s }
    private var bodyHeight: CGFloat { 0.56 * s }
    private var legHeight: CGFloat { 0.1 * s }
    private var corner: CGFloat { 0.17 * s }

    /// Between 0 and 1, `period` seconds long.
    private func phase(_ period: Double, offset: Double = 0) -> Double {
        ((t + offset) / period).truncatingRemainder(dividingBy: 1)
    }

    private func wave(_ period: Double, offset: Double = 0) -> CGFloat {
        CGFloat(sin((t / period + offset) * 2 * .pi))
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        // Everything is drawn around the point where the feet meet the ground, placed so that
        // the body sits at the middle of the box.
        var c = context
        c.translateBy(x: size.width / 2, y: size.height / 2 + 0.36 * s)
        switch mood {
        case .asleep: drawAsleep(&c)
        case .working: drawWorking(&c)
        case .waiting: drawWaiting(&c)
        case .finished: drawFinished(&c)
        case .failed: drawFailed(&c)
        }
    }

    // MARK: Moods

    private func drawAsleep(_ c: inout GraphicsContext) {
        // Slow breathing, from the ground up.
        let breath = 1 + 0.035 * wave(2.8)
        var body = c
        body.scaleBy(x: 1 / sqrt(breath), y: breath)
        drawLegs(&body)
        drawBody(&body, arms: .down)
        drawEyes(&body, .closed)
        // Two z's float up from the head, one after the other.
        for offset in [0.0, 1.1] {
            let p = phase(2.2, offset: offset)
            let rise = CGFloat(p) * 0.28 * s
            var z = c
            z.opacity = p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85
            z.draw(
                Text("z").font(.system(size: 0.3 * s, weight: .bold)).foregroundColor(Self.skin),
                at: CGPoint(x: bodyWidth / 2 + 0.06 * s + rise * 0.3, y: -legHeight - bodyHeight - 0.02 * s - rise))
        }
    }

    private func drawWorking(_ c: inout GraphicsContext) {
        var body = c
        // A faint bob with the typing.
        body.translateBy(x: 0, y: 0.25 * wave(0.9))
        drawLegs(&body)
        drawBody(&body, arms: .none)
        drawEyes(&body, .down)
        // The laptop stands in front, hands tapping on it in turn.
        var laptop = c
        let base = CGRect(x: -0.32 * s, y: -legHeight - 0.02 * s, width: 0.64 * s, height: 0.07 * s)
        let screen = CGRect(x: -0.27 * s, y: -legHeight - 0.25 * s, width: 0.54 * s, height: 0.23 * s)
        laptop.fill(Path(roundedRect: screen, cornerRadius: 0.04 * s, style: .continuous), with: .color(Self.laptop))
        laptop.fill(
            Path(roundedRect: screen.insetBy(dx: 0.035 * s, dy: 0.035 * s), cornerRadius: 0.02 * s, style: .continuous),
            with: .color(Self.screen.opacity(0.85)))
        // A line of text that is still being written.
        let typed = CGFloat(phase(2.6))
        laptop.fill(
            Path(CGRect(x: screen.minX + 0.07 * s, y: screen.minY + 0.07 * s, width: 0.4 * s * min(1, typed * 1.3), height: 0.03 * s)),
            with: .color(Self.laptop.opacity(0.8)))
        laptop.fill(Path(roundedRect: base, cornerRadius: 0.02 * s, style: .continuous), with: .color(Self.laptop))
        for (side, offset) in [(-1.0, 0.0), (1.0, 0.5)] {
            let tap = max(0, wave(0.36, offset: offset)) * 0.07 * s
            drawHand(&laptop, at: CGPoint(x: CGFloat(side) * 0.17 * s, y: -legHeight - 0.09 * s + tap))
        }
    }

    private func drawWaiting(_ c: inout GraphicsContext) {
        // Hops: up in the air, squashed on landing.
        let hop = abs(wave(0.76))
        let squash = pow(1 - hop, 3) * 0.14
        var body = c
        body.translateBy(x: 0, y: -hop * 0.16 * s)
        body.scaleBy(x: 1 + squash, y: 1 - squash)
        drawLegs(&body)
        drawBody(&body, arms: .waving(angle: Angle(degrees: Double(-128 + 16 * wave(0.38)))))
        drawEyes(&body, .wide)
    }

    private func drawFinished(_ c: inout GraphicsContext) {
        // A content sway from the feet, and a small bounce with it.
        var body = c
        body.translateBy(x: 0, y: -0.03 * s * (1 + wave(0.6)))
        body.rotate(by: Angle(degrees: Double(7 * wave(1.2))))
        drawLegs(&body)
        drawBody(&body, arms: .up)
        drawEyes(&body, .happy)
    }

    private func drawFailed(_ c: inout GraphicsContext) {
        // Slumped to one side, with a drop of sweat running down now and then.
        var body = c
        body.rotate(by: Angle(degrees: 8))
        body.translateBy(x: 0, y: 0.03 * s)
        drawLegs(&body)
        drawBody(&body, arms: .down)
        drawEyes(&body, .low)
        let p = phase(2.4)
        if p < 0.6 {
            var drop = c
            drop.opacity = p < 0.1 ? p / 0.1 : 1 - max(0, p - 0.45) / 0.15
            let y = -legHeight - bodyHeight + 0.1 * s + CGFloat(p / 0.6) * 0.3 * s
            var path = Path()
            let r = 0.055 * s
            path.move(to: CGPoint(x: 0, y: -r * 1.8))
            path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: r, y: -r))
            path.addArc(center: .zero, radius: r, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            path.addQuadCurve(to: CGPoint(x: 0, y: -r * 1.8), control: CGPoint(x: -r, y: -r))
            drop.translateBy(x: bodyWidth / 2 + 0.07 * s, y: y)
            drop.fill(path, with: .color(Self.sweat))
        }
    }

    // MARK: Parts

    private enum Arms {
        case none, down, up, waving(angle: Angle)
    }

    private enum Eyes {
        case open, wide, closed, down, low, happy
    }

    private func drawLegs(_ c: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            let rect = CGRect(x: CGFloat(side) * 0.2 * s - 0.065 * s, y: -legHeight - 0.02 * s, width: 0.13 * s, height: legHeight + 0.02 * s)
            c.fill(Path(roundedRect: rect, cornerRadius: 0.04 * s, style: .continuous), with: .color(Self.skinShade))
        }
    }

    private func drawBody(_ c: inout GraphicsContext, arms: Arms) {
        let rect = CGRect(x: -bodyWidth / 2, y: -legHeight - bodyHeight, width: bodyWidth, height: bodyHeight)
        let armSize = CGSize(width: 0.11 * s, height: 0.26 * s)
        let shoulderY = rect.minY + 0.26 * bodyHeight
        func arm(_ c: inout GraphicsContext, side: CGFloat, angle: Angle) {
            var a = c
            a.translateBy(x: side * (bodyWidth / 2 - 0.02 * s), y: shoulderY)
            a.rotate(by: angle)
            let rect = CGRect(x: -armSize.width / 2, y: -0.02 * s, width: armSize.width, height: armSize.height)
            a.fill(Path(roundedRect: rect, cornerRadius: armSize.width / 2, style: .continuous), with: .color(Self.skinShade))
        }
        switch arms {
        case .none:
            break
        case .down:
            arm(&c, side: -1, angle: .degrees(12))
            arm(&c, side: 1, angle: .degrees(-12))
        case .up:
            arm(&c, side: -1, angle: .degrees(150))
            arm(&c, side: 1, angle: .degrees(-150))
        case .waving(let angle):
            arm(&c, side: -1, angle: .degrees(14))
            arm(&c, side: 1, angle: angle)
        }
        c.fill(Path(roundedRect: rect, cornerRadius: corner, style: .continuous), with: .color(Self.skin))
    }

    private func drawEyes(_ c: inout GraphicsContext, _ eyes: Eyes) {
        let top = -legHeight - bodyHeight
        let centreY = top + 0.4 * bodyHeight
        for side in [-1.0, 1.0] {
            let x = CGFloat(side) * 0.17 * s
            switch eyes {
            case .open, .wide, .down, .low:
                let height = eyes == .wide ? 0.24 * s : eyes == .low ? 0.1 * s : eyes == .down ? 0.16 * s : 0.19 * s
                let drop = eyes == .down ? 0.02 * s : eyes == .low ? 0.05 * s : 0
                let rect = CGRect(x: x - 0.045 * s, y: centreY - height / 2 + drop, width: 0.09 * s, height: height)
                c.fill(Path(roundedRect: rect, cornerRadius: 0.045 * s, style: .continuous), with: .color(Self.eye))
            case .closed:
                var path = Path()
                path.move(to: CGPoint(x: x - 0.06 * s, y: centreY + 0.02 * s))
                path.addLine(to: CGPoint(x: x + 0.06 * s, y: centreY + 0.02 * s))
                c.stroke(path, with: .color(Self.eye), style: StrokeStyle(lineWidth: 0.045 * s, lineCap: .round))
            case .happy:
                var path = Path()
                path.addArc(
                    center: CGPoint(x: x, y: centreY + 0.03 * s), radius: 0.07 * s,
                    startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                c.stroke(path, with: .color(Self.eye), style: StrokeStyle(lineWidth: 0.05 * s, lineCap: .round))
            }
        }
    }

    private func drawHand(_ c: inout GraphicsContext, at point: CGPoint) {
        let rect = CGRect(x: point.x - 0.06 * s, y: point.y - 0.06 * s, width: 0.12 * s, height: 0.12 * s)
        c.fill(Path(roundedRect: rect, cornerRadius: 0.05 * s, style: .continuous), with: .color(Self.skinShade))
    }
}

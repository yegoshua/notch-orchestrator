// A piece of the app's own source, for the editor behind "Without the mouse":
// Sources/NotchApp/Companion.swift, the moods of the companion.
export const COMPANION_SWIFT = String.raw`    // MARK: Moods

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
            z.draw(Text("z").font(.system(size: 0.3 * s, weight: .bold)), at: head(rise))
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
    }`;

/** The line of the file the piece starts at, and the files beside it. */
export const FIRST_LINE = 106;
export const FILES = [
  'AppModel.swift', 'CollapsedView.swift', 'Companion.swift', 'ExpandedPanel.swift', 'HookReceiver.swift', 'Hotkey.swift',
  'IslandKit.swift', 'LimitRing.swift', 'NotchPanel.swift', 'PipelinePoller.swift', 'RequestCardView.swift', 'SessionListView.swift',
];
export const OPEN_FILE = 'Companion.swift';
